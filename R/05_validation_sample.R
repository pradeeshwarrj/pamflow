#' Load assembled detections with file durations (internal)
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @return The table from `pam_assemble_detections()` plus `file_duration_s`.
#' @keywords internal
#' @noRd
pam_load_detections <- function(cfg, run_id = cfg$birdnet$run_id) {
  det <- pam_assemble_detections(cfg, run_id = run_id)
  m <- data.table::fread(file.path(cfg$paths$metadata, "audio_master.csv"),
                         select = c("file_path", "duration_s"))
  m[, rel := as.character(fs::path_rel(file_path, start = cfg$paths$audio_standardized))]
  merge(det, m[, .(rel, file_duration_s = duration_s)], by = "rel",
        all.x = TRUE, sort = FALSE)
}

#' Write a CSV atomically (internal)
#'
#' @param dt A data.table.
#' @param path Destination path. Written to `<path>.part` and then renamed, so
#'   an interruption never leaves a half-written file.
#' @return `path`, invisibly.
#' @keywords internal
#' @noRd
pam_write_csv_atomic <- function(dt, path) {
  tmp <- paste0(path, ".part")
  data.table::fwrite(dt, tmp)
  if (file.exists(path)) unlink(path)
  file.rename(tmp, path)
  invisible(path)
}

#' Confidence band index (internal)
#'
#' @param conf Numeric confidences.
#' @param bands Increasing band edges, e.g. c(0.3, 0.4, 0.5, 0.7, 1).
#' @return Integer band index (1 .. length(bands) - 1); values outside the
#'   edges are placed in the nearest band.
#' @keywords internal
#' @noRd
pam_band_index <- function(conf, bands) {
  findInterval(conf, bands, rightmost.closed = TRUE, all.inside = TRUE)
}

#' Confidence band label (internal)
#'
#' @param idx Band index from `pam_band_index()`.
#' @param bands Band edges.
#' @return Labels such as "0.30-0.40".
#' @keywords internal
#' @noRd
pam_band_label <- function(idx, bands) {
  sprintf("%.2f-%.2f", bands[idx], bands[idx + 1L])
}

#' Build the pool of candidate events for validation
#'
#' Takes the run's assembled detections through the Stage 4 rules (deployment
#' window, species lists, merging of windows into events) but with the
#' confidence cutoff set to the lowest stored confidence and no species
#' thresholds or seasons, so that events below your intended cutoff can also be
#' reviewed.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run (sub-folder of paths$detections).
#' @return A data.table of events with `event_id` (rel|species|start).
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' pool <- suppressMessages(pam_validation_pool(ex$cfg))
#' as.data.frame(pool)[, c("species", "confidence", "n_windows", "start_time")]
#' @export
pam_validation_pool <- function(cfg, run_id = cfg$birdnet$run_id) {
  det <- pam_load_detections(cfg, run_id)
  pc <- cfg$processing
  pc$min_confidence <- cfg$birdnet$min_confidence
  pool <- pam_clean_detections(det, pc, thresholds = NULL, seasons = NULL)$clean
  pool[, event_id := paste(rel, scientific_name, sprintf("%.1f", start_time), sep = "|")]
  pool[]
}

#' Draw a validation sample from a pool of events
#'
#' Pure function (no file access). Strategies:
#' * `"stratified"`: up to `n_per_cell` events per species x confidence band;
#'   restrict to some species with `species`.
#' * `"random"`: `n` events drawn at random from the whole pool (or from
#'   `species`).
#' * `"rare"`: species with at most `rare_max_events` events in the pool;
#'   up to `rare_n` events of each.
#'
#' @param pool Events from `pam_validation_pool()`.
#' @param strategy One of "stratified", "random", "rare".
#' @param bands Increasing confidence band edges.
#' @param n_per_cell,n,rare_max_events,rare_n See above.
#' @param species Optional names (scientific, common or "Scientific_Common").
#' @param seed Random seed.
#' @param exclude_ids `event_id`s already sampled; never drawn again.
#' @return A data.table: the sampled rows with `band_idx` and `band`.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' pool <- suppressMessages(pam_validation_pool(ex$cfg))
#' bands <- unlist(ex$cfg$validation$bands)
#' # at most one event per species and confidence band
#' smp <- pam_validation_sample(pool, "stratified", bands = bands, n_per_cell = 1)
#' as.data.frame(smp)[, c("species", "confidence", "band")]
#'
#' # five events at random from the whole pool
#' rnd <- pam_validation_sample(pool, "random", bands = bands, n = 5, seed = 42)
#' nrow(rnd)
#' @export
pam_validation_sample <- function(pool, strategy = c("stratified", "random", "rare"),
                                  bands, n_per_cell = 25L, n = 100L, species = NULL,
                                  rare_max_events = 30L, rare_n = 50L, seed = 1L,
                                  exclude_ids = character()) {
  strategy <- match.arg(strategy)
  p <- data.table::copy(pool)
  p[, band_idx := pam_band_index(confidence, bands)]
  p[, band := pam_band_label(band_idx, bands)]
  totals <- p[, .N, by = scientific_name]
  if (!is.null(species)) {
    wanted <- pam_match_species(p, species)   # evaluated outside `[` so the argument
    p <- p[wanted]                            # is not shadowed by the `species` column
  }
  p <- p[!event_id %in% exclude_ids]
  set.seed(seed)
  picked <- switch(
    strategy,
    stratified = p[, .SD[sample.int(.N, min(.N, as.integer(n_per_cell)))],
                   by = .(scientific_name, band)],
    random = p[sample.int(.N, min(.N, as.integer(n)))],
    rare = {
      rare <- totals[N <= rare_max_events, scientific_name]
      p[scientific_name %in% rare][
        , .SD[sample.int(.N, min(.N, as.integer(rare_n)))], by = scientific_name]
    })
  picked[]
}

#' Draw a validation round and add it to the sample file
#'
#' Each call adds a new round to `<detections>/<run_id>/validation/
#' validation_samples.csv`. Events drawn in earlier rounds are never drawn
#' again, so you can start small and add more later.
#'
#' @param cfg A `pam_config` object (uses the `validation` section).
#' @param run_id Detection run.
#' @param strategy "stratified", "random" or "rare" (see `pam_validation_sample()`).
#' @param n Events for the "random" strategy.
#' @param species Optional species restriction.
#' @param n_per_cell Events per species x band for "stratified". Defaults to
#'   `validation$n_per_cell`.
#' @param pool Optional pool from `pam_validation_pool()` (computed if NULL).
#' @return Invisibly, the newly added rows.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 5))
#' as.data.frame(new)[, c("sample_id", "species", "confidence", "clip_file")]
#' # the sample file is written to the run folder
#' file.exists(file.path(ex$cfg$paths$detections, "run01", "validation", "validation_samples.csv"))
#' @export
pam_validation_draw <- function(cfg, run_id = cfg$birdnet$run_id,
                                strategy = c("stratified", "random", "rare"),
                                n = 100L, species = NULL,
                                n_per_cell = cfg$validation$n_per_cell, pool = NULL) {
  strategy <- match.arg(strategy)
  vc <- cfg$validation
  val_dir <- file.path(cfg$paths$detections, run_id, "validation")
  dir.create(val_dir, recursive = TRUE, showWarnings = FALSE)
  samples_path <- file.path(val_dir, "validation_samples.csv")
  existing <- if (file.exists(samples_path)) {
    data.table::fread(samples_path, colClasses = list(character = c(
      "recording_date", "detection_datetime", "band", "clip_file", "spec_file")))
  } else NULL

  if (is.null(pool)) pool <- pam_validation_pool(cfg, run_id)
  if (!nrow(pool)) rlang::abort("No events available to sample")
  round_id <- if (is.null(existing)) 1L else max(existing$round) + 1L

  new <- pam_validation_sample(
    pool, strategy, bands = unlist(vc$bands), n_per_cell = n_per_cell, n = n,
    species = species, rare_max_events = vc$rare_max_events, rare_n = vc$rare_n,
    seed = vc$seed + round_id,
    exclude_ids = if (is.null(existing)) character() else existing$event_id)
  if (!nrow(new)) {
    pam_log("INFO", "no new events to sample (all already drawn)", "05_validation", cfg$paths$logs)
    return(invisible(new))
  }

  first_id <- if (is.null(existing)) 0L else max(existing$sample_id)
  pad <- vc$clip_pad_s
  new[, `:=`(sample_id = first_id + seq_len(.N), round = round_id, strategy = strategy,
             clip_start_s = pmax(0, start_time - pad))]
  new[, `:=`(clip_dur_s = end_time + pad - clip_start_s,
             event_offset_s = start_time - clip_start_s,
             event_end_offset_s = end_time - clip_start_s,
             clip_file = sprintf("s%06d.wav", sample_id),
             spec_file = sprintf("s%06d.png", sample_id),
             detection_datetime = format(detection_datetime, "%Y-%m-%d %H:%M:%OS1"),
             recording_date = as.character(recording_date))]
  keep <- c("sample_id", "round", "strategy", "event_id", "rel", "filename", "species",
            "scientific_name", "common_name", "confidence", "mean_confidence",
            "n_windows", "band", "start_time", "end_time", "grid", "recorder",
            "recording_date", "detection_datetime", "clip_file", "spec_file",
            "clip_start_s", "clip_dur_s", "event_offset_s", "event_end_offset_s")
  new <- new[, keep, with = FALSE]

  all_rows <- data.table::rbindlist(list(existing, new), use.names = TRUE, fill = TRUE)
  pam_write_csv_atomic(all_rows, samples_path)
  pam_log("INFO", sprintf("round %d (%s): %d new events, %d in total",
                          round_id, strategy, nrow(new), nrow(all_rows)),
          "05_validation", cfg$paths$logs)
  invisible(new)
}
