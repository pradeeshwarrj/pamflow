#' Quality factors of an even-order Butterworth filter cascade
#'
#' @param order Even filter order (8 gives 48 dB per octave).
#' @return Numeric vector of `order / 2` Q values, one per second-order section.
#' @keywords internal
#' @noRd
pam_butterworth_q <- function(order = 8L) {
  if (order < 2 || order %% 2 != 0) {
    rlang::abort("Filter order must be an even number >= 2")
  }
  k <- seq_len(order / 2)
  1 / (2 * sin((2 * k - 1) * pi / (2 * order)))
}

#' Build the FFmpeg filter string for a Butterworth high-pass
#'
#' FFmpeg's `highpass` filter supports only 2 poles per instance, so higher
#' orders are built as a cascade of second-order sections, each with the Q
#' value that yields a true Butterworth response (maximally flat passband,
#' -3 dB at the cutoff). Four identical sections would NOT give this: the
#' cutoff would sit near -12 dB.
#'
#' @param cutoff_hz Cutoff frequency in Hz (-3 dB point).
#' @param order Even filter order. 8 = 48 dB/octave.
#' @return A single character string for `ffmpeg -af`.
#' @export
#' @examples
#' pam_highpass_filter_string(250, 8)
pam_highpass_filter_string <- function(cutoff_hz = 250, order = 8L) {
  if (!is.numeric(cutoff_hz) || length(cutoff_hz) != 1 || cutoff_hz <= 0) {
    rlang::abort("cutoff_hz must be a single positive number")
  }
  q <- sort(pam_butterworth_q(order))
  paste(sprintf("highpass=f=%s:p=2:t=q:w=%.6f:r=f64", format(cutoff_hz), q),
        collapse = ",")
}

#' Check that FFmpeg is installed and supports the filter chain
#'
#' @param ffmpeg Executable name or full path.
#' @param filter Filter string to test on 0.1 s of silence.
#' @return The first line of FFmpeg's version output. Aborts with install
#'   advice if FFmpeg is missing or too old for the filter.
#' @export
pam_check_ffmpeg <- function(ffmpeg = "ffmpeg", filter = NULL) {
  run <- function(args) {
    out <- tryCatch(suppressWarnings(system2(ffmpeg, args, stdout = TRUE, stderr = TRUE)),
                    error = function(e) structure(conditionMessage(e), status = 127L))
    list(out = out, ok = is.null(attr(out, "status")) || attr(out, "status") == 0L)
  }
  v <- run("-version")
  if (!v$ok) {
    rlang::abort(c("FFmpeg could not be run.",
                   i = "Install it (winget install --id Gyan.FFmpeg -e), restart RStudio,",
                   i = "or set filter$ffmpeg_path in the config to the full path of ffmpeg.exe."))
  }
  if (!is.null(filter)) {
    t <- run(c("-v", "error", "-f", "lavfi", "-i", shQuote("anullsrc=r=48000:cl=mono"),
               "-t", "0.1", "-af", shQuote(filter), "-f", "null", "-"))
    if (!t$ok) {
      rlang::abort(c("This FFmpeg build rejected the high-pass filter chain.",
                     i = "Update FFmpeg to a recent version.",
                     x = paste(utils::tail(t$out, 3), collapse = " | ")))
    }
  }
  v$out[1]
}

#' Filter one audio file with FFmpeg
#'
#' Base R only, so it can be shipped to parallel workers without the package
#' installed. Writes to `<output>.part` and renames on success, so an
#' interrupted run never leaves a half-written file that looks finished.
#'
#' @param item List with `input`, `output` (paths) and `bits` (input bit depth;
#'   16, 24 or 32 are preserved, anything else becomes 16).
#' @param filter Filter string from `pam_highpass_filter_string()`.
#' @param ffmpeg Executable name or path.
#' @return A list: `ok` (logical) and `message` (last FFmpeg error lines, or "").
#' @export
pam_filter_one <- function(item, filter, ffmpeg = "ffmpeg") {
  codec <- switch(as.character(item$bits)[1], "24" = "pcm_s24le", "32" = "pcm_s32le",
                  "pcm_s16le")
  tmp <- paste0(item$output, ".part")
  dir.create(dirname(item$output), recursive = TRUE, showWarnings = FALSE)
  args <- c("-y", "-nostdin", "-v", "error", "-i", shQuote(item$input),
            "-af", shQuote(filter), "-c:a", codec, "-f", "wav", shQuote(tmp))
  res <- tryCatch(suppressWarnings(system2(ffmpeg, args, stdout = TRUE, stderr = TRUE)),
                  error = function(e) structure(conditionMessage(e), status = 127L))
  status <- attr(res, "status")
  ok <- (is.null(status) || status == 0L) && file.exists(tmp) && file.size(tmp) > 44
  if (ok) {
    if (file.exists(item$output)) unlink(item$output)
    ok <- file.rename(tmp, item$output)
  }
  if (!ok) unlink(tmp)
  list(ok = ok, message = if (ok) "" else paste(utils::tail(res, 3), collapse = " | "))
}

#' Filter and verify one batch (internal)
#'
#' @param batch data.table with `input`, `output`, `bits`, `exp_dur`, `exp_sr`,
#'   `exp_ch`.
#' @param fn Worker function (`pam_filter_one` with a global environment).
#' @param filter Filter string.
#' @param fc The `filter` section of the config.
#' @param cl Optional parallel cluster.
#' @return `batch` with `ok`, `message`, `verified`. Outputs that fail
#'   verification (unreadable, or duration/rate/channels differ) are deleted.
#' @keywords internal
#' @noRd
pam_filter_batch <- function(batch, fn, filter, fc, cl = NULL) {
  items <- lapply(seq_len(nrow(batch)), function(i) {
    list(input = batch$input[i], output = batch$output[i], bits = batch$bits[i])
  })
  res <- if (is.null(cl)) {
    lapply(items, fn, filter = filter, ffmpeg = fc$ffmpeg_path)
  } else {
    parallel::parLapplyLB(cl, items, fn, filter = filter, ffmpeg = fc$ffmpeg_path)
  }
  batch[, ok := vapply(res, function(r) isTRUE(r$ok), logical(1))]
  batch[, message := vapply(res, function(r) r$message, character(1))]
  batch[, verified := FALSE]

  if (any(batch$ok)) {
    good <- batch[ok == TRUE]
    info <- pam_audio_info(good$output)
    v <- data.table::fcoalesce(
      info$readable &
        abs(info$duration_s - good$exp_dur) <= fc$duration_tolerance_s &
        info$sample_rate == good$exp_sr & info$channels == good$exp_ch,
      FALSE)
    batch[ok == TRUE, verified := v]
    bad <- batch[ok == TRUE & verified == FALSE, output]
    if (length(bad)) {
      unlink(bad)
      batch[ok == TRUE & verified == FALSE,
            message := "output failed verification (unreadable or length/format mismatch)"]
    }
  }
  batch[]
}

#' Stage 2: high-pass filter all QC-passed recordings
#'
#' Applies a Butterworth high-pass (default 250 Hz, 48 dB/octave) with FFmpeg
#' and writes filtered copies to `paths$filtered`, mirroring the folder
#' structure and file names of `paths$audio_standardized`. Originals are never
#' modified.
#'
#' @param cfg A `pam_config` object. Uses the `filter` section and paths.
#' @param master Optional master table from `pam_scan_audio()$master`; if NULL
#'   it is read from `metadata/audio_master.csv`.
#' @param force If TRUE, ignore the checkpoint and re-filter everything.
#' @return Invisibly, a list: `n_pending`, `n_ok`, `n_failed`, `results_file`.
#' @details Resumable: completed files are recorded in `metadata/02_filter.done`
#'   only after the output has been written and verified (readable, same
#'   duration, sample rate and channels). Per-file outcomes, including FFmpeg
#'   error text, are appended to `metadata/02_filter_results.csv`. Only files
#'   with `qc_pass == TRUE` are filtered. Run with
#'   `pam_run_stage("02_filter", pam_filter_audio, cfg)`.
#' @export
pam_filter_audio <- function(cfg, master = NULL, force = FALSE) {
  stage <- "02_filter"; log_dir <- cfg$paths$logs
  fc <- cfg$filter
  if (!isTRUE(fc$enabled)) {
    pam_log("INFO", "filter disabled in config; nothing to do", stage, log_dir)
    return(invisible(NULL))
  }
  filter <- pam_highpass_filter_string(fc$highpass_hz, fc$order)
  pam_log("INFO", paste("using", pam_check_ffmpeg(fc$ffmpeg_path, filter)), stage, log_dir)
  pam_log("INFO", paste("filter chain:", filter), stage, log_dir)

  if (is.null(master)) {
    mp <- file.path(cfg$paths$metadata, "audio_master.csv")
    if (!file.exists(mp)) rlang::abort("audio_master.csv not found. Run Stage 1 first.")
    master <- data.table::fread(mp, select = c("file_path", "duration_s", "sample_rate",
                                               "channels", "bits", "file_size_b", "qc_pass"))
  }
  root <- cfg$paths$audio_standardized
  out_dir <- cfg$paths$filtered
  src <- master[qc_pass == TRUE]
  rel <- as.character(fs::path_rel(src$file_path, start = root))
  todo <- data.table::data.table(
    rel = rel, input = src$file_path, output = file.path(out_dir, rel),
    bits = src$bits, exp_dur = src$duration_s, exp_sr = src$sample_rate,
    exp_ch = src$channels, size = src$file_size_b)

  ckpt <- file.path(cfg$paths$metadata, "02_filter.done")
  results_path <- file.path(cfg$paths$metadata, "02_filter_results.csv")
  if (force) unlink(c(ckpt, results_path))
  done <- pam_checkpoint_read(ckpt)
  done <- done[file.exists(file.path(out_dir, done))]   # re-do files whose output vanished
  pending <- todo[!rel %in% done]

  if (!nrow(pending)) {
    pam_log("INFO", "nothing pending; all files already filtered", stage, log_dir)
    return(invisible(list(n_pending = 0L, n_ok = 0L, n_failed = 0L, results_file = results_path)))
  }
  pam_log("INFO", sprintf("%d files to filter (%.1f GB input; filtered copies need about the same space in %s)",
                          nrow(pending), sum(pending$size, na.rm = TRUE) / 1e9, out_dir),
          stage, log_dir)

  batches <- split(seq_len(nrow(pending)), ceiling(seq_len(nrow(pending)) / fc$chunk_size))
  fn <- pam_filter_one
  environment(fn) <- globalenv()        # workers need no pamflow installation
  cl <- NULL
  if (as.integer(fc$workers) > 1L) {
    cl <- parallel::makeCluster(as.integer(fc$workers))
    on.exit(parallel::stopCluster(cl), add = TRUE)
  }

  n_ok <- 0L; n_fail <- 0L
  cli::cli_progress_bar("Filtering audio", total = nrow(pending))
  for (b in seq_along(batches)) {
    batch <- tryCatch(
      pam_filter_batch(data.table::copy(pending[batches[[b]]]), fn, filter, fc, cl),
      error = function(e) {
        pam_log("ERROR", paste("batch", b, "failed:", conditionMessage(e)), stage, log_dir)
        NULL
      })
    if (is.null(batch)) {                # files stay pending; rerun to retry
      cli::cli_progress_update(inc = length(batches[[b]]))
      next
    }
    data.table::fwrite(batch[, .(rel, ok, verified, message)], results_path,
                       append = file.exists(results_path))
    pam_checkpoint_add(batch[verified == TRUE, rel], ckpt)
    n_ok <- n_ok + sum(batch$verified)
    n_fail <- n_fail + sum(!batch$verified)
    pam_log("INFO", sprintf("batch %d/%d: %d ok, %d failed", b, length(batches),
                            sum(batch$verified), sum(!batch$verified)), stage, log_dir)
    cli::cli_progress_update(inc = nrow(batch))
  }
  cli::cli_progress_done()
  pam_log("INFO", sprintf("filtering finished: %d ok, %d failed of %d",
                          n_ok, n_fail, nrow(pending)), stage, log_dir)
  invisible(list(n_pending = nrow(pending), n_ok = n_ok, n_failed = n_fail,
                 results_file = results_path))
}
