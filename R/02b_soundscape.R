#' Stage 2b: Soundscape Analysis (Indices & Summaries)
#'
#' Implementation of ecoacoustic soundscape indices following Bradfer-Lawrence
#' et al. (2019) guidelines. Computes core acoustic indices with 1-minute
#' sub-windowing, checkpointing, multi-core parallel processing, and
#' timezone-aware hourly/diel summarization. Supports WAV and FLAC via
#' \code{\link{pam_read_audio}} / \code{\link{pam_list_audio}}.
#'
#' @name soundscape
NULL

# Quiet R CMD check NOTES for data.table non-standard evaluation
if (getRversion() >= "2.15.1") {
  utils::globalVariables(c(
    "file_id", "..meta_cols", "window_start_sec",
    "start_time_utc", "window_datetime_utc", "hour",
    "diel_phase", "grid"
  ))
}

#' Safely Extract a Single Numeric Value from Soundecology/Seewave Returns
#'
#' @param x An object returned by a soundecology/seewave function.
#' @return A length-1 numeric, or NA_real_.
#' @export
to_scalar_num <- function(x) {
  if (is.null(x)) return(NA_real_)
  if (is.list(x) || is.matrix(x) || is.data.frame(x)) return(NA_real_)
  if (length(x) != 1L) return(NA_real_)
  val <- suppressWarnings(as.numeric(x))
  if (length(val) != 1L || is.na(val) || is.nan(val)) return(NA_real_)
  val
}

#' Helper to Safely Extract Scalar Numerical Values from Soundecology Returns
#'
#' @param res A list returned by a soundecology function.
#' @param candidates Character vector of preferred element names.
#' @return A length-1 numeric, or NA_real_.
#' @keywords internal
get_soundeco_val <- function(res, candidates) {
  if (is.null(res) || !is.list(res)) return(NA_real_)
  for (cand in candidates) {
    if (!is.null(res[[cand]])) {
      val <- to_scalar_num(res[[cand]])
      if (!is.na(val)) return(val)
    }
  }
  for (nm in names(res)) {
    val <- to_scalar_num(res[[nm]])
    if (!is.na(val)) return(val)
  }
  NA_real_
}

#' Build a cleanroom function environment for PSOCK workers
#'
#' Prevents workers from loadNamespace()-ing an outdated installed pamflow
#' copy when closures are serialized. All helper functions are re-parented
#' to an isolated env whose parent is baseenv().
#'
#' @param funs Named list of functions to export.
#' @return An environment suitable for clusterExport / worker closures.
#' @keywords internal
pam_soundscape_export_env <- function(funs) {
  export_env <- new.env(parent = baseenv())
  for (nm in names(funs)) {
    export_env[[nm]] <- funs[[nm]]
  }
  for (nm in names(funs)) {
    f <- export_env[[nm]]
    if (is.function(f)) {
      environment(f) <- export_env
      export_env[[nm]] <- f
    }
  }
  export_env
}

#' Compute Ecoacoustic Soundscape Indices for a Single Audio File
#'
#' Reads WAV or FLAC via \code{\link{pam_read_audio}}, optionally downsamples
#' to 24 kHz, applies a high-pass filter at sub-window level, and computes
#' configured acoustic indices (ACI, ADI, AEve, Bio, H, M, NDSI).
#'
#' @param audio_path Character. Path to input audio file (`.wav` or `.flac`).
#' @param low_stop_hz Numeric. Highpass low-stop frequency in Hz (default 500).
#' @param cfg List. Parsed configuration structure from \code{\link{pam_config_read}}.
#' @param window_sec Numeric. Optional window duration in seconds.
#'
#' @return A \code{data.table} with file/window metadata and index values.
#' @examples
#' \donttest{
#' if (requireNamespace("soundecology", quietly = TRUE)) {
#'   ex <- pam_example_project()
#'   # the example tones are only 2 s long and 8 kHz, so some indices come out as NA
#'   pam_soundscape_one(ex$files[1], cfg = ex$cfg)
#' }
#' }
#' @export
pam_soundscape_one <- function(audio_path, low_stop_hz = NULL, cfg = NULL, window_sec = NULL) {
  stage <- "02b_soundscape"
  log_dir <- if (!is.null(cfg) && !is.null(cfg$paths) && !is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()
  if (!file.exists(audio_path)) {
    stop(glue::glue("Audio file not found: {audio_path}"))
  }

  sc_cfg <- pam_or(cfg$soundscape, cfg$settings$soundscape)
  low_stop_hz <- to_scalar_num(pam_or(low_stop_hz, pam_or(sc_cfg$low_stop_hz, 500)))
  anthro_range <- pam_or(sc_cfg$anthro_range, c(1000, 2000))
  bio_range <- pam_or(sc_cfg$bio_range, c(2000, 11000))

  win_sec <- to_scalar_num(pam_or(
    window_sec,
    pam_or(
      if (!is.null(sc_cfg$window_mins)) sc_cfg$window_mins * 60 else NULL,
      pam_or(sc_cfg$window_sec, 600)
    )
  ))
  sub_win_sec <- to_scalar_num(pam_or(sc_cfg$sub_window_sec, 60))

  file_id <- tools::file_path_sans_ext(basename(audio_path))

  wave <- tryCatch(
    pam_read_audio(audio_path),
    error = function(e) {
      stop(glue::glue("Failed to read audio file '{audio_path}': {e$message}"))
    }
  )

  target_rate <- 24000
  if (wave@samp.rate > target_rate) {
    wave <- tryCatch(
      tuneR::downsample(wave, target_rate),
      error = function(e) wave
    )
  }

  dur_sec <- length(wave@left) / wave@samp.rate

  if (!is.na(win_sec) && win_sec > 0 && dur_sec > win_sec) {
    starts <- seq(0, dur_sec - 1e-3, by = win_sec)
  } else {
    starts <- 0
  }

  res_list <- vector("list", length(starts))

  idx_settings <- pam_or(sc_cfg$acoustic_indices, NULL)
  if (is.null(idx_settings)) {
    idx_settings <- list(ACI = list(), ADI = list(), AEve = list(), Bio = list(), H = list(), M = list(), NDSI = list())
  }

  null_path <- nullfile()
  sink_con <- tryCatch(file(null_path, open = "wt"), error = function(e) NULL)
  if (!is.null(sink_con)) {
    sink(sink_con, type = "output")
    on.exit({
      try(sink(type = "output"), silent = TRUE)
      try(close(sink_con), silent = TRUE)
    }, add = TRUE)
  }

  calc_quiet <- function(expr) {
    suppressMessages(suppressWarnings(tryCatch(expr, error = function(e) NULL)))
  }

  for (i in seq_along(starts)) {
    w_start <- starts[i]
    w_end <- min(w_start + ifelse(win_sec > 0, win_sec, dur_sec), dur_sec)
    w_dur <- w_end - w_start

    actual_sub_sec <- min(sub_win_sec, w_dur)
    sub_starts <- seq(w_start, w_end - 1e-3, by = actual_sub_sec)

    sub_res <- vector("list", length(sub_starts))

    for (j in seq_along(sub_starts)) {
      s_start <- sub_starts[j]
      s_end <- min(s_start + actual_sub_sec, w_end)

      samp_start <- max(1, floor(s_start * wave@samp.rate) + 1)
      samp_end <- min(length(wave@left), ceiling(s_end * wave@samp.rate))

      sub_left <- wave@left[samp_start:samp_end]
      sub_right <- if (isTRUE(wave@stereo) && length(wave@right) >= samp_end) {
        wave@right[samp_start:samp_end]
      } else {
        numeric(0)
      }

      # High-pass filter sub-window; flatten matrix -> 1D numeric for tuneR::Wave
      if (!is.na(low_stop_hz) && low_stop_hz > 0 && length(sub_left) > 512) {
        filt_left <- calc_quiet(as.numeric(seewave::ffilter(
          sub_left, f = wave@samp.rate, from = low_stop_hz, output = "matrix"
        )))
        if (!is.null(filt_left) && length(filt_left) == length(sub_left)) {
          sub_left <- filt_left
        }

        if (length(sub_right) > 512) {
          filt_right <- calc_quiet(as.numeric(seewave::ffilter(
            sub_right, f = wave@samp.rate, from = low_stop_hz, output = "matrix"
          )))
          if (!is.null(filt_right) && length(filt_right) == length(sub_right)) {
            sub_right <- filt_right
          }
        }
      }

      sub_wave <- tuneR::Wave(
        left = sub_left,
        right = sub_right,
        samp.rate = wave@samp.rate,
        bit = wave@bit,
        pcm = wave@pcm
      )

      sub_res_list <- list(file_name = basename(audio_path), window_start_sec = w_start)

      if ("ACI" %in% names(idx_settings)) {
        res <- calc_quiet(soundecology::acoustic_complexity(sub_wave))
        sub_res_list$aci <- to_scalar_num(get_soundeco_val(res, c(
          "Acoustic_Complexity", "AcousticComplexityValue_all",
          "AcousticComplexityValue_left", "AcousticComplexityValue",
          "aci_tot", "AciTotAll_Run"
        )))
      }
      if ("ADI" %in% names(idx_settings)) {
        res <- calc_quiet(soundecology::acoustic_diversity(sub_wave))
        sub_res_list$adi <- to_scalar_num(get_soundeco_val(res, c(
          "Acoustic_Diversity_Value", "adi_left", "adi_all", "adi"
        )))
      }
      if ("AEve" %in% names(idx_settings)) {
        res <- calc_quiet(soundecology::acoustic_evenness(sub_wave))
        sub_res_list$aeve <- to_scalar_num(get_soundeco_val(res, c(
          "Acoustic_Evenness_Value", "aeve_left", "aeve_all", "aeve"
        )))
      }
      if ("Bio" %in% names(idx_settings)) {
        flim <- pam_or(idx_settings$Bio$flim, bio_range)
        res <- calc_quiet(soundecology::bioacoustic_index(
          sub_wave, min_freq = flim[1], max_freq = flim[2]
        ))
        sub_res_list$bio <- to_scalar_num(get_soundeco_val(res, c(
          "Left_Bioacc", "left_area", "area", "bio_index"
        )))
      }
      if ("H" %in% names(idx_settings)) {
        h_res <- calc_quiet(seewave::sh(sub_wave, f = sub_wave@samp.rate))
        sub_res_list$h <- to_scalar_num(
          if (is.list(h_res)) get_soundeco_val(h_res, "sh") else h_res
        )
      }
      if ("M" %in% names(idx_settings)) {
        m_res <- calc_quiet(seewave::M(sub_wave, f = sub_wave@samp.rate))
        sub_res_list$m <- to_scalar_num(m_res)
      }
      if ("NDSI" %in% names(idx_settings)) {
        anthro <- pam_or(
          idx_settings$NDSI$anthro_range,
          pam_or(idx_settings$NDSI$flim_antroPh, anthro_range)
        )
        bio <- pam_or(
          idx_settings$NDSI$bio_range,
          pam_or(idx_settings$NDSI$flim_bioPh, bio_range)
        )
        res <- calc_quiet(soundecology::ndsi(
          sub_wave,
          anthro_min = anthro[1], anthro_max = anthro[2],
          bio_min = bio[1], bio_max = bio[2]
        ))
        sub_res_list$ndsi <- to_scalar_num(get_soundeco_val(res, c(
          "ndsi_left", "ndsi_all", "ndsi"
        )))
      }

      sub_res[[j]] <- data.table::as.data.table(sub_res_list)
    }

    sub_dt <- data.table::rbindlist(sub_res, fill = TRUE)
    idx_cols <- setdiff(names(sub_dt), c("file_name", "window_start_sec"))
    means <- sub_dt[, lapply(.SD, mean, na.rm = TRUE), .SDcols = idx_cols]

    res_list[[i]] <- cbind(
      data.table::data.table(
        file_id          = file_id,
        window_index     = as.integer(i),
        window_start_sec = round(w_start, 2),
        window_end_sec   = round(w_end, 2)
      ),
      means
    )
  }

  data.table::rbindlist(res_list)
}

#' Resolve Soundscape Output Directory
#'
#' @param cfg List. Parsed configuration structure.
#' @return Character scalar path to output directory.
#' @keywords internal
pam_soundscape_out_dir <- function(cfg) {
  sc_cfg <- if (!is.null(cfg)) pam_or(cfg$soundscape, cfg$settings$soundscape) else NULL
  run_id <- pam_or(if (!is.null(cfg)) cfg$run_id else NULL, pam_or(if (!is.null(sc_cfg)) sc_cfg$run_id else NULL, "run01"))

  if (!is.null(cfg$paths$soundscape)) {
    return(file.path(cfg$paths$soundscape, run_id))
  }
  if (!is.null(cfg$data$soundscape)) {
    return(file.path(cfg$data$soundscape, run_id))
  }

  proj_root <- pam_or(cfg$paths$project_root, pam_or(cfg$data$project_root, "."))
  file.path(proj_root, "data", "soundscape", run_id)
}

#' Batch Process Audio Files for Soundscape Indices
#'
#' @param file_list Character vector. File paths to audio files (WAV or FLAC).
#' @param cfg List. Parsed configuration structure.
#' @param test_n Integer. Optional. Process only this many files (for tests).
#'
#' @return A \code{data.table} containing raw soundscape index values.
#' @export
pam_soundscape_batch <- function(file_list, cfg, test_n = NULL) {
  stage <- "02b_soundscape"
  log_dir <- if (!is.null(cfg$paths) && !is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()
  sc_cfg <- pam_or(cfg$soundscape, cfg$settings$soundscape)

  out_dir <- pam_soundscape_out_dir(cfg)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  raw_csv <- file.path(out_dir, "soundscape_raw.csv")
  done_txt <- file.path(out_dir, "done.txt")

  existing_raw <- if (file.exists(raw_csv)) {
    tryCatch(
      data.table::fread(raw_csv, fill = TRUE),
      error = function(e) data.table::data.table()
    )
  } else {
    data.table::data.table()
  }

  done_files <- character(0)
  if (file.exists(done_txt)) {
    done_files <- readLines(done_txt, warn = FALSE)
  }

  # Keep done.txt in sync with actual raw rows (WAV + FLAC basenames)
  if (nrow(existing_raw) > 0 && "file_id" %in% names(existing_raw)) {
    valid_done_ids <- unique(existing_raw$file_id)
    valid_done_names <- c(
      paste0(valid_done_ids, ".wav"),
      paste0(valid_done_ids, ".flac"),
      paste0(valid_done_ids, ".WAV"),
      paste0(valid_done_ids, ".FLAC")
    )
    done_files <- intersect(done_files, c(valid_done_ids, valid_done_names))
  } else if (length(done_files) > 0) {
    pam_log("WARN", "done.txt found but soundscape_raw.csv is empty/missing. Resetting checkpoint.", stage, log_dir)
    done_files <- character(0)
    unlink(done_txt)
  }

  to_process <- file_list[
    !basename(file_list) %in% done_files &
      !tools::file_path_sans_ext(basename(file_list)) %in% done_files
  ]

  if (!is.null(test_n) && test_n > 0) {
    to_process <- utils::head(to_process, test_n)
  }

  if (length(to_process) == 0) {
    pam_log("INFO", "All requested soundscape batch files are already processed.", stage, log_dir)
    return(existing_raw)
  }

  workers_cfg <- pam_or(sc_cfg$workers, pam_or(sc_cfg$no_cores, pam_or(cfg$settings$workers, 1)))
  if (is.character(workers_cfg)) {
    if (workers_cfg == "max") {
      n_cores <- parallel::detectCores()
    } else if (workers_cfg %in% c("max-1", "-1")) {
      n_cores <- max(1, parallel::detectCores() - 1)
    } else {
      n_cores <- suppressWarnings(as.integer(workers_cfg))
    }
  } else {
    n_cores <- suppressWarnings(as.integer(workers_cfg))
  }
  if (is.na(n_cores) || n_cores < 1) n_cores <- 1
  n_cores <- min(n_cores, length(to_process))

  pam_log(
    "INFO",
    glue::glue("Starting soundscape processing for {length(to_process)} remaining files across {n_cores} worker core(s)..."),
    stage, log_dir
  )

  # ---- Cleanroom export env (prevents installed-namespace hijack) ----
  # Include audio I/O helpers so FLAC decode works inside pam_soundscape_one
  # without loading the installed pamflow namespace on workers.
  export_env <- pam_soundscape_export_env(list(
    pam_soundscape_one = pam_soundscape_one,
    to_scalar_num      = to_scalar_num,
    get_soundeco_val   = get_soundeco_val,
    pam_or             = pam_or,
    pam_log            = pam_log,
    pam_read_audio     = pam_read_audio,
    pam_is_flac        = pam_is_flac,
    pam_audio_info     = pam_audio_info,
    pam_audio_exts     = pam_audio_exts,
    pam_audio_pattern  = pam_audio_pattern
  ))

  cl <- NULL
  if (n_cores > 1) {
    cl <- tryCatch({
      c_obj <- parallel::makePSOCKcluster(n_cores)
      parallel::clusterEvalQ(c_obj, {
        suppressPackageStartupMessages({
          library(data.table)
          library(tuneR)
          library(seewave)
          library(soundecology)
          library(glue)
          library(av)
        })
        try(detach("package:pamflow", unload = TRUE, character.only = TRUE), silent = TRUE)
        if ("pamflow" %in% loadedNamespaces()) {
          try(unloadNamespace("pamflow"), silent = TRUE)
        }
        NULL
      })

      parallel::clusterExport(c_obj, varlist = ls(export_env, all.names = TRUE), envir = export_env)

      sig_ok <- parallel::clusterEvalQ(c_obj, {
        fmls <- names(formals(pam_soundscape_one))
        list(ok = all(c("audio_path", "cfg") %in% fmls), formals = fmls)
      })
      bad <- vapply(sig_ok, function(x) !isTRUE(x$ok), logical(1))
      if (any(bad)) {
        parallel::stopCluster(c_obj)
        stop(
          "Worker pam_soundscape_one is missing 'audio_path'/'cfg' formals. ",
          "Installed pamflow is likely masking dev functions. ",
          "Formals seen: ", paste(sig_ok[[which(bad)[1]]]$formals, collapse = ", "),
          ". Run devtools::install() or remove the old install."
        )
      }

      c_obj
    }, error = function(e) {
      pam_log(
        "WARN",
        glue::glue("Failed to start parallel cluster ({e$message}). Falling back to single-core."),
        stage, log_dir
      )
      NULL
    })

    if (!is.null(cl)) {
      on.exit({
        try(parallel::stopCluster(cl), silent = TRUE)
      }, add = TRUE)
    }
  }

  batch_size <- 50
  n_batches <- ceiling(length(to_process) / batch_size)
  start_time <- Sys.time()

  for (b in seq_len(n_batches)) {
    idx_start <- (b - 1) * batch_size + 1
    idx_end <- min(b * batch_size, length(to_process))
    current_batch <- to_process[idx_start:idx_end]

    if (!is.null(cl)) {
      worker_fn <- function(fpath) {
        tryCatch(
          pam_soundscape_one(fpath, low_stop_hz = NULL, cfg = cfg),
          error = function(e) list(error = e$message)
        )
      }
      environment(worker_fn) <- list2env(
        list(
          pam_soundscape_one = export_env$pam_soundscape_one,
          cfg = cfg
        ),
        parent = baseenv()
      )

      batch_results <- parallel::parLapply(cl, current_batch, worker_fn)
    } else {
      batch_results <- vector("list", length(current_batch))
      for (i in seq_along(current_batch)) {
        fpath <- current_batch[i]
        fname <- basename(fpath)
        batch_results[[i]] <- tryCatch(
          pam_soundscape_one(fpath, low_stop_hz = NULL, cfg = cfg),
          error = function(e) {
            pam_log("ERROR", glue::glue("Error processing soundscape for {fname}: {e$message}"), stage, log_dir)
            NULL
          }
        )
      }
    }

    for (i in seq_along(batch_results)) {
      res <- batch_results[[i]]
      if (is.list(res) && !is.data.frame(res) && !data.table::is.data.table(res) && !is.null(res$error)) {
        fname <- basename(current_batch[i])
        pam_log("ERROR", glue::glue("Error processing soundscape for {fname}: {res$error}"), stage, log_dir)
        batch_results[i] <- list(NULL)
      }
    }

    successful_indices <- which(!vapply(batch_results, is.null, logical(1)))
    valid_dt <- data.table::rbindlist(batch_results[successful_indices], fill = TRUE)

    if (nrow(valid_dt) > 0) {
      append_mode <- file.exists(raw_csv)
      data.table::fwrite(valid_dt, raw_csv, append = append_mode)

      successful_files <- basename(current_batch[successful_indices])
      cat(paste0(successful_files, "\n"), file = done_txt, append = TRUE, sep = "")
    }

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "hours"))
    files_done <- idx_end
    rate <- files_done / max(elapsed, 0.0001)
    rem_files <- length(to_process) - files_done
    eta_hrs <- rem_files / max(rate, 0.0001)

    pam_log(
      "INFO",
      glue::glue("Soundscape Batch {b}/{n_batches} complete. Speed: {round(rate, 1)} files/hr | ETA: {round(eta_hrs, 2)} hrs"),
      stage, log_dir
    )
  }

  if (file.exists(raw_csv)) {
    data.table::fread(raw_csv, fill = TRUE)
  } else {
    data.table::data.table()
  }
}

#' Summarize Soundscape Indices into Hourly, Diel, and Site Covariate Metrics
#'
#' @param raw_dt \code{data.table}. Raw window soundscape indices.
#' @param master_dt \code{data.table}. Master metadata from Stage 1.
#' @param cfg List. Parsed configuration structure.
#'
#' @return A named list containing \code{hourly}, \code{diel}, and \code{site_covariates}.
#' @export
pam_soundscape_summarise <- function(raw_dt, master_dt, cfg = NULL) {
  if (is.null(raw_dt) || nrow(raw_dt) == 0) {
    stop("raw_dt is empty or NULL. Verify soundscape batch output or reset done.txt if checkpointing desynced.")
  }
  if (is.null(master_dt) || nrow(master_dt) == 0) {
    stop("master_dt is empty or NULL. Verify audio_master.csv output from Stage 1.")
  }

  dt_raw <- data.table::copy(raw_dt)
  dt_master <- data.table::copy(master_dt)

  if (!"file_id" %in% names(dt_master)) {
    if ("file_name" %in% names(dt_master)) {
      dt_master[, file_id := tools::file_path_sans_ext(file_name)]
    } else if ("filename" %in% names(dt_master)) {
      dt_master[, file_id := tools::file_path_sans_ext(filename)]
    } else {
      stop("master_dt must contain 'file_id', 'file_name', or 'filename' column.")
    }
  }

  if (!"start_time" %in% names(dt_master)) {
    stop("master_dt must contain 'start_time' column.")
  }

  meta_cols <- intersect(c("file_id", "grid", "start_time"), names(dt_master))
  dt_meta <- unique(dt_master[, ..meta_cols], by = "file_id")

  dt <- merge(dt_raw, dt_meta, by = "file_id", all.x = TRUE)

  sc_cfg <- if (!is.null(cfg)) pam_or(cfg$soundscape, cfg$settings$soundscape) else NULL
  local_tz <- pam_or(
    if (!is.null(cfg)) cfg$filenames$timezone else NULL,
    pam_or(if (!is.null(sc_cfg)) sc_cfg$timezone else NULL, "Asia/Kolkata")
  )

  day_hours <- pam_or(if (!is.null(sc_cfg)) sc_cfg$day_hours else NULL, c(6, 17))

  dt[, window_start_sec := as.numeric(window_start_sec)]

  parse_utc <- function(ts) {
    if (inherits(ts, "POSIXct")) return(ts)
    res <- suppressWarnings(as.POSIXct(ts, tz = "UTC"))
    if (any(is.na(res))) {
      res <- suppressWarnings(as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
    }
    res
  }

  dt[, start_time_utc := parse_utc(start_time)]
  dt[, window_datetime_utc := start_time_utc + window_start_sec]
  dt[, hour := as.integer(format(window_datetime_utc, tz = local_tz, "%H"))]
  dt[, diel_phase := ifelse(hour >= day_hours[1] & hour <= day_hours[2], "Day", "Night")]

  indices <- intersect(c("aci", "adi", "aeve", "bio", "h", "m", "ndsi"), names(dt))

  hourly_list <- list()
  for (idx in indices) {
    m_col <- paste0(idx, "_mean")
    s_col <- paste0(idx, "_sd")
    sub_dt <- dt[!is.na(get(idx)), .(
      mean_val = mean(get(idx), na.rm = TRUE),
      sd_val   = ifelse(length(get(idx)) > 1, stats::sd(get(idx), na.rm = TRUE), 0),
      n        = .N
    ), by = .(grid, hour)]
    data.table::setnames(sub_dt, c("mean_val", "sd_val", "n"), c(m_col, s_col, paste0(idx, "_n")))
    hourly_list[[idx]] <- sub_dt
  }

  hourly_dt <- Reduce(function(x, y) merge(x, y, by = c("grid", "hour"), all = TRUE), hourly_list)
  data.table::setorderv(hourly_dt, c("grid", "hour"))

  diel_list <- list()
  for (idx in indices) {
    m_col <- paste0(idx, "_mean")
    s_col <- paste0(idx, "_sd")
    sub_dt <- dt[!is.na(get(idx)), .(
      mean_val = mean(get(idx), na.rm = TRUE),
      sd_val   = ifelse(length(get(idx)) > 1, stats::sd(get(idx), na.rm = TRUE), 0),
      n        = .N
    ), by = .(grid, diel_phase)]
    data.table::setnames(sub_dt, c("mean_val", "sd_val", "n"), c(m_col, s_col, paste0(idx, "_n")))
    diel_list[[idx]] <- sub_dt
  }

  diel_dt <- Reduce(function(x, y) merge(x, y, by = c("grid", "diel_phase"), all = TRUE), diel_list)
  data.table::setorderv(diel_dt, c("grid", "diel_phase"))

  diel_wide_list <- list()
  for (idx in indices) {
    m_day <- paste0(idx, "_day_mean")
    s_day <- paste0(idx, "_day_sd")
    m_night <- paste0(idx, "_night_mean")
    s_night <- paste0(idx, "_night_sd")

    day_sub <- dt[!is.na(get(idx)) & diel_phase == "Day", .(
      m_d = mean(get(idx), na.rm = TRUE),
      s_d = ifelse(length(get(idx)) > 1, stats::sd(get(idx), na.rm = TRUE), 0)
    ), by = .(grid)]
    data.table::setnames(day_sub, c("m_d", "s_d"), c(m_day, s_day))

    night_sub <- dt[!is.na(get(idx)) & diel_phase == "Night", .(
      m_n = mean(get(idx), na.rm = TRUE),
      s_n = ifelse(length(get(idx)) > 1, stats::sd(get(idx), na.rm = TRUE), 0)
    ), by = .(grid)]
    data.table::setnames(night_sub, c("m_n", "s_n"), c(m_night, s_night))

    site_wide <- merge(day_sub, night_sub, by = "grid", all = TRUE)
    diel_wide_list[[idx]] <- site_wide
  }

  cov_dt <- Reduce(function(x, y) merge(x, y, by = "grid", all = TRUE), diel_wide_list)
  data.table::setorderv(cov_dt, "grid")

  list(
    hourly          = hourly_dt,
    diel            = diel_dt,
    site_covariates = cov_dt
  )
}

#' Run Stage 2b Soundscape Analysis Pipeline
#'
#' Discovers WAV/FLAC files via \code{\link{pam_list_audio}}, computes indices
#' with \code{\link{pam_soundscape_batch}}, and writes hourly/diel/site summaries.
#'
#' @param cfg List. Parsed configuration structure from \code{\link{pam_config_read}}.
#' @param test_n Integer. Optional. Process only this many files (for tests).
#'
#' @return A named list containing \code{raw}, \code{hourly}, \code{diel}, and \code{site_covariates}.
#' @export
pam_soundscape_run <- function(cfg, test_n = NULL) {
  stage <- "02b_soundscape"
  log_dir <- if (!is.null(cfg$paths) && !is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()
  sc_cfg <- pam_or(cfg$soundscape, cfg$settings$soundscape)
  run_id <- pam_or(cfg$run_id, pam_or(sc_cfg$run_id, "run01"))
  pam_log("INFO", glue::glue("Starting Stage 2b Soundscape pipeline for run_id: '{run_id}'"), stage, log_dir)

  meta_candidates <- c(
    if (!is.null(cfg$paths$metadata)) file.path(cfg$paths$metadata, "audio_master.csv") else NULL,
    if (!is.null(cfg$paths$metadata)) file.path(cfg$paths$metadata, "master_recordings.csv") else NULL,
    file.path(pam_or(cfg$paths$project_root, "."), "data", "metadata", "audio_master.csv"),
    file.path(pam_or(cfg$paths$project_root, "."), "data", "metadata", "master_recordings.csv"),
    file.path(pam_or(cfg$paths$output, cfg$data$output), "metadata", "audio_master.csv"),
    file.path(pam_or(cfg$paths$output, cfg$data$output), "metadata", "master_recordings.csv")
  )

  master_csv <- NULL
  for (cand in meta_candidates) {
    if (!is.null(cand) && file.exists(cand)) {
      master_csv <- cand
      break
    }
  }

  if (is.null(master_csv)) {
    stop("Master metadata table ('audio_master.csv' or 'master_recordings.csv') not found. Please run Stage 1 first.")
  }
  master_dt <- data.table::fread(master_csv, fill = TRUE)

  audio_candidates <- c(
    cfg$paths$audio_standardized,
    cfg$data$standardized,
    file.path(pam_or(cfg$paths$project_root, "."), "data", "standardized"),
    cfg$paths$audio
  )

  input_dir <- NULL
  for (cand in audio_candidates) {
    if (!is.null(cand) && dir.exists(cand)) {
      input_dir <- cand
      break
    }
  }

  if (is.null(input_dir)) {
    stop("Audio input directory not found. Please verify standardized audio paths in config.")
  }

  file_list <- pam_list_audio(input_dir, recursive = TRUE)
  if (length(file_list) == 0) {
    stop(glue::glue("No WAV/FLAC files found in: {input_dir}"))
  }
  pam_log("INFO", glue::glue("Found {length(file_list)} audio files (wav/flac) in {input_dir}"), stage, log_dir)

  raw_dt <- pam_soundscape_batch(file_list, cfg, test_n = test_n)

  if (is.null(raw_dt) || nrow(raw_dt) == 0) {
    stop("Soundscape batch processing returned 0 rows. Check worker logs or clear done.txt.")
  }

  pam_log("INFO", "Calculating soundscape hourly and diel summaries...", stage, log_dir)
  summaries <- pam_soundscape_summarise(raw_dt, master_dt, cfg)

  out_dir <- pam_soundscape_out_dir(cfg)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  data.table::fwrite(summaries$hourly, file.path(out_dir, "soundscape_hourly.csv"))
  data.table::fwrite(summaries$diel, file.path(out_dir, "soundscape_diel_summary.csv"))
  data.table::fwrite(summaries$site_covariates, file.path(out_dir, "soundscape_site_covariates.csv"))

  pam_log("INFO", glue::glue("Stage 2b Soundscape analysis completed successfully. Outputs saved to: {out_dir}"), stage, log_dir)

  list(
    raw             = raw_dt,
    hourly          = summaries$hourly,
    diel            = summaries$diel,
    site_covariates = summaries$site_covariates
  )
}
