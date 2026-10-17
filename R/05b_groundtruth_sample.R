#' Convert master-table start times to local POSIXct (internal)
#'
#' @param x ISO UTC text (as written by Stage 1) or POSIXct.
#' @param tz Olson timezone of the recordings.
#' @return POSIXct in `tz`.
#' @keywords internal
#' @noRd
pam_parse_master_time <- function(x, tz) {
  if (is.character(x)) x <- as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  attr(x, "tzone") <- tz
  x
}

#' Folder holding the ground-truth annotation files (internal)
#'
#' @param cfg A `pam_config` object.
#' @return `<paths$validation>/ground_truth`.
#' @keywords internal
#' @noRd
pam_gt_dir <- function(cfg) file.path(cfg$paths$validation, "ground_truth")

#' All possible annotation segments of the recordings
#'
#' Cuts every QC-passed, in-deployment recording into consecutive,
#' non-overlapping segments of `segment_s` seconds (a final piece shorter than
#' a segment is dropped).
#'
#' @param master Table with `rel`, `grid`, `recording_start` (POSIXct, local),
#'   `duration_s`, `qc_pass`, `in_deployment`.
#' @param segment_s Segment length in seconds.
#' @param hours Optional c(from, to): keep only segments whose local start hour
#'   is >= from and < to (e.g. c(4, 18)).
#' @return A data.table with one row per segment: `rel`, `grid`,
#'   `recording_start`, `seg_start`, `seg_end` (seconds into the file),
#'   `slot_time`, `hour`, `seg_key`.
#' @export
pam_recall_frame <- function(master, segment_s = 60, hours = NULL) {
  m <- data.table::copy(master)[qc_pass == TRUE & in_deployment == TRUE & !is.na(duration_s)]
  m[, n_slots := floor(duration_s / segment_s)]
  m <- m[n_slots >= 1]
  if (!nrow(m)) rlang::abort("No eligible recordings (QC-passed, in deployment, long enough)")
  frame <- m[, .(seg_start = (seq_len(n_slots) - 1) * segment_s),
             by = .(rel, grid, recording_start)]
  frame[, `:=`(seg_end = seg_start + segment_s, slot_time = recording_start + seg_start)]
  frame[, hour := as.integer(format(slot_time, "%H"))]
  if (length(hours) == 2L) frame <- frame[hour >= hours[1] & hour < hours[2]]
  frame[, seg_key := paste(rel, sprintf("%.0f", seg_start), sep = "|")]
  frame[]
}

#' Simple random sample of segments
#'
#' @param frame Segments from `pam_recall_frame()`.
#' @param n Number of segments.
#' @param seed Random seed.
#' @param exclude_keys `seg_key`s already drawn; never drawn again.
#' @return A data.table of `min(n, available)` segments.
#' @export
pam_recall_sample <- function(frame, n, seed = 1L, exclude_keys = character()) {
  f <- frame[!seg_key %in% exclude_keys]
  set.seed(seed)
  f[sample.int(.N, min(.N, as.integer(n)))]
}

#' Draw a round of random segments for ground-truth annotation
#'
#' Samples segments uniformly at random from the recordings, adds them to
#' `<paths$validation>/ground_truth/recall_segments.csv`, and never draws the
#' same segment twice. The ground truth belongs to the audio, not to a
#' detection run, so it can be reused to compare runs (for example filtered
#' against unfiltered audio).
#'
#' @param cfg A `pam_config` object (uses the `recall` section).
#' @param n Segments to draw in this round.
#' @param run_id Detection run. Only recordings that run processed are sampled,
#'   because recall is measured against that run. NULL samples all recordings.
#' @return Invisibly, the newly added rows.
#' @export
pam_recall_draw <- function(cfg, n = cfg$recall$n_segments, run_id = cfg$birdnet$run_id) {
  rc <- cfg$recall; tz <- cfg$filenames$timezone
  gt_dir <- pam_gt_dir(cfg)
  dir.create(gt_dir, recursive = TRUE, showWarnings = FALSE)
  seg_path <- file.path(gt_dir, "recall_segments.csv")
  existing <- if (file.exists(seg_path)) {
    data.table::fread(seg_path, colClasses = list(character = c(
      "seg_key", "rel", "slot_time", "clip_file", "spec_file", "grid")))
  } else NULL

  m <- data.table::fread(file.path(cfg$paths$metadata, "audio_master.csv"),
                         select = c("file_path", "grid", "duration_s", "start_time",
                                    "qc_pass", "in_deployment"))
  m[, rel := as.character(fs::path_rel(file_path, start = cfg$paths$audio_standardized))]
  m[, recording_start := pam_parse_master_time(start_time, tz)]
  if (!is.null(run_id)) {
    fr <- file.path(cfg$paths$detections, run_id, "file_results.csv")
    if (file.exists(fr)) {
      done <- data.table::fread(fr)[ok == TRUE, rel]
      m <- m[rel %in% done]
    } else {
      warning("No file_results.csv for run '", run_id, "'; sampling all recordings")
    }
  }

  frame <- pam_recall_frame(m, rc$segment_s, unlist(rc$hours))
  round_id <- if (is.null(existing)) 1L else max(existing$round) + 1L
  new <- pam_recall_sample(frame, n, seed = rc$seed + round_id,
                           exclude_keys = if (is.null(existing)) character() else existing$seg_key)
  if (!nrow(new)) {
    pam_log("INFO", "no new segments to draw", "05b_groundtruth", cfg$paths$logs)
    return(invisible(new))
  }
  first_id <- if (is.null(existing)) 0L else max(existing$segment_id)
  new[, `:=`(segment_id = first_id + seq_len(.N), round = round_id,
             segment_s = rc$segment_s,
             slot_time = format(slot_time, "%Y-%m-%d %H:%M:%S"))]
  new[, `:=`(clip_file = sprintf("g%06d.wav", segment_id),
             spec_file = sprintf("g%06d.png", segment_id))]
  keep <- c("segment_id", "round", "seg_key", "rel", "grid", "seg_start", "seg_end",
            "segment_s", "slot_time", "hour", "clip_file", "spec_file")
  new <- new[, keep, with = FALSE]
  all_rows <- data.table::rbindlist(list(existing, new), use.names = TRUE, fill = TRUE)
  pam_write_csv_atomic(all_rows, seg_path)
  pam_log("INFO", sprintf("round %d: %d new segments, %d in total (%d s each)",
                          round_id, nrow(new), nrow(all_rows), rc$segment_s),
          "05b_groundtruth", cfg$paths$logs)
  invisible(new)
}

#' Export audio and spectrograms for the ground-truth segments
#'
#' Cuts each segment from the audio chosen by `recall$audio` ("standardized"
#' by default, so the truth does not depend on the high-pass filter) and draws
#' a wide spectrogram. Existing files are kept.
#'
#' @param cfg A `pam_config` object.
#' @param force Recreate all files.
#' @return Invisibly, list(n_ok, n_failed, failed_ids).
#' @export
pam_recall_export <- function(cfg, force = FALSE) {
  stage <- "05b_export"; log_dir <- cfg$paths$logs
  rc <- cfg$recall; ffmpeg <- cfg$filter$ffmpeg_path
  gt_dir <- pam_gt_dir(cfg)
  seg_path <- file.path(gt_dir, "recall_segments.csv")
  if (!file.exists(seg_path)) rlang::abort("No segments yet. Run pam_recall_draw() first.")
  seg <- data.table::fread(seg_path)
  clip_dir <- file.path(gt_dir, "clips"); spec_dir <- file.path(gt_dir, "spectrograms")
  dir.create(clip_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(spec_dir, recursive = TRUE, showWarnings = FALSE)

  pam_check_ffmpeg(ffmpeg)
  src_dir <- if (identical(rc$audio, "filtered")) cfg$paths$filtered else cfg$paths$audio_standardized
  need <- seg[force | !file.exists(file.path(clip_dir, clip_file)) |
                !file.exists(file.path(spec_dir, spec_file))]
  if (!nrow(need)) {
    pam_log("INFO", "all segment files already exist", stage, log_dir)
    return(invisible(list(n_ok = 0L, n_failed = 0L, failed_ids = integer())))
  }
  pam_log("INFO", sprintf("exporting %d segments from %s", nrow(need), src_dir), stage, log_dir)

  filt <- pam_spectrogram_filter(rc$spec_max_hz, unlist(rc$spec_px))
  failed <- integer()
  cli::cli_progress_bar("Exporting segments", total = nrow(need))
  for (i in seq_len(nrow(need))) {
    s <- need[i]
    clip <- file.path(clip_dir, s$clip_file); spec <- file.path(spec_dir, s$spec_file)
    r1 <- pam_ffmpeg_to_file(
      c("-ss", sprintf("%.3f", s$seg_start), "-t", sprintf("%.3f", s$segment_s),
        "-i", shQuote(file.path(src_dir, s$rel)), "-c:a", "pcm_s16le"), clip, ffmpeg)
    r2 <- if (r1$ok) pam_ffmpeg_to_file(
      c("-i", shQuote(clip), "-lavfi", shQuote(filt), "-frames:v", "1"), spec, ffmpeg) else r1
    if (!r2$ok) {
      failed <- c(failed, s$segment_id)
      pam_log("WARN", sprintf("segment %d failed: %s", s$segment_id, r2$message), stage,
              log_dir, echo = FALSE)
    }
    cli::cli_progress_update()
  }
  cli::cli_progress_done()
  pam_log("INFO", sprintf("export finished: %d ok, %d failed", nrow(need) - length(failed),
                          length(failed)), stage, log_dir)
  invisible(list(n_ok = nrow(need) - length(failed), n_failed = length(failed),
                 failed_ids = failed))
}
