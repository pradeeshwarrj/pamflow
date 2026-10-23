#' Audio folder a detection run read from (internal)
#'
#' Uses the newest `run_settings_*.yml` of the run, falling back to the
#' config's input setting.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @return A folder path.
#' @keywords internal
#' @noRd
pam_run_input_dir <- function(cfg, run_id) {
  run_dir <- file.path(cfg$paths$detections, run_id)
  sf <- sort(list.files(run_dir, pattern = "^run_settings_.*\\.yml$", full.names = TRUE))
  if (length(sf)) {
    d <- yaml::read_yaml(sf[length(sf)])$input_dir
    if (!is.null(d) && dir.exists(d)) return(d)
  }
  if (identical(cfg$birdnet$input, "filtered")) cfg$paths$filtered else cfg$paths$audio_standardized
}

#' FFmpeg filter that draws a spectrogram picture (internal)
#'
#' @param max_hz Top of the frequency axis in Hz.
#' @param px Picture size, c(width, height).
#' @return A filter string for `-lavfi`.
#' @keywords internal
#' @noRd
pam_spectrogram_filter <- function(max_hz = 12000, px = c(900, 360)) {
  sprintf("aresample=%d,showspectrumpic=s=%dx%d:legend=1:scale=log:fscale=lin:color=intensity",
          as.integer(2 * max_hz), as.integer(px[1]), as.integer(px[2]))
}

#' Run FFmpeg to produce one file, atomically (internal)
#'
#' @param args FFmpeg arguments before the output file (already quoted).
#' @param out Final output path.
#' @param ffmpeg Executable.
#' @return list(ok, message).
#' @keywords internal
#' @noRd
pam_ffmpeg_to_file <- function(args, out, ffmpeg = "ffmpeg") {
  tmp <- sub("(\\.[A-Za-z0-9]+)$", ".tmp\\1", out)
  res <- tryCatch(
    suppressWarnings(system2(ffmpeg, c("-y", "-nostdin", "-v", "error", args, shQuote(tmp)),
                             stdout = TRUE, stderr = TRUE)),
    error = function(e) structure(conditionMessage(e), status = 127L))
  status <- attr(res, "status")
  ok <- (is.null(status) || status == 0L) && file.exists(tmp) && file.size(tmp) > 0
  if (ok) {
    if (file.exists(out)) unlink(out)
    ok <- file.rename(tmp, out)
  }
  if (!ok) unlink(tmp)
  list(ok = ok, message = if (ok) "" else paste(utils::tail(res, 3), collapse = " | "))
}

#' Export audio clips and spectrograms for the sampled events (WAV + FLAC)
#'
#' For every row of `validation_samples.csv` whose files are missing, cuts a
#' clip (event plus `validation$clip_pad_s` seconds of context on each side)
#' from the audio the run read, and draws a spectrogram PNG with FFmpeg.
#' Dynamically uses `-c:a flac` or `-c:a pcm_s16le` based on the target clip file
#' extension. Existing files are kept, so it can be rerun after each new round.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @param force Recreate all files.
#' @return Invisibly, list(n_ok, n_failed, failed_ids).
#' @export
pam_validation_export <- function(cfg, run_id = cfg$birdnet$run_id, force = FALSE) {
  stage <- "05_export"; log_dir <- cfg$paths$logs
  vc <- cfg$validation; ffmpeg <- cfg$filter$ffmpeg_path
  val_dir <- file.path(cfg$paths$detections, run_id, "validation")
  samples_path <- file.path(val_dir, "validation_samples.csv")
  if (!file.exists(samples_path)) rlang::abort("No samples yet. Run pam_validation_draw() first.")
  samples <- data.table::fread(samples_path)
  clip_dir <- file.path(val_dir, "clips"); spec_dir <- file.path(val_dir, "spectrograms")
  dir.create(clip_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(spec_dir, recursive = TRUE, showWarnings = FALSE)

  pam_check_ffmpeg(ffmpeg)
  input_dir <- pam_run_input_dir(cfg, run_id)
  need <- samples[force | !file.exists(file.path(clip_dir, clip_file)) |
                    !file.exists(file.path(spec_dir, spec_file))]
  if (!nrow(need)) {
    pam_log("INFO", "all clips and spectrograms already exist", stage, log_dir)
    return(invisible(list(n_ok = 0L, n_failed = 0L, failed_ids = integer())))
  }
  pam_log("INFO", sprintf("exporting %d clips from %s", nrow(need), input_dir), stage, log_dir)

  filt <- pam_spectrogram_filter(vc$spec_max_hz, unlist(vc$spec_px))
  failed <- integer()
  cli::cli_progress_bar("Exporting clips", total = nrow(need))
  for (i in seq_len(nrow(need))) {
    s <- need[i]
    clip <- file.path(clip_dir, s$clip_file); spec <- file.path(spec_dir, s$spec_file)

    out_ext <- tolower(tools::file_ext(clip))
    codec_args <- if (out_ext == "flac") c("-c:a", "flac") else c("-c:a", "pcm_s16le")

    r1 <- pam_ffmpeg_to_file(
      c("-ss", sprintf("%.3f", s$clip_start_s), "-t", sprintf("%.3f", s$clip_dur_s),
        "-i", shQuote(file.path(input_dir, s$rel)), codec_args), clip, ffmpeg)
    r2 <- if (r1$ok) pam_ffmpeg_to_file(
      c("-i", shQuote(clip), "-lavfi", shQuote(filt), "-frames:v", "1"), spec, ffmpeg) else r1
    if (!r2$ok) {
      failed <- c(failed, s$sample_id)
      pam_log("WARN", sprintf("sample %d failed: %s", s$sample_id, r2$message), stage, log_dir,
              echo = FALSE)
    }
    cli::cli_progress_update()
  }
  cli::cli_progress_done()
  pam_log("INFO", sprintf("export finished: %d ok, %d failed", nrow(need) - length(failed),
                          length(failed)), stage, log_dir)
  invisible(list(n_ok = nrow(need) - length(failed), n_failed = length(failed),
                 failed_ids = failed))
}
