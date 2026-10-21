#' Stage 2b: Soundscape Analysis (Indices & Summaries)
#'
#' Implementation of ecoacoustic soundscape indices following Bradfer-Lawrence
#' et al. (2019) guidelines. Computes core acoustic indices with 1-minute
#' sub-windowing, checkpointing, and timezone-aware hourly/diel summarization.
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
#' Returns NA_real_ for NULL, non-scalar, or non-numeric inputs. Useful because
#' soundecology returns can be lists, data.frames, or numeric(0) on short clips.
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
#' Tries named candidates first; if none match, falls back to the first
#' numeric element found anywhere in the list. This is robust against
#' soundecology changing its return element names between versions.
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

#' Compute Ecoacoustic Soundscape Indices for a Single Audio File
#'
#' Reads a WAV file, applies an optional low-stop (highpass) filter, resamples
#' high-sample-rate audio to 24 kHz for ecoacoustic frequency bounds (max 11-12 kHz),
#' splits the recording into internal analysis windows, and computes ecoacoustic
#' indices dynamically configured in \code{cfg$soundscape$acoustic_indices}.
#'
#' @param wav_path Character. Path to input WAV file.
#' @param low_stop_hz Numeric. Highpass low-stop frequency in Hz (default 500).
#'   Pass NULL or 0 to skip filtering.
#' @param cfg List. Parsed configuration structure from \code{\link{pam_config_read}}.
#' @param window_sec Numeric. Optional window duration in seconds (e.g. 600 for
#'   10 minutes).
#'
#' @return A \code{data.table} with columns for \code{file_id}, \code{window_index},
#'   \code{window_start_sec}, \code{window_end_sec}, and computed index values.
#' @export
pam_soundscape_one <- function(wav_path, low_stop_hz = NULL, cfg = NULL, window_sec = NULL) {
  stage <- "02b_soundscape"
  log_dir <- if (!is.null(cfg) && !is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()
  if (!file.exists(wav_path)) {
    stop(glue::glue("WAV file not found: {wav_path}"))
  }

  low_stop_hz <- to_scalar_num(pam_or(low_stop_hz, pam_or(cfg$soundscape$low_stop_hz, 500)))
  anthro_range <- pam_or(cfg$soundscape$anthro_range, c(1000, 2000))
  bio_range <- pam_or(cfg$soundscape$bio_range, c(2000, 11000))

  # Resolve window duration (supports window_mins or window_sec)
  win_sec <- to_scalar_num(pam_or(
    window_sec,
    pam_or(
      if (!is.null(cfg$soundscape$window_mins)) cfg$soundscape$window_mins * 60 else NULL,
      pam_or(cfg$soundscape$window_sec, 600)
    )
  ))
  sub_win_sec <- to_scalar_num(pam_or(cfg$soundscape$sub_window_sec, 60))

  file_id <- tools::file_path_sans_ext(basename(wav_path))

  wave <- tryCatch(
    tuneR::readWave(wav_path),
    error = function(e) {
      stop(glue::glue("Failed to read wave file '{wav_path}': {e$message}"))
    }
  )

  # Low-stop filtering if requested
  if (!is.na(low_stop_hz) && low_stop_hz > 0) {
    wave <- tryCatch(
      seewave::ffilter(wave, f = wave@samp.rate, from = low_stop_hz, output = "Wave"),
      error = function(e) {
        pam_log("WARN", glue::glue("ffilter failed for {file_id}, using raw wave: {e$message}"), stage, log_dir)
        wave
      }
    )
  }

  # Downsample to 24 kHz for ecoacoustics (max required freq = 11 kHz)
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

  # Resolve index settings dynamically; default to all 7 indices if absent
  idx_settings <- cfg$soundscape$acoustic_indices
  if (is.null(idx_settings)) {
    idx_settings <- list(ACI = list(), ADI = list(), AEve = list(), Bio = list(), H = list(), M = list(), NDSI = list())
  }

  null_con <- nullfile()
  sink_active <- FALSE
  if (is.character(null_con) && length(null_con) == 1) {
    sink(null_con, type = "output")
    sink_active <- TRUE
    on.exit({
      if (sink_active) sink(type = "output")
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
      sub_right <- if (wave@stereo && length(wave@right) >= samp_end) wave@right[samp_start:samp_end] else numeric(0)

      sub_wave <- tuneR::Wave(
        left = sub_left,
        right = sub_right,
        samp.rate = wave@samp.rate,
        bit = wave@bit,
        pcm = wave@pcm
      )

      sub_res_list <- list(file_name = basename(wav_path), window_start_sec = w_start)

      if ("ACI" %in% names(idx_settings)) {
        res <- calc_quiet(soundecology::acoustic_complexity(sub_wave))
        sub_res_list$aci <- get_soundeco_val(res, c("Acoustic_Complexity", "AcousticComplexityValue_all", "AcousticComplexityValue_left", "AcousticComplexityValue", "aci_tot"))
      }
      if ("ADI" %in% names(idx_settings)) {
        res <- calc_quiet(soundecology::acoustic_diversity(sub_wave))
        sub_res_list$adi <- get_soundeco_val(res, c("Acoustic_Diversity_Value", "adi_left", "adi_all", "adi"))
      }
      if ("AEve" %in% names(idx_settings)) {
        res <- calc_quiet(soundecology::acoustic_evenness(sub_wave))
        sub_res_list$aeve <- get_soundeco_val(res, c("Acoustic_Evenness_Value", "aeve_left", "aeve_all", "aeve"))
      }
      if ("Bio" %in% names(idx_settings)) {
        flim <- pam_or(idx_settings$Bio$flim, bio_range)
        res <- calc_quiet(soundecology::bioacoustic_index(sub_wave, min_freq = flim[1], max_freq = flim[2]))
        sub_res_list$bio <- get_soundeco_val(res, c("Left_Bioacc", "left_area", "area", "bio_index"))
      }
      if ("H" %in% names(idx_settings)) {
        h_res <- calc_quiet(seewave::sh(sub_wave, f = sub_wave@samp.rate))
        sub_res_list$h <- if (is.null(h_res)) NA_real_ else if (is.list(h_res)) get_soundeco_val(h_res, "sh") else to_scalar_num(h_res)
      }
      if ("M" %in% names(idx_settings)) {
        sub_res_list$m <- calc_quiet(to_scalar_num(seewave::M(sub_wave, f = sub_wave@samp.rate)))
      }
      if ("NDSI" %in% names(idx_settings)) {
        anthro <- pam_or(idx_settings$NDSI$anthro_range, pam_or(idx_settings$NDSI$flim_antroPh, anthro_range))
        bio <- pam_or(idx_settings$NDSI$bio_range, pam_or(idx_settings$NDSI$flim_bioPh, bio_range))
        res <- calc_quiet(soundecology::ndsi(sub_wave, anthro_min = anthro[1], anthro_max = anthro[2], bio_min = bio[1], bio_max = bio[2]))
        sub_res_list$ndsi <- get_soundeco_val(res, c("ndsi_left", "ndsi_all", "ndsi"))
      }

      sub_res[[j]] <- data.table::as.data.table(sub_res_list)
    }

    sub_dt <- data.table::rbindlist(sub_res, fill = TRUE)

    means <- sub_dt[, lapply(.SD, mean, na.rm = TRUE), .SDcols = setdiff(names(sub_dt), c("file_name", "window_start_sec"))]

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


#' Batch Process Audio Files for Soundscape Indices
#'
#' Processes a list of audio files in batches of 50, appending results to
#' \code{soundscape_raw.csv} and writing checkpoints to \code{done.txt}.
#'
#' @param file_list Character vector. File paths to audio files.
#' @param cfg List. Parsed configuration structure from \code{\link{pam_config_read}}.
#' @param test_n Integer. Optional. Process only this many files (for tests).
#'
#' @return A \code{data.table} containing raw soundscape index values.
#' @export
pam_soundscape_batch <- function(file_list, cfg, test_n = NULL) {
  stage <- "02b_soundscape"
  log_dir <- if (!is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()
  run_id <- pam_or(cfg$run_id, pam_or(cfg$soundscape$run_id, "run01"))
  out_dir <- file.path(pam_or(cfg$paths$project_root, "."), "data", "soundscape", run_id)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  raw_csv <- file.path(out_dir, "soundscape_raw.csv")
  done_txt <- file.path(out_dir, "done.txt")

  done_files <- character(0)
  if (file.exists(done_txt)) {
    done_files <- readLines(done_txt, warn = FALSE)
  }

  to_process <- file_list[!basename(file_list) %in% done_files]

  if (!is.null(test_n) && test_n > 0) {
    to_process <- utils::head(to_process, test_n)
  }

  if (length(to_process) == 0) {
    pam_log("INFO", "All soundscape batch files already processed (checkpoint complete).", stage, log_dir)
    if (file.exists(raw_csv)) {
      return(data.table::fread(raw_csv))
    } else {
      return(data.table::data.table())
    }
  }

  pam_log("INFO", glue::glue("Starting soundscape processing for {length(to_process)} remaining files..."), stage, log_dir)

  batch_size <- 50
  n_batches <- ceiling(length(to_process) / batch_size)
  start_time <- Sys.time()

  for (b in seq_len(n_batches)) {
    idx_start <- (b - 1) * batch_size + 1
    idx_end <- min(b * batch_size, length(to_process))
    current_batch <- to_process[idx_start:idx_end]

    batch_results <- vector("list", length(current_batch))

    for (i in seq_along(current_batch)) {
      fpath <- current_batch[i]
      fname <- basename(fpath)

      res <- tryCatch(
        pam_soundscape_one(fpath, low_stop_hz = NULL, cfg = cfg),
        error = function(e) {
          pam_log("ERROR", glue::glue("Error processing soundscape for {fname}: {e$message}"), stage, log_dir)
          NULL
        }
      )

      if (!is.null(res)) {
        batch_results[[i]] <- res
      }
    }

    successful_indices <- which(!sapply(batch_results, is.null))
    valid_dt <- data.table::rbindlist(batch_results[successful_indices], fill = TRUE)

    if (nrow(valid_dt) > 0) {
      append_mode <- file.exists(raw_csv)
      data.table::fwrite(valid_dt, raw_csv, append = append_mode)

      # ONLY checkpoint files that succeeded
      successful_files <- basename(current_batch[successful_indices])
      cat(paste(successful_files, collapse = "\n"), "\n", file = done_txt, append = TRUE)
    }

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "hours"))
    files_done <- idx_end
    rate <- files_done / max(elapsed, 0.0001)
    rem_files <- length(to_process) - files_done
    eta_hrs <- rem_files / max(rate, 0.0001)

    pam_log("INFO", glue::glue("Soundscape Batch {b}/{n_batches} complete. Speed: {round(rate, 1)} files/hr | ETA: {round(eta_hrs, 2)} hrs"), stage, log_dir)
  }

  if (file.exists(raw_csv)) {
    data.table::fread(raw_csv)
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
    stop("raw_dt is empty or NULL.")
  }
  if (is.null(master_dt) || nrow(master_dt) == 0) {
    stop("master_dt is empty or NULL.")
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

  local_tz <- pam_or(
    cfg$filenames$timezone,
    pam_or(cfg$soundscape$timezone, "Asia/Kolkata")
  )

  day_hours <- pam_or(cfg$soundscape$day_hours, c(6, 17))

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
#' @param cfg List. Parsed configuration structure from \code{\link{pam_config_read}}.
#' @param test_n Integer. Optional. Process only this many files (for tests).
#'
#' @return A named list containing \code{raw}, \code{hourly}, \code{diel}, and \code{site_covariates}.
#' @export
pam_soundscape_run <- function(cfg, test_n = NULL) {
  stage <- "02b_soundscape"
  log_dir <- if (!is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()
  run_id <- pam_or(cfg$run_id, pam_or(cfg$soundscape$run_id, "run01"))
  pam_log("INFO", glue::glue("Starting Stage 2b Soundscape pipeline for run_id: '{run_id}'"), stage, log_dir)

  master_csv <- file.path(cfg$paths$metadata, "audio_master.csv")
  if (!file.exists(master_csv)) {
    stop(glue::glue("Master metadata table not found at: {master_csv}. Please run Stage 1 first."))
  }
  master_dt <- data.table::fread(master_csv)

  input_dir <- cfg$paths$audio_standardized
  if (!dir.exists(input_dir)) {
    input_dir <- cfg$paths$audio
  }
  if (!dir.exists(input_dir)) {
    stop(glue::glue("Audio input directory not found: {input_dir}"))
  }

  file_list <- list.files(input_dir, pattern = "\\.wav$", full.names = TRUE, recursive = TRUE)
  if (length(file_list) == 0) {
    stop(glue::glue("No WAV files found in: {input_dir}"))
  }

  raw_dt <- pam_soundscape_batch(file_list, cfg, test_n = test_n)

  pam_log("INFO", "Calculating soundscape hourly and diel summaries...", stage, log_dir)
  summaries <- pam_soundscape_summarise(raw_dt, master_dt, cfg)

  out_dir <- file.path(pam_or(cfg$paths$project_root, "."), "data", "soundscape", run_id)
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
