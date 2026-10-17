# Stage 6: Occupancy detection histories and covariates
# Builds per-species detection history matrices from cleaned detections,
# occasion-level effort, and site-level covariates.

# ---- Pure helpers ----

#' Build site identifiers from the audio master table
#'
#' Grids with a single deployment use the grid name alone (e.g.
#' \code{"G1180"}). Grids with multiple deployments get
#' \code{"G0272_dep3"} to keep them distinct.
#'
#' @param master A \code{data.table} with at least columns \code{grid} and
#'   \code{deployment_id}.
#' @return The input table (modified by reference) with a \code{site_id}
#'   column.
#' @keywords internal
pam_site_id <- function(master) {
  if (!"deployment_id" %in% names(master)) {
    master[, site_id := grid]
    return(invisible(master))
  }
  dep_counts <- unique(master[, .(grid, deployment_id)])[, .N, by = grid]
  multi <- dep_counts[N > 1L, grid]
  master[, site_id := ifelse(
    grid %in% multi,
    paste0(grid, "_", deployment_id),
    as.character(grid)
  )]
  invisible(master)
}


#' Calculate daily recording effort per site
#'
#' Splits recordings that cross midnight into two rows and sums hours
#' per site per calendar day. Days below \code{min_effort_h} are flagged
#' as insufficient.
#'
#' @param master A \code{data.table} with columns \code{site_id},
#'   \code{start_time} (POSIXct), \code{duration_s}, \code{qc_pass},
#'   \code{in_deployment}.
#' @param tz Character. Timezone for calendar dates.
#' @param min_effort_h Numeric. Minimum recording hours for an occasion
#'   to count as surveyed.
#' @return A \code{data.table} with columns \code{site_id},
#'   \code{occasion_date} (Date), \code{effort_hours}, \code{sufficient}.
#' @keywords internal
pam_daily_effort <- function(master, tz = "Asia/Kolkata",
                             min_effort_h = 2) {
  empty <- data.table::data.table(
    site_id = character(),
    occasion_date = as.Date(character()),
    effort_hours = numeric(),
    sufficient = logical()
  )

  dt <- data.table::copy(master)
  dt <- dt[qc_pass == TRUE & in_deployment == TRUE]
  if (nrow(dt) == 0L) return(empty)

  # Ensure POSIXct with the right timezone
  if (is.character(dt$start_time)) {
    dt[, start_time := as.POSIXct(start_time, tz = "UTC")]
  }
  attr(dt$start_time, "tzone") <- tz

  dt[, start_local := start_time]
  dt[, end_local := start_local + duration_s]
  dt[, date1 := as.Date(start_local, tz = tz)]
  dt[, date2 := as.Date(end_local, tz = tz)]

  # --- Same-day recordings (vast majority) ---
  same <- dt[date1 == date2]
  cross <- dt[date1 != date2]
  parts <- vector("list", 3L)

  if (nrow(same) > 0L) {
    parts[[1L]] <- same[, .(site_id,
                            occasion_date = date1,
                            effort_hours = duration_s / 3600)]
  }

  # --- Cross-midnight recordings (rare, <= 60 min) ---
  if (nrow(cross) > 0L) {
    cross[, midnight := as.POSIXct(as.character(date2), tz = tz)]
    cross[, h1 := as.numeric(difftime(midnight, start_local,
                                      units = "hours"))]
    cross[, h2 := as.numeric(difftime(end_local, midnight,
                                      units = "hours"))]
    parts[[2L]] <- cross[, .(site_id,
                             occasion_date = date1,
                             effort_hours = h1)]
    parts[[3L]] <- cross[, .(site_id,
                             occasion_date = date2,
                             effort_hours = h2)]
  }

  effort <- data.table::rbindlist(parts, use.names = TRUE)
  if (nrow(effort) == 0L) return(empty)

  effort <- effort[, .(effort_hours = sum(effort_hours)),
                   by = .(site_id, occasion_date)]
  effort[, sufficient := effort_hours >= min_effort_h]
  effort <- effort[order(site_id, occasion_date)]
  return(effort)
}


#' Build a detection history matrix for one species
#'
#' @param events A \code{data.table} of detections for one species with
#'   columns \code{site_id}, \code{occasion_date}, \code{confidence}.
#' @param effort A \code{data.table} from \code{pam_daily_effort}.
#' @param threshold Numeric. Minimum confidence for a detection to count.
#' @return A wide \code{data.table}: rows = sites, columns = site_id +
#'   one per occasion date. Values: 1, 0, or NA.
#' @keywords internal
pam_detection_matrix <- function(events, effort, threshold = 0.5) {
  all_occ <- data.table::copy(effort)

  det <- events[confidence >= threshold]
  det_so <- det[, .(detected = 1L), by = .(site_id, occasion_date)]

  all_occ <- merge(all_occ, det_so,
                   by = c("site_id", "occasion_date"),
                   all.x = TRUE)
  all_occ[is.na(detected), detected := 0L]
  all_occ[sufficient == FALSE, detected := NA_integer_]

  wide <- data.table::dcast(
    all_occ,
    site_id ~ occasion_date,
    value.var = "detected"
  )

  date_cols <- sort(setdiff(names(wide), "site_id"))
  data.table::setcolorder(wide, c("site_id", date_cols))
  return(wide)
}


#' Build occasion-level covariate table
#'
#' Produces effort (hours) and Julian date (days since the first occasion
#' in the dataset) for each site-occasion.
#'
#' @param effort A \code{data.table} from \code{pam_daily_effort}.
#' @return A \code{data.table} with columns \code{site_id},
#'   \code{occasion_date}, \code{effort_hours}, \code{sufficient},
#'   \code{julian_date}.
#' @keywords internal
pam_occasion_covariates <- function(effort) {
  cov <- data.table::copy(effort)
  if (nrow(cov) == 0L) {
    cov[, julian_date := integer()]
    return(cov)
  }
  min_date <- min(cov$occasion_date)
  cov[, julian_date := as.integer(occasion_date - min_date) + 1L]
  cov <- cov[order(site_id, occasion_date)]
  return(cov)
}


#' Build site-level covariate table
#'
#' Extracts site metadata from the master table and adds total effort.
#' Currently includes grid, deployment dates, coordinates (if present),
#' and total recorded hours.
#'
#' @param master A \code{data.table} with deployment and QC columns.
#' @param effort A \code{data.table} from \code{pam_daily_effort}.
#' @return A \code{data.table} with one row per site.
#' @keywords internal
pam_site_covariates <- function(master, effort) {
  want <- c("site_id", "grid", "deployment_id", "habitat",
            "latitude", "longitude", "deploy_date", "retrieve_date")
  have <- intersect(want, names(master))
  sites <- unique(master[, ..have])

  total_eff <- effort[, .(total_effort_hours = sum(effort_hours),
                          n_occasions_surveyed = sum(sufficient)),
                      by = site_id]
  sites <- merge(sites, total_eff, by = "site_id", all.x = TRUE)
  sites[is.na(total_effort_hours), total_effort_hours := 0]
  sites[is.na(n_occasions_surveyed), n_occasions_surveyed := 0L]
  return(sites)
}


# ---- Main wrapper ----

#' Build occupancy detection histories for all qualifying species
#'
#' Reads cleaned detections and the audio master, constructs per-species
#' detection history matrices (wide format), occasion covariates (effort
#' and Julian date), and site covariates. Writes everything to
#' \code{data/occupancy/<run_id>/}.
#'
#' @param cfg A list from \code{pam_config_read}.
#' @param run_id Character. The detection run to use. Defaults to
#'   \code{cfg$occupancy$run_id}.
#' @param force Logical. Rebuild even if outputs exist? Default FALSE.
#' @return Invisibly, a list with \code{histories} (named list of wide
#'   matrices), \code{effort}, \code{site_covariates}, \code{summary}.
#' @details
#' ## Occasion definition
#' Each occasion is one calendar day (midnight to midnight in the
#' project timezone). Days with less than \code{min_effort_hours} of
#' recording are coded NA (not surveyed).
#'
#' ## Site definition
#' Grids with a single deployment use the grid name as the site ID.
#' Grids with multiple deployments get \code{grid_deployment_id}.
#'
#' ## Confidence thresholds
#' If \code{processing.species_thresholds_file} points to a CSV with
#' columns \code{scientific_name} and \code{threshold}, those per-species
#' values are used. Species not listed fall back to
#' \code{processing.min_confidence}.
#'
#' ## Species filter
#' Only species with at least \code{occupancy.min_detections} total
#' detections (after the confidence cut) get a history matrix.
#'
#' @export
pam_build_occupancy <- function(cfg,
                                run_id = cfg$occupancy$run_id,
                                force = FALSE) {
  stage <- "06_occupancy"
  occ_dir <- file.path(cfg$paths$occupancy, run_id)

  summary_path <- file.path(occ_dir, "occupancy_summary.csv")
  if (!force && file.exists(summary_path)) {
    pam_log("INFO",
            "Occupancy outputs exist; use force = TRUE to rebuild",
            stage = stage, log_dir = cfg$paths$logs)
    return(invisible(NULL))
  }

  pam_log("INFO",
          paste("Building occupancy histories for run:", run_id),
          stage = stage, log_dir = cfg$paths$logs)

  # ---- Read inputs ----
  master_path <- file.path(cfg$paths$metadata, "audio_master.csv")
  if (!file.exists(master_path)) {
    stop("audio_master.csv not found. Run Stage 1 first.", call. = FALSE)
  }
  master <- data.table::fread(master_path)

  # Fix timezone (fwrite writes UTC ISO)
  tz <- if (!is.null(cfg$filenames$timezone) &&
            nzchar(cfg$filenames$timezone)) {
    cfg$filenames$timezone
  } else {
    "Asia/Kolkata"
  }
  if ("start_time" %in% names(master)) {
    if (is.character(master$start_time)) {
      master[, start_time := as.POSIXct(start_time, tz = "UTC")]
    }
    attr(master$start_time, "tzone") <- tz
  }

  det_path <- file.path(cfg$paths$detections,
                        run_id, "processed", "detections_clean.csv")
  if (!file.exists(det_path)) {
    stop("detections_clean.csv not found for run '", run_id,
         "'. Run Stage 4 first.", call. = FALSE)
  }
  det <- data.table::fread(det_path)

  # ---- Config parameters ----
  min_effort_h <- if (!is.null(cfg$occupancy$min_effort_hours)) {
    cfg$occupancy$min_effort_hours
  } else {
    2
  }
  min_det <- if (!is.null(cfg$occupancy$min_detections)) {
    cfg$occupancy$min_detections
  } else {
    10
  }
  global_thresh <- if (!is.null(cfg$processing$min_confidence)) {
    cfg$processing$min_confidence
  } else {
    0.5
  }

  # ---- Per-species thresholds ----
  all_species <- unique(det$species)
  thresholds <- stats::setNames(
    rep(global_thresh, length(all_species)),
    all_species
  )

  thresh_file <- cfg$processing$species_thresholds_file
  if (!is.null(thresh_file) && nzchar(thresh_file) &&
      thresh_file != "null") {
    thresh_path <- if (fs::is_absolute_path(thresh_file)) {
      thresh_file
    } else {
      file.path(cfg$paths$project_root, thresh_file)
    }
    if (file.exists(thresh_path)) {
      sp_thresh <- data.table::fread(thresh_path)
      for (i in seq_len(nrow(sp_thresh))) {
        sp <- sp_thresh$scientific_name[i]
        if (sp %in% names(thresholds)) {
          thresholds[sp] <- sp_thresh$threshold[i]
        }
      }
      pam_log("INFO",
              paste("Loaded per-species thresholds from", thresh_path),
              stage = stage, log_dir = cfg$paths$logs)
    } else {
      pam_log("WARN",
              paste("Thresholds file not found:", thresh_path,
                    "; using global threshold", global_thresh),
              stage = stage, log_dir = cfg$paths$logs)
    }
  }

  # ---- Filter master to valid, in-deployment recordings ----
  master <- master[qc_pass == TRUE & in_deployment == TRUE]

  # ---- Build site IDs ----
  pam_site_id(master)

  # Join site_id to detections
  # master uses "file_name", detections use "filename"
  det_key <- intersect(c("filename", "file_name", "file_path"),
                       names(det))
  master_key <- intersect(c("file_name", "filename", "file_path"),
                          names(master))
  if (length(det_key) == 0L || length(master_key) == 0L) {
    stop("Cannot join detections to master: ",
         "no common file identifier column.", call. = FALSE)
  }
  # Use the first available key from each side
  dk <- det_key[1L]
  mk <- master_key[1L]
  if (dk == mk) {
    det <- merge(det,
                 unique(master[, c(mk, "site_id"), with = FALSE]),
                 by = dk, all.x = TRUE)
  } else {
    master_lookup <- unique(master[, c(mk, "site_id"), with = FALSE])
    data.table::setnames(master_lookup, mk, dk)
    det <- merge(det, master_lookup, by = dk, all.x = TRUE)
  }

  # Extract occasion date from detection timestamps
  if ("detection_datetime" %in% names(det)) {
    det[, occasion_date := as.Date(substr(detection_datetime, 1, 10))]
  } else if ("recording_start" %in% names(det)) {
    det[, occasion_date := as.Date(substr(recording_start, 1, 10))]
  } else {
    stop("Detections need 'detection_datetime' or 'recording_start'.",
         call. = FALSE)
  }

  # ---- Calculate effort ----
  effort <- pam_daily_effort(master, tz = tz,
                             min_effort_h = min_effort_h)
  pam_log("INFO",
          sprintf("Effort: %d site-occasions, %d sufficient (>= %g h)",
                  nrow(effort), sum(effort$sufficient), min_effort_h),
          stage = stage, log_dir = cfg$paths$logs)

  # ---- Filter species ----
  sp_counts <- det[, .N, by = species]
  qualifying <- sp_counts[N >= min_det, species]
  pam_log("INFO",
          sprintf("%d species with >= %d detections: %s",
                  length(qualifying), min_det,
                  paste(qualifying, collapse = ", ")),
          stage = stage, log_dir = cfg$paths$logs)

  if (length(qualifying) == 0L) {
    pam_log("WARN",
            "No species qualify. Lower min_detections or check data.",
            stage = stage, log_dir = cfg$paths$logs)
    return(invisible(NULL))
  }

  # ---- Build histories ----
  histories <- list()
  summary_rows <- vector("list", length(qualifying))

  for (idx in seq_along(qualifying)) {
    sp <- qualifying[idx]
    sp_events <- det[species == sp]
    thresh <- thresholds[sp]

    wide <- pam_detection_matrix(sp_events, effort,
                                 threshold = thresh)
    histories[[sp]] <- wide

    n_sites <- nrow(wide)
    n_occ <- ncol(wide) - 1L
    det_cols <- setdiff(names(wide), "site_id")
    n_det_sites <- sum(
      rowSums(wide[, ..det_cols], na.rm = TRUE) > 0
    )
    naive_occ <- if (n_sites > 0L) n_det_sites / n_sites else 0

    summary_rows[[idx]] <- data.table::data.table(
      species = sp,
      threshold_used = thresh,
      n_sites = n_sites,
      n_occasions = n_occ,
      n_sites_detected = n_det_sites,
      naive_occupancy = round(naive_occ, 3)
    )

    pam_log("INFO",
            sprintf("  %s: %d sites, %d occasions, naive psi = %.2f",
                    sp, n_sites, n_occ, naive_occ),
            stage = stage, log_dir = cfg$paths$logs)
  }

  # ---- Build covariates ----
  occ_cov <- pam_occasion_covariates(effort)
  site_cov <- pam_site_covariates(master, effort)
  summary_dt <- data.table::rbindlist(summary_rows)

  # ---- Write outputs ----
  if (!dir.exists(occ_dir)) dir.create(occ_dir, recursive = TRUE)

  for (sp in qualifying) {
    sp_safe <- gsub(" ", "_", sp)
    data.table::fwrite(
      histories[[sp]],
      file.path(occ_dir,
                paste0("detection_history_", sp_safe, ".csv"))
    )
  }

  data.table::fwrite(occ_cov,
                     file.path(occ_dir, "occasion_covariates.csv"))
  data.table::fwrite(site_cov,
                     file.path(occ_dir, "site_covariates.csv"))
  data.table::fwrite(summary_dt,
                     file.path(occ_dir, "occupancy_summary.csv"))

  pam_log("INFO",
          paste("Occupancy outputs written to", occ_dir),
          stage = stage, log_dir = cfg$paths$logs)

  invisible(list(
    histories = histories,
    effort = occ_cov,
    site_covariates = site_cov,
    summary = summary_dt
  ))
}
