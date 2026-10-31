# Activity and phenology patterns: detections per recorded hour, by hour of day,
# day, week or month, from the cleaned detections and the recording effort.

utils::globalVariables(c("period", "n_sites_surveyed", "relative_activity", "date"))

#' Recording effort per site, date and hour of day (internal)
#'
#' Splits every recording over the clock hours it covers, so a recording from
#' 06:50 to 07:20 counts 10 minutes in hour 6 and 20 minutes in hour 7, and a
#' recording that crosses midnight counts in both days. Times are local clock
#' times; the one-hour shift at a daylight-saving change is ignored.
#'
#' @param master Master table of usable recordings with `site_id`,
#'   `start_time` (POSIXct), `duration_s`, `qc_pass` and `in_deployment`.
#' @param tz Time zone for the clock hours.
#' @return A data.table: `site_id`, `date` (Date), `hour` (0-23) and
#'   `effort_hours`.
#' @keywords internal
#' @noRd
pam_hourly_effort <- function(master, tz = "Asia/Kolkata") {
  empty <- data.table::data.table(
    site_id = character(), date = as.Date(character()), hour = integer(),
    effort_hours = numeric())
  dt <- master[qc_pass == TRUE & in_deployment == TRUE & !is.na(start_time) &
                 !is.na(duration_s) & duration_s > 0.001]
  if (nrow(dt) == 0L) return(empty)

  start <- dt$start_time
  attr(start, "tzone") <- tz
  day_number <- as.integer(as.Date(format(start, "%Y-%m-%d")))
  second_of_day <- as.integer(format(start, "%H")) * 3600 +
    as.integer(format(start, "%M")) * 60 + as.integer(format(start, "%S"))
  t_start <- day_number * 86400 + second_of_day      # seconds on a local clock scale
  t_end <- t_start + dt$duration_s
  first_slot <- floor(t_start / 3600)
  last_slot <- floor((t_end - 1e-6) / 3600)
  n_slots <- as.integer(last_slot - first_slot + 1)

  row <- rep(seq_len(nrow(dt)), times = n_slots)
  slot <- first_slot[row] + sequence(n_slots) - 1
  overlap_s <- pmin(t_end[row], (slot + 1) * 3600) - pmax(t_start[row], slot * 3600)
  out <- data.table::data.table(
    site_id = dt$site_id[row],
    date = as.Date(slot %/% 24, origin = "1970-01-01"),
    hour = as.integer(slot %% 24),
    effort_hours = overlap_s / 3600)
  out[, .(effort_hours = sum(effort_hours)), by = .(site_id, date, hour)]
}

#' Period that a date and hour belong to (internal)
#'
#' @param date A Date vector.
#' @param hour Hour of day (0-23), used for `by = "hour"`.
#' @param by One of "hour", "day", "week" (starting on Monday) or "month".
#' @return Integer hours for "hour", otherwise the Date on which the period
#'   starts.
#' @keywords internal
#' @noRd
pam_period <- function(date, hour, by) {
  switch(by,
         hour = as.integer(hour),
         day = date,
         week = date - (as.integer(format(date, "%u")) - 1L),
         month = as.Date(format(date, "%Y-%m-01")),
         rlang::abort("`by` must be one of hour, day, week or month."))
}

#' Activity patterns: detections per recorded hour
#'
#' Counts the cleaned detections of each species in every hour of the day, day,
#' week or month, and divides them by the time that was recorded in that period.
#' Because the division uses recording effort, periods and sites that were
#' recorded for different lengths of time can be compared. Use it for daily
#' (diel) activity patterns and for seasonal patterns such as migration or
#' breeding timing.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run (sub-folder of paths$detections).
#' @param by The period: `"hour"` (hour of the day, pooled over all dates),
#'   `"day"`, `"week"` (weeks start on Monday) or `"month"`.
#' @param by_site If `FALSE` (the default), sites are pooled: the rate is all
#'   detections divided by all recorded hours. If `TRUE`, one row per site.
#' @param species Optional species to keep: scientific names, common names or
#'   species labels, in any capitalization. `NULL` keeps all.
#' @param thresholds Optional per-species thresholds (a data frame, or the path
#'   of a CSV file, with `scientific_name` and `threshold`), for example from
#'   `pam_species_thresholds()`. They are applied on top of Stage 4 and can only
#'   remove more events.
#' @param min_effort_hours Periods with less recorded time than this get no
#'   rate (`NA`) and `sufficient = FALSE`. Default 0 keeps every period with any
#'   recording.
#' @param write If `TRUE`, also save the table as
#'   `<outputs>/<run_id>/activity_<by>.csv`. Nothing is written by default.
#' @return A data.table with one row per period and species (and per site when
#'   `by_site = TRUE`): `period` (hour 0-23, or the first day of the period),
#'   `species`, `scientific_name`, `n_detections`, `effort_hours`,
#'   `detections_per_hour`, `relative_activity` (the rate divided by the
#'   species' highest rate, so 1 marks its peak), `sufficient` and, for pooled
#'   tables, `n_sites_surveyed` and `n_sites_detected`. Periods with recordings
#'   but no detection get 0. Periods with no recording have no row. The choices
#'   are stored in the attributes `by` and `by_site`.
#' @details
#' ## What the rate means
#' `detections_per_hour` is the number of detected events (Stage 4 merges
#' overlapping BirdNET windows into events) per hour of recording. It is an
#' activity index: it depends on how often and how loudly animals call, not only
#' on how many are present, and on the confidence thresholds used. Compare it
#' between periods and sites for the same species, and avoid comparing raw
#' rates between species.
#'
#' ## Time of day
#' Hours are local clock hours of the project time zone. A recording is split
#' over the hours it covers, so effort is exact for recordings that start part
#' way through an hour or cross midnight.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#' act <- suppressMessages(pam_activity(ex$cfg, by = "hour"))
#' as.data.frame(act)[, c("period", "species", "n_detections", "detections_per_hour")]
#' # one row per site and day
#' day <- suppressMessages(pam_activity(ex$cfg, by = "day", by_site = TRUE))
#' head(as.data.frame(day)[, c("site_id", "period", "species", "n_detections")], 4)
#' @seealso [pam_plot_activity()], [pam_detection_table()]
#' @export
pam_activity <- function(cfg, run_id = cfg$birdnet$run_id,
                         by = c("hour", "day", "week", "month"), by_site = FALSE,
                         species = NULL, thresholds = NULL, min_effort_hours = 0,
                         write = FALSE) {
  by <- match.arg(by)
  by_unit <- by                       # plain name for use inside data.table calls
  stage <- "07_activity"; log_dir <- cfg$paths$logs
  if (!is.logical(by_site) || length(by_site) != 1L || is.na(by_site)) {
    rlang::abort("`by_site` must be TRUE or FALSE.")
  }
  if (!is.numeric(min_effort_hours) || length(min_effort_hours) != 1L ||
      is.na(min_effort_hours) || min_effort_hours < 0) {
    rlang::abort("`min_effort_hours` must be a single number of 0 or more.")
  }
  thresholds <- pam_read_thresholds(thresholds, "thresholds")

  sm <- pam_site_master(cfg)
  ev <- pam_prepare_events(cfg, run_id, sm$master, thresholds = thresholds, species = species)
  det <- ev$det
  species_tab <- ev$species_tab
  if (nrow(species_tab) == 0L) {
    rlang::abort("No detections to summarise (check the species selection and Stage 4).")
  }

  keys <- if (by_site) c("site_id", "period") else "period"
  effort <- pam_hourly_effort(sm$master, sm$tz)
  effort[, period := pam_period(date, hour, by_unit)]
  eff <- effort[, .(effort_hours = sum(effort_hours),
                    n_sites_surveyed = data.table::uniqueN(site_id)), by = keys]
  if (nrow(eff) == 0L) rlang::abort("No usable recordings found in the master table.")

  by_cols <- c(keys, "species", "scientific_name")
  det <- det[!is.na(hour)]
  if (nrow(det)) {
    det[, period := pam_period(occasion_date, hour, by_unit)]
    counts <- det[, .(n_detections = .N, n_sites_detected = data.table::uniqueN(site_id)),
                  by = by_cols]
    known <- eff[, keys, with = FALSE]
    n_orphan <- nrow(counts[!known, on = keys])
    if (n_orphan > 0L) {
      pam_log("WARN", sprintf("%d period-species rows have detections but no recording effort; dropped",
                              n_orphan), stage, log_dir)
    }
    counts <- counts[known, on = keys, nomatch = NULL]
  } else {
    counts <- eff[0L, keys, with = FALSE]
    counts[, `:=`(species = character(), scientific_name = character(),
                  n_detections = integer(), n_sites_detected = integer())]
  }

  n_eff <- nrow(eff); n_sp <- nrow(species_tab)
  skeleton <- cbind(eff[rep(seq_len(n_eff), times = n_sp)],
                    species_tab[rep(seq_len(n_sp), each = n_eff)])
  out <- merge(skeleton, counts, by = by_cols, all.x = TRUE, sort = FALSE)
  out[is.na(n_detections), `:=`(n_detections = 0L, n_sites_detected = 0L)]

  out[, sufficient := effort_hours >= min_effort_hours]
  out[, detections_per_hour := data.table::fifelse(sufficient & effort_hours > 0,
                                                   n_detections / effort_hours, NA_real_)]
  group_cols <- c("species", if (by_site) "site_id")
  out[, relative_activity := {
    peak <- suppressWarnings(max(detections_per_hour, na.rm = TRUE))
    if (is.finite(peak) && peak > 0) detections_per_hour / peak else NA_real_
  }, by = group_cols]
  if (by_site) out[, c("n_sites_surveyed", "n_sites_detected") := NULL]

  first <- c(if (by_site) "site_id", "period", "species", "scientific_name")
  data.table::setcolorder(out, first)
  data.table::setorderv(out, c(if (by_site) "site_id", "species", "period"))
  attr(out, "by") <- by
  attr(out, "by_site") <- by_site

  pam_log("INFO", sprintf("Activity by %s: %d rows, %d species, %d periods", by, nrow(out),
                          data.table::uniqueN(out$species), data.table::uniqueN(out$period)),
          stage, log_dir)

  if (isTRUE(write)) {
    path <- file.path(cfg$paths$outputs, run_id, sprintf("activity_%s.csv", by))
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    pam_write_csv_atomic(out, path)
    pam_log("INFO", sprintf("Activity table written to %s", path), stage, log_dir)
  }
  out[]
}

#' Plot activity patterns
#'
#' Draws the result of [pam_activity()] with one panel per species: bars for the
#' hour of the day, a line for days, weeks and months.
#'
#' @param activity A pooled table from `pam_activity(by_site = FALSE)`.
#' @param species Optional species (scientific or common name as in the table)
#'   to plot; `NULL` plots all.
#' @param relative If `TRUE`, plot `relative_activity` (1 = the species' peak)
#'   instead of detections per recorded hour, so species can be compared by
#'   timing.
#' @return A ggplot object.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#' act <- suppressMessages(pam_activity(ex$cfg, by = "hour"))
#' p <- pam_plot_activity(act)
#' class(p)
#' @export
pam_plot_activity <- function(activity, species = NULL, relative = FALSE) {
  by <- attr(activity, "by")
  if (is.null(by)) rlang::abort("`activity` must be a table from pam_activity().")
  if ("site_id" %in% names(activity)) {
    rlang::abort("Plot a pooled table: run pam_activity() with by_site = FALSE.")
  }
  dt <- data.table::copy(data.table::as.data.table(activity))
  if (!is.null(species)) {
    wanted <- species
    dt <- dt[species %in% wanted | scientific_name %in% wanted]
    if (nrow(dt) == 0L) rlang::abort("None of the requested species are in `activity`.")
  }
  dt[, value := if (isTRUE(relative)) relative_activity else detections_per_hour]

  p <- ggplot2::ggplot(dt, ggplot2::aes(x = period, y = value))
  if (by == "hour") {
    p <- p + ggplot2::geom_col(fill = "#6c9bd2", na.rm = TRUE) +
      ggplot2::scale_x_continuous(breaks = seq(0, 21, by = 3))
  } else {
    p <- p + ggplot2::geom_line(colour = "#6c9bd2", na.rm = TRUE) +
      ggplot2::geom_point(colour = "#3a6ea5", size = 1.5, na.rm = TRUE)
  }
  x_label <- c(hour = "Hour of day", day = "Day", week = "Week starting",
               month = "Month starting")[[by]]
  p +
    ggplot2::facet_wrap(~ species, scales = if (isTRUE(relative)) "fixed" else "free_y") +
    ggplot2::labs(x = x_label, y = if (isTRUE(relative)) "Relative activity"
                  else "Detections per recorded hour") +
    ggplot2::theme_minimal()
}
