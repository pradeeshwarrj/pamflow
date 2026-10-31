# Shared foundation for the ecological products (activity, richness, abundance):
# one table of detections and recording effort per site, time bin and species.

#' Check the length of a time bin (internal)
#'
#' @param bin_days Number of days per bin.
#' @return `bin_days` as a single positive integer.
#' @keywords internal
#' @noRd
pam_check_bin_days <- function(bin_days) {
  if (!is.numeric(bin_days) || length(bin_days) != 1L || is.na(bin_days) ||
      bin_days < 1 || bin_days != round(bin_days)) {
    rlang::abort("`bin_days` must be a single whole number of days (1 or more).")
  }
  as.integer(bin_days)
}

#' First day of the time bin that contains each date (internal)
#'
#' @param date A Date vector.
#' @param origin The Date where the first bin starts.
#' @param bin_days Number of days per bin.
#' @return A Date vector of bin start days.
#' @keywords internal
#' @noRd
pam_bin_start <- function(date, origin, bin_days) {
  origin + (as.integer(date - origin) %/% bin_days) * bin_days
}

#' Recording effort per site and time bin (internal)
#'
#' Sums the daily effort of `pam_daily_effort()` into bins of `bin_days` days.
#' All sites share the same bin edges, which start on the first day with any
#' effort in the project, so a bin means the same dates everywhere.
#'
#' @param master Audio master table with `site_id`, `start_time` (POSIXct),
#'   `duration_s`, `qc_pass` and `in_deployment`.
#' @param bin_days Number of days per bin.
#' @param tz Time zone used for calendar days.
#' @param min_effort_h Minimum recorded hours for a bin to count as surveyed.
#' @return A data.table: `site_id`, `bin_start`, `bin_end` (last day of the
#'   bin), `effort_hours`, `n_days` (days with recordings in the bin) and
#'   `sufficient`. The first bin day is stored in the attribute `origin`.
#' @keywords internal
#' @noRd
pam_effort_bins <- function(master, bin_days = 1L, tz = "Asia/Kolkata", min_effort_h = 2) {
  bin_days <- pam_check_bin_days(bin_days)
  daily <- pam_daily_effort(master, tz = tz, min_effort_h = 0)
  empty <- data.table::data.table(
    site_id = character(), bin_start = as.Date(character()), bin_end = as.Date(character()),
    effort_hours = numeric(), n_days = integer(), sufficient = logical())
  if (nrow(daily) == 0L) {
    attr(empty, "origin") <- as.Date(NA)
    return(empty)
  }
  origin <- min(daily$occasion_date)
  daily[, bin_start := pam_bin_start(occasion_date, origin, bin_days)]
  eff <- daily[, .(effort_hours = sum(effort_hours), n_days = .N), by = .(site_id, bin_start)]
  eff[, bin_end := bin_start + bin_days - 1L]
  eff[, sufficient := effort_hours >= min_effort_h]
  data.table::setcolorder(eff, c("site_id", "bin_start", "bin_end", "effort_hours",
                                 "n_days", "sufficient"))
  data.table::setorder(eff, site_id, bin_start)
  attr(eff, "origin") <- origin
  eff[]
}

#' Read the audio master table with local-time recording starts (internal)
#'
#' @param cfg A `pam_config` object.
#' @return A list: `master` (data.table, `start_time` in the project time zone)
#'   and `tz`.
#' @keywords internal
#' @noRd
pam_read_master_local <- function(cfg) {
  master_path <- file.path(cfg$paths$metadata, "audio_master.csv")
  if (!file.exists(master_path)) {
    rlang::abort("audio_master.csv not found. Run the scan (Stage 1) first.")
  }
  master <- data.table::fread(master_path)
  tz <- pam_or(cfg$filenames$timezone, "Asia/Kolkata")
  if (!nzchar(tz)) tz <- "Asia/Kolkata"
  if ("start_time" %in% names(master)) {
    if (is.character(master$start_time)) {
      master[, start_time := as.POSIXct(start_time, tz = "UTC")]
    }
    attr(master$start_time, "tzone") <- tz
  }
  list(master = master, tz = tz)
}

#' Master table of usable recordings with site identifiers (internal)
#'
#' @param cfg A `pam_config` object.
#' @return A list: `master` (recordings that passed QC and lie inside a
#'   deployment, with `site_id`) and `tz` (project time zone).
#' @keywords internal
#' @noRd
pam_site_master <- function(cfg) {
  loaded <- pam_read_master_local(cfg)
  master <- loaded$master[qc_pass == TRUE & in_deployment == TRUE]
  pam_site_id(master)
  list(master = master, tz = loaded$tz)
}

#' Cleaned events with site, date and hour, ready for counting (internal)
#'
#' Reads `detections_clean.csv`, attaches `site_id`, the local `occasion_date`
#' and `hour` of each event, and applies the optional species selection and
#' thresholds. Shared by the products that count detections.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @param master Output of `pam_site_master()$master`.
#' @param thresholds Optional table from `pam_read_thresholds()`.
#' @param extra_by Names of further detection columns that must exist.
#' @param species Optional names (scientific, common or species) to keep.
#' @return A list: `det` (events after the species selection and thresholds,
#'   without events that have no site or date) and `species_tab` (species, and
#'   the `extra_by` columns, present after the species selection but before the
#'   thresholds, so that species removed by a threshold still get zero rows).
#' @keywords internal
#' @noRd
pam_prepare_events <- function(cfg, run_id, master, thresholds = NULL,
                               extra_by = character(), species = NULL) {
  det_path <- file.path(cfg$paths$detections, run_id, "processed", "detections_clean.csv")
  if (!file.exists(det_path)) {
    rlang::abort(sprintf("detections_clean.csv not found for run '%s'. Run Stage 4 first.", run_id))
  }
  det <- data.table::fread(det_path)
  missing_cols <- setdiff(c("species", "scientific_name", "confidence", "grid", extra_by), names(det))
  if (length(missing_cols)) {
    rlang::abort(sprintf("detections_clean.csv lacks the column(s): %s",
                         paste(missing_cols, collapse = ", ")))
  }
  if (!"common_name" %in% names(det)) det[, common_name := NA_character_]

  # attach site_id through grid (and deployment when present)
  det[, grid := as.character(grid)]
  lookup_cols <- "grid"
  if ("deployment_id" %in% names(det) && "deployment_id" %in% names(master)) {
    det[, deployment_id := as.character(deployment_id)]
    lookup_cols <- c("grid", "deployment_id")
  }
  lookup <- unique(master[, c(lookup_cols, "site_id"), with = FALSE])
  lookup[, grid := as.character(grid)]
  if ("deployment_id" %in% lookup_cols) lookup[, deployment_id := as.character(deployment_id)]
  det <- merge(det, lookup, by = lookup_cols, all.x = TRUE, sort = FALSE)

  time_col <- intersect(c("detection_datetime", "recording_start"), names(det))
  if (!length(time_col)) {
    rlang::abort("Detections need 'detection_datetime' or 'recording_start'.")
  }
  time_text <- as.character(det[[time_col[1L]]])
  det[, occasion_date := as.Date(substr(time_text, 1L, 10L))]
  det[, hour := as.integer(substr(time_text, 12L, 13L))]

  if (!is.null(species)) {
    keep <- pam_match_species(det, species)
    det <- det[keep]
  }
  species_tab <- unique(det[, c("species", "scientific_name", extra_by), with = FALSE])

  if (!is.null(thresholds)) {
    det <- merge(det, thresholds[, .(scientific_name, thr_extra = threshold)],
                 by = "scientific_name", all.x = TRUE, sort = FALSE)
    det <- det[is.na(thr_extra) | confidence >= thr_extra]
    det[, thr_extra := NULL]
  }
  det <- det[!is.na(site_id) & !is.na(occasion_date)]
  list(det = det, species_tab = species_tab)
}

#' Check or look up the minimum effort per time bin (internal)
#'
#' @param cfg A `pam_config` object.
#' @param min_effort_hours A number of hours, or `NULL` to use
#'   `occupancy$min_effort_hours` (2 if not set).
#' @return A single number of 0 or more.
#' @keywords internal
#' @noRd
pam_resolve_min_effort <- function(cfg, min_effort_hours = NULL) {
  value <- pam_or(min_effort_hours, pam_or(cfg$occupancy$min_effort_hours, 2))
  if (!is.numeric(value) || length(value) != 1L || is.na(value) || value < 0) {
    rlang::abort("`min_effort_hours` must be a single number of 0 or more.")
  }
  value
}

#' Detection counts and recording effort per site and time bin (internal)
#'
#' Shared by the products built on detections per site and time bin. Counts are
#' sparse: only site-bin-species combinations with at least one event have a
#' row. Effort has a row for every site and bin with usable recordings.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @param bin_days Length of a time bin in days (already checked).
#' @param thresholds Optional table from `pam_read_thresholds()`.
#' @param min_effort_h Minimum recorded hours for a bin to count as surveyed.
#' @param extra_by Names of further detection columns to count by.
#' @param species Optional names (scientific, common or species) to keep.
#' @return A list: `counts` (`site_id`, `bin_start`, `species`,
#'   `scientific_name`, the `extra_by` columns, `n_detections`, `n_files`,
#'   `max_confidence`), `effort` (see `pam_effort_bins()`), `species_tab`
#'   (species present before the thresholds) and `origin` (first bin day).
#' @keywords internal
#' @noRd
pam_binned_counts <- function(cfg, run_id, bin_days, thresholds, min_effort_h,
                              extra_by = character(), species = NULL) {
  stage <- "07_table"; log_dir <- cfg$paths$logs
  sm <- pam_site_master(cfg)
  master <- sm$master
  effort <- pam_effort_bins(master, bin_days = bin_days, tz = sm$tz,
                            min_effort_h = min_effort_h)
  origin <- attr(effort, "origin")
  ev <- pam_prepare_events(cfg, run_id, master, thresholds = thresholds,
                          extra_by = extra_by, species = species)
  det <- ev$det
  species_tab <- ev$species_tab
  if (nrow(det)) det[, bin_start := pam_bin_start(occasion_date, origin, bin_days)]

  by_cols <- c("site_id", "bin_start", "species", "scientific_name", extra_by)
  if (nrow(det)) {
    has_rel <- "rel" %in% names(det)
    counts <- det[, .(n_detections = .N,
                      n_files = if (has_rel) data.table::uniqueN(rel) else NA_integer_,
                      max_confidence = max(confidence)), by = by_cols]
    known <- effort[, .(site_id, bin_start)]
    n_orphan <- nrow(counts[!known, on = c("site_id", "bin_start")])
    if (n_orphan > 0L) {
      pam_log("WARN", sprintf("%d site-bin-species rows have detections but no recording effort; dropped",
                              n_orphan), stage, log_dir)
    }
    counts <- counts[known, on = c("site_id", "bin_start"), nomatch = NULL]
  } else {
    counts <- data.table::data.table(
      site_id = character(), bin_start = as.Date(character()), species = character(),
      scientific_name = character(), n_detections = integer(), n_files = integer(),
      max_confidence = numeric())
    for (nm in extra_by) data.table::set(counts, j = nm, value = character())
  }

  list(counts = counts, effort = effort, species_tab = species_tab, origin = origin)
}

#' Table of detections and recording effort per site, time bin and species
#'
#' The shared starting point for activity patterns, richness and abundance
#' indices. It counts the cleaned detections (Stage 4) of every species in
#' every site and time bin, and puts the recording effort next to the counts,
#' so rates per recorded hour can be compared between sites that were recorded
#' for different lengths of time.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run (sub-folder of paths$detections).
#' @param bin_days Length of a time bin in days. `NULL` (the default) uses
#'   `occupancy$occasion_length_days` from the config (1 if not set); use 7 for
#'   weekly bins.
#' @param thresholds Optional per-species thresholds: a data frame, or the path
#'   of a CSV file, with `scientific_name` and `threshold` (for example the
#'   result of `pam_species_thresholds()`). They are applied to the event
#'   confidence on top of Stage 4, so they can only remove more events. To keep
#'   events below the Stage 4 cut-off, lower it there and run Stage 4 again.
#' @param min_effort_hours Minimum recorded hours for a bin to count as
#'   surveyed. `NULL` uses `occupancy$min_effort_hours` (2 if not set).
#' @param extra_by Optional names of further detection columns to count by, for
#'   example a call type, if your detections have one.
#' @param complete If `TRUE` (the default), every surveyed site and bin gets a
#'   row for every species, with 0 where it was not detected. Set to `FALSE` for
#'   very large projects to keep only rows with detections.
#' @param write If `TRUE`, also save the table as
#'   `<outputs>/<run_id>/detection_table.csv`. Nothing is written by default.
#' @return A data.table with one row per site, bin and species (and `extra_by`
#'   column): `site_id`, `bin_start`, `bin_end`, `species`, `scientific_name`,
#'   `n_detections` (events), `n_files` (recordings with a detection),
#'   `max_confidence`, `effort_hours`, `n_days`, `sufficient` (the bin reached
#'   the minimum effort) and `detections_per_hour`. Bins below the minimum
#'   effort are kept and flagged, not dropped. The bin length and first bin day
#'   are stored in the attributes `bin_days` and `origin`.
#' @details
#' ## Sites and effort
#' Sites follow the occupancy stage: the grid name, or `grid_deploymentId` for
#' grids with several deployments. Effort counts recordings that passed QC and
#' lie inside a deployment window. Detections that fall in a site and bin with no
#' effort (for example, in a recording that failed QC) are dropped with a
#' warning.
#'
#' ## Time bins
#' All bins start on the first day with any recording in the project, so a bin
#' covers the same dates at every site.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#' tab <- suppressMessages(pam_detection_table(ex$cfg))
#' as.data.frame(tab)[, c("site_id", "bin_start", "species", "n_detections", "effort_hours")]
#' # two-day bins instead of one-day bins
#' tab2 <- suppressMessages(pam_detection_table(ex$cfg, bin_days = 2))
#' unique(tab2$bin_start)
#' @export
pam_detection_table <- function(cfg, run_id = cfg$birdnet$run_id, bin_days = NULL,
                                thresholds = NULL, min_effort_hours = NULL,
                                extra_by = character(), complete = TRUE, write = FALSE) {
  stage <- "07_table"; log_dir <- cfg$paths$logs
  bin_days <- pam_check_bin_days(pam_or(bin_days, pam_or(cfg$occupancy$occasion_length_days, 1L)))
  min_effort_h <- pam_resolve_min_effort(cfg, min_effort_hours)
  extra_by <- as.character(extra_by)
  thresholds <- pam_read_thresholds(thresholds, "thresholds")

  bc <- pam_binned_counts(cfg, run_id, bin_days, thresholds, min_effort_h, extra_by = extra_by)
  counts <- bc$counts
  effort <- bc$effort
  species_tab <- bc$species_tab
  origin <- bc$origin
  by_cols <- c("site_id", "bin_start", "species", "scientific_name", extra_by)

  if (isTRUE(complete) && nrow(species_tab) && nrow(effort)) {
    n_eff <- nrow(effort); n_sp <- nrow(species_tab)
    skeleton <- cbind(effort[rep(seq_len(n_eff), times = n_sp), .(site_id, bin_start)],
                      species_tab[rep(seq_len(n_sp), each = n_eff)])
    counts <- merge(skeleton, counts, by = by_cols, all.x = TRUE, sort = FALSE)
    counts[is.na(n_detections), `:=`(n_detections = 0L, n_files = 0L)]
  }

  out <- merge(counts, effort, by = c("site_id", "bin_start"), all.x = TRUE, sort = FALSE)
  out[, detections_per_hour := data.table::fifelse(effort_hours > 0, n_detections / effort_hours,
                                                   NA_real_)]
  data.table::setcolorder(out, c("site_id", "bin_start", "bin_end", "species", "scientific_name",
                                 extra_by, "n_detections", "n_files", "max_confidence",
                                 "effort_hours", "n_days", "sufficient", "detections_per_hour"))
  data.table::setorderv(out, c("site_id", "bin_start", "species", extra_by))
  attr(out, "bin_days") <- bin_days
  attr(out, "origin") <- origin

  pam_log("INFO", sprintf("Detection table: %d rows, %d sites, %d bins of %d day(s), %d species",
                          nrow(out), data.table::uniqueN(out$site_id),
                          data.table::uniqueN(out$bin_start), bin_days,
                          data.table::uniqueN(out$species)), stage, log_dir)

  if (isTRUE(write)) {
    path <- file.path(cfg$paths$outputs, run_id, "detection_table.csv")
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    pam_write_csv_atomic(out, path)
    pam_log("INFO", sprintf("Detection table written to %s", path), stage, log_dir)
  }
  out[]
}
