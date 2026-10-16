#' Resolve a config path against the project root (internal)
#'
#' @param path Relative or absolute path, or NULL.
#' @param root Project root.
#' @return An absolute path, or NULL.
#' @keywords internal
#' @noRd
pam_resolve_path <- function(path, root) {
  if (is.null(path) || length(path) == 0L || is.na(path)) return(NULL)
  if (fs::is_absolute_path(path)) as.character(path) else as.character(fs::path(root, path))
}

#' Default value for NULL (internal)
#' @keywords internal
#' @noRd
pam_or <- function(x, y) if (is.null(x)) y else x

#' Match detections against a list of species names (internal)
#'
#' @param det Detections with `scientific_name`, `common_name`, `species`.
#' @param terms Character vector of names (case-insensitive).
#' @return Logical vector, TRUE where any name field matches.
#' @keywords internal
#' @noRd
pam_match_species <- function(det, terms) {
  terms <- tolower(trimws(terms))
  tolower(det$scientific_name) %in% terms |
    tolower(det$common_name) %in% terms |
    tolower(det$species) %in% terms
}

#' Write a table with POSIXct columns as local-time text (internal)
#'
#' @param dt A data.table.
#' @param path Output CSV path.
#' @return `path`, invisibly.
#' @keywords internal
#' @noRd
pam_fwrite_local <- function(dt, path) {
  out <- data.table::copy(dt)
  for (nm in names(out)[vapply(out, inherits, logical(1), "POSIXct")]) {
    data.table::set(out, j = nm, value = format(out[[nm]], "%Y-%m-%d %H:%M:%OS1"))
  }
  data.table::fwrite(out, path)
  invisible(path)
}

#' Apply the cleaning rules to a detections table
#'
#' Pure function (no file access), so it can be tested directly. Rules run in a
#' fixed order and each removed detection is kept with its reason.
#'
#' @param det A data.table of detections as returned by
#'   `pam_assemble_detections()`, plus `file_duration_s`.
#' @param pc The `processing` section of the config: `min_confidence`,
#'   `species_whitelist`, `species_blacklist`, `date_range`,
#'   `drop_outside_deployment`, `max_overrun_s`, `merge_gap_s`.
#' @param thresholds Optional data.table with `scientific_name` and
#'   `threshold`; overrides `min_confidence` for those species.
#' @param seasons Optional data.table with `scientific_name`, `month_start`,
#'   `month_end` (1-12; start > end wraps over the year end).
#' @return A list: `clean` (one row per event, with `confidence` = maximum,
#'   `mean_confidence`, `n_windows`), `removed` (rows with `reason`), `steps`
#'   (rule, n_before, n_removed).
#' @export
pam_clean_detections <- function(det, pc, thresholds = NULL, seasons = NULL) {
  det <- data.table::copy(det)
  steps <- list(); removed <- list()
  rule <- function(dt, keep, label) {
    keep <- data.table::fcoalesce(keep, FALSE)
    steps[[length(steps) + 1L]] <<- data.table::data.table(
      rule = label, n_before = nrow(dt), n_removed = sum(!keep))
    if (any(!keep)) {
      r <- dt[!keep]
      r[, reason := label]
      removed[[length(removed) + 1L]] <<- r
    }
    dt[keep]
  }

  det[, detection_date := as.Date(format(detection_datetime, "%Y-%m-%d"))]

  det <- rule(det, !is.na(det$confidence) & !is.na(det$start_time) & !is.na(det$end_time) &
                det$start_time >= 0 & det$end_time > det$start_time,
              "invalid confidence or timestamps")
  det <- rule(det, !is.na(det$recording_start), "file not in master table")
  det <- rule(det, det$end_time <= det$file_duration_s + pam_or(pc$max_overrun_s, 3),
              "beyond end of recording")
  if (isTRUE(pam_or(pc$drop_outside_deployment, TRUE))) {
    det <- rule(det, det$in_deployment %in% TRUE, "outside deployment window")
  }

  wl <- unlist(pc$species_whitelist); bl <- unlist(pc$species_blacklist)
  if (length(wl)) det <- rule(det, pam_match_species(det, wl), "species not on whitelist")
  if (length(bl)) det <- rule(det, !pam_match_species(det, bl), "species on blacklist")

  dr <- unlist(pc$date_range)
  if (length(dr) == 2L) {
    dr <- as.Date(dr)
    det <- rule(det, det$detection_date >= dr[1] & det$detection_date <= dr[2],
                "outside date range")
  }

  if (!is.null(seasons)) {
    det <- merge(det, seasons[, .(scientific_name, month_start, month_end)],
                 by = "scientific_name", all.x = TRUE, sort = FALSE)
    mon <- as.integer(format(det$detection_datetime, "%m"))
    in_season <- is.na(det$month_start) |
      ifelse(det$month_start <= det$month_end,
             mon >= det$month_start & mon <= det$month_end,
             mon >= det$month_start | mon <= det$month_end)
    det <- rule(det, in_season, "outside species season")
    det[, c("month_start", "month_end") := NULL]
  }

  if (!is.null(thresholds)) {
    det <- merge(det, thresholds[, .(scientific_name, thr_species = threshold)],
                 by = "scientific_name", all.x = TRUE, sort = FALSE)
  } else {
    det[, thr_species := NA_real_]
  }
  det[, threshold := data.table::fifelse(is.na(thr_species), pc$min_confidence, thr_species)]
  det <- rule(det, det$confidence >= det$threshold, "below confidence threshold")
  if (nrow(det) == 0L) {                      # nothing left to merge
    clean <- data.table::copy(det)
    clean[, c("threshold", "thr_species", "file_duration_s") := NULL]
    clean[, `:=`(mean_confidence = numeric(), n_windows = integer())]
    steps[[length(steps) + 1L]] <- data.table::data.table(
      rule = "merged overlapping windows into events (not removed)",
      n_before = 0L, n_removed = 0L)
    return(list(clean = clean[], removed = data.table::rbindlist(removed, fill = TRUE),
                steps = data.table::rbindlist(steps)))
  }

  # merge overlapping windows of the same species within a recording into events
  n_windows_in <- nrow(det)
  keys <- c("rel", "scientific_name")
  gap <- pam_or(pc$merge_gap_s, 0)
  data.table::setorderv(det, c(keys, "start_time"))
  det[, event := cumsum(start_time >= data.table::shift(cummax(end_time), fill = -Inf) + gap),
      by = keys]
  agg <- det[, .(start_time = min(start_time), end_time = max(end_time),
                 confidence = max(confidence), mean_confidence = mean(confidence),
                 n_windows = .N), by = c(keys, "event")]
  drop_cols <- c("start_time", "end_time", "confidence", "event", "detection_datetime",
                 "threshold", "thr_species", "file_duration_s")
  meta <- unique(det[, setdiff(names(det), drop_cols), with = FALSE], by = keys)
  clean <- merge(agg, meta, by = keys, all.x = TRUE, sort = FALSE)
  clean[, event := NULL]
  clean[, detection_datetime := recording_start + start_time]
  steps[[length(steps) + 1L]] <- data.table::data.table(
    rule = "merged overlapping windows into events (not removed)",
    n_before = n_windows_in, n_removed = n_windows_in - nrow(clean))

  first <- c("filename", "species", "scientific_name", "common_name", "confidence",
             "mean_confidence", "n_windows", "start_time", "end_time", "site", "grid",
             "recorder", "deployment_id", "recording_date", "detection_date",
             "recording_start", "detection_datetime", "rel")
  data.table::setcolorder(clean, intersect(first, names(clean)))
  data.table::setorder(clean, grid, detection_datetime)

  list(clean = clean[], removed = data.table::rbindlist(removed, fill = TRUE),
       steps = data.table::rbindlist(steps))
}

#' Stage 4: clean the detections of a run
#'
#' Assembles the run's detections, applies `pam_clean_detections()` using the
#' `processing` settings of the config, and writes the results to
#' `<detections>/<run_id>/processed/`.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run (sub-folder of paths$detections). Defaults to
#'   birdnet$run_id.
#' @return A list: `clean`, `removed`, `steps` (see `pam_clean_detections()`).
#' @details Writes `detections_clean.csv`, `removed_detections.csv` (with the
#'   reason for each removal) and `processing_steps.csv`. Times are written as
#'   local-time text. Run with
#'   `pam_run_stage("04_process", pam_process_detections, cfg, run_id = "...")`.
#' @export
pam_process_detections <- function(cfg, run_id = cfg$birdnet$run_id) {
  stage <- "04_process"; log_dir <- cfg$paths$logs
  pc <- cfg$processing; root <- cfg$paths$project_root
  out_dir <- file.path(cfg$paths$detections, run_id, "processed")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  det <- pam_assemble_detections(cfg, run_id = run_id)
  m <- data.table::fread(file.path(cfg$paths$metadata, "audio_master.csv"),
                         select = c("file_path", "duration_s"))
  m[, rel := as.character(fs::path_rel(file_path, start = cfg$paths$audio_standardized))]
  det <- merge(det, m[, .(rel, file_duration_s = duration_s)], by = "rel",
               all.x = TRUE, sort = FALSE)

  read_table <- function(path, needed) {
    p <- pam_resolve_path(path, root)
    if (is.null(p)) return(NULL)
    if (!file.exists(p)) rlang::abort(sprintf("File not found: %s", p))
    tab <- data.table::fread(p)
    if (!all(needed %in% names(tab))) {
      rlang::abort(sprintf("%s must have columns: %s", basename(p), paste(needed, collapse = ", ")))
    }
    tab
  }
  thr <- read_table(pc$species_thresholds_file, c("scientific_name", "threshold"))
  ss <- read_table(pc$species_season_file, c("scientific_name", "month_start", "month_end"))

  res <- pam_clean_detections(det, pc, thresholds = thr, seasons = ss)

  pam_fwrite_local(res$clean, file.path(out_dir, "detections_clean.csv"))
  pam_fwrite_local(res$removed, file.path(out_dir, "removed_detections.csv"))
  data.table::fwrite(res$steps, file.path(out_dir, "processing_steps.csv"))

  pam_log("INFO", sprintf("%d raw detections -> %d events after cleaning (%d removed)",
                          nrow(det), nrow(res$clean), nrow(res$removed)), stage, log_dir)
  res
}
