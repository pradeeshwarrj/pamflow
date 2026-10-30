#' Parse grid and start time from recording filenames
#'
#' @param files Character vector of file paths.
#' @param pattern PCRE regex with named groups `grid`, `date` (YYYYMMDD) and
#'   `time` (HHMMSS), applied to the file name only.
#' @param timezone Olson timezone of the filename timestamps (local time).
#' @return A data.table with `file_path`, `file_name`, `grid`, `start_time`
#'   (POSIXct) and `valid_name`. Files that don't match get NA and
#'   `valid_name = FALSE`; they are never dropped.
#' @examples
#' ex <- pam_example_project()
#' # the second name does not match the pattern, so it is flagged, not dropped
#' pam_parse_filenames(c(ex$files[1], "not_a_recording.wav"),
#'                     pattern = ex$cfg$filenames$pattern,
#'                     timezone = "Asia/Kolkata")
#' @export
pam_parse_filenames <- function(files, pattern, timezone) {
  file_name <- basename(files)
  m <- regexpr(pattern, file_name, perl = TRUE)
  starts <- attr(m, "capture.start")
  lens <- attr(m, "capture.length")
  needed <- c("grid", "date", "time")
  if (is.null(starts) || !all(needed %in% colnames(starts))) {
    rlang::abort("filenames$pattern must contain named groups: grid, date, time")
  }
  grab <- function(nm) {
    out <- substring(file_name, starts[, nm], starts[, nm] + lens[, nm] - 1L)
    out[m == -1L] <- NA_character_
    out
  }
  dt <- data.table::data.table(
    file_path = files, file_name = file_name,
    grid = grab("grid"), date_str = grab("date"), time_str = grab("time")
  )
  dt[, start_time := as.POSIXct(paste(date_str, time_str),
                                format = "%Y%m%d %H%M%S", tz = timezone)]
  dt[, valid_name := !is.na(grid) & !is.na(start_time)]
  dt[, c("date_str", "time_str") := NULL]
  dt[]
}

#' Read and clean the deployment sheet
#'
#' @param cfg A `pam_config` object. Uses `paths$deployment_sheet`, the
#'   `deployments` settings and `filenames$timezone`.
#' @return A data.table with the configured columns plus `deploy_start`,
#'   `retrieve_end` (POSIXct, local time) and `recovery_time_missing`. `grid`
#'   is converted to the filename format (0059 -> "G0059").
#' @details Columns are matched by position (`deployments$columns`); everything
#'   is read as text so leading zeros survive. Repairs applied (and nothing
#'   else): "/" and "." date separators become "-", "." in times becomes ":",
#'   seconds are dropped, a blank recovery time becomes
#'   `deployments$default_recovery_time`, and a recovery year before 2000
#'   (e.g. 15-04-0206) is replaced by the deployment year. Rows that still
#'   can't be parsed get NA and are listed by `pam_check_deployments()`.
#' @examples
#' ex <- pam_example_project()
#' dep <- pam_read_deployments(ex$cfg)
#' as.data.frame(dep)[, c("deployment_id", "grid", "deploy_start", "retrieve_end")]
#' @export
pam_read_deployments <- function(cfg) {
  path <- cfg$paths$deployment_sheet
  if (!file.exists(path)) rlang::abort(sprintf("Deployment sheet not found: %s", path))
  d <- cfg$deployments
  cols <- unlist(d$columns)

  dep <- data.table::fread(path, header = FALSE, colClasses = "character",
                           na.strings = c("", "NA"), strip.white = TRUE, fill = TRUE,
                           skip = if (isTRUE(d$has_header)) 1L else 0L)
  if (ncol(dep) < length(cols)) {
    rlang::abort(sprintf("Deployment sheet has %d columns; config expects %d",
                         ncol(dep), length(cols)))
  }
  dep <- dep[, seq_along(cols), with = FALSE]
  data.table::setnames(dep, cols)

  tz <- cfg$filenames$timezone
  clean_date <- function(x) gsub("[./]", "-", trimws(x))
  clean_time <- function(x) {
    x <- gsub("\\.", ":", trimws(x))
    sub("^(\\d{1,2}:\\d{2}):\\d{2}$", "\\1", x)
  }

  dep[, grid := paste0(d$grid_prefix, sprintf("%04d", suppressWarnings(as.integer(grid))))]
  dep[, deploy_day := as.Date(clean_date(deploy_date), format = d$date_format)]
  dep[, retrieve_day := as.Date(clean_date(retrieve_date), format = d$date_format)]

  # repair implausible recovery years (e.g. 0206) using the deployment year
  bad_year <- dep[, !is.na(retrieve_day) & !is.na(deploy_day) &
                    as.integer(format(retrieve_day, "%Y")) < 2000L]
  if (any(bad_year)) {
    fixed <- as.Date(paste0(format(dep$retrieve_day[bad_year], "%d-%m-"),
                            format(dep$deploy_day[bad_year], "%Y")), format = "%d-%m-%Y")
    warning("Recovery year repaired using deployment year for rows: ",
            paste(dep$deployment_id[bad_year], collapse = ", "))
    dep[bad_year, retrieve_day := fixed]
  }

  dep[, recovery_time_missing := is.na(retrieve_time) & !is.na(retrieve_day)]
  dep[recovery_time_missing == TRUE, retrieve_time := d$default_recovery_time]

  fmt <- paste("%Y-%m-%d", d$time_format)
  dep[, deploy_start := as.POSIXct(paste(format(deploy_day, "%Y-%m-%d"), clean_time(deploy_time)),
                                   format = fmt, tz = tz)]
  dep[, retrieve_end := as.POSIXct(paste(format(retrieve_day, "%Y-%m-%d"), clean_time(retrieve_time)),
                                   format = fmt, tz = tz)]
  dep[, c("latitude", "longitude") := lapply(.SD, as.numeric),
      .SDcols = c("latitude", "longitude")]
  dep[, c("deploy_day", "retrieve_day") := NULL]
  dep[]
}

#' List problems in the deployment table
#'
#' @param dep Table from `pam_read_deployments()`.
#' @return A data.table `deployment_id`, `grid`, `issue` (empty if none).
#'   Issues: unparseable start, missing/unparseable recovery, recovery before
#'   deployment, assumed recovery time, and overlap with another deployment of
#'   the same grid.
#' @examples
#' ex <- pam_example_project()
#' dep <- pam_read_deployments(ex$cfg)
#' pam_check_deployments(dep)   # no rows: the example deployments are consistent
#' @export
pam_check_deployments <- function(dep) {
  d <- data.table::copy(dep)
  data.table::setorder(d, grid, deploy_start)
  d[, overlaps_prev := !is.na(deploy_start) &
      deploy_start < data.table::shift(retrieve_end), by = grid]
  flag <- function(rows, text) rows[, .(deployment_id, grid, issue = text)]
  data.table::rbindlist(list(
    flag(d[is.na(deploy_start)], "deployment start missing or unparseable"),
    flag(d[is.na(retrieve_end)], "recovery date missing or unparseable (never matched to audio)"),
    flag(d[retrieve_end < deploy_start], "recovery before deployment"),
    flag(d[recovery_time_missing == TRUE], "recovery time blank; end of day assumed"),
    flag(d[overlaps_prev == TRUE], "overlaps another deployment of the same grid")
  ))
}

#' Add QC flags to a master audio table
#'
#' @param master data.table from `pam_parse_filenames()` joined with
#'   `pam_audio_info()`.
#' @param cfg A `pam_config` object (uses `qc$gap_tolerance_s` and
#'   `audio$min_duration_s`).
#' @return `master` with `end_time`, `truncated`, `short`, `duplicate`,
#'   `gap_s`, `gap_before`, `overlap_before` and `qc_pass`. Sorted by grid and
#'   start time.
#' @details Gaps are measured between the end of one file and the start of the
#'   next within a grid. `qc_pass` requires a valid name, a readable and
#'   untruncated file, and no duplicate; `short` files and gaps are reported but
#'   do not fail QC. Truncation checks apply to PCM WAV files (where bit depth
#'   is non-NA).
#' @examples
#' ex <- pam_example_project()
#' cfg <- ex$cfg
#' master <- pam_parse_filenames(ex$files, cfg$filenames$pattern, cfg$filenames$timezone)
#' master <- merge(master, pam_audio_info(ex$files), by = "file_path")
#' master <- pam_add_qc(master, cfg)
#' as.data.frame(master)[, c("file_name", "gap_s", "qc_pass")]
#' @export
pam_add_qc <- function(master, cfg) {
  tol <- cfg$qc$gap_tolerance_s
  master[, end_time := start_time + duration_s]

  master[, expected_bytes := fifelse(
    is.na(bits),
    NA_real_,
    44 + duration_s * sample_rate * channels * bits / 8
  )]
  master[, truncated := readable & !is.na(expected_bytes) &
           file_size_b < 0.99 * expected_bytes]

  master[, modal_duration_s := if (all(is.na(duration_s))) NA_real_ else {
    tab <- table(round(duration_s))
    as.numeric(names(tab)[which.max(tab)])
  }, by = grid]
  master[, short := readable & duration_s < 0.99 * modal_duration_s]
  master[, dup_n := .N, by = .(grid, start_time)]
  master[, duplicate := valid_name & dup_n > 1L]

  data.table::setorder(master, grid, start_time)
  master[valid_name == TRUE,
         gap_s := as.numeric(difftime(start_time, data.table::shift(end_time),
                                      units = "secs")),
         by = grid]
  master[, gap_before := !is.na(gap_s) & gap_s > tol]
  master[, overlap_before := !is.na(gap_s) & gap_s < -tol]
  master[, qc_pass := valid_name & readable & !truncated & !duplicate]
  master[, c("expected_bytes", "dup_n") := NULL]
  master[]
}

#' Attach recorder and coordinates by matching grid and time window
#'
#' @param master Master audio table with `file_path`, `grid`, `start_time`.
#' @param dep Table from `pam_read_deployments()`.
#' @return `master` with `deployment_id`, `recorder`, `latitude`, `longitude`
#'   and `in_deployment`. Recordings outside every deployment window of their
#'   grid get NA and `in_deployment = FALSE` (not dropped).
#' @examples
#' ex <- pam_example_project()
#' cfg <- ex$cfg
#' master <- pam_parse_filenames(ex$files, cfg$filenames$pattern, cfg$filenames$timezone)
#' master <- pam_match_deployments(master, pam_read_deployments(cfg))
#' as.data.frame(master)[, c("file_name", "deployment_id", "recorder", "in_deployment")]
#' @export
pam_match_deployments <- function(master, dep) {
  key <- master[, .(file_path, grid, start_time)]
  matched <- dep[key,
                 on = .(grid, deploy_start <= start_time, retrieve_end >= start_time),
                 mult = "first",
                 .(file_path = i.file_path, deployment_id = x.deployment_id,
                   recorder = x.recorder, latitude = x.latitude, longitude = x.longitude)]
  master <- merge(master, matched, by = "file_path", all.x = TRUE, sort = FALSE)
  master[, in_deployment := !is.na(deployment_id)]
  master[]
}

#' Summarise the audio master table
#'
#' @param master Output of `pam_scan_audio()$master`.
#' @param dep Optional deployment table, to report grids/deployments with no
#'   match.
#' @return A list: `overall` (one-row data.table), `per_grid` (data.table),
#'   `grids_without_deployment`, `deployments_without_audio`.
#' @examples
#' ex <- pam_example_project()
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' summ <- pam_audio_summary(res$master, res$deployments)
#' summ$overall
#' summ$per_grid
#' @export
pam_audio_summary <- function(master, dep = NULL) {
  overall <- master[, .(
    n_files = .N, n_grids = uniqueN(grid), total_hours = sum(duration_s, na.rm = TRUE) / 3600,
    n_invalid_name = sum(!valid_name), n_unreadable = sum(!readable),
    n_truncated = sum(truncated, na.rm = TRUE), n_short = sum(short, na.rm = TRUE),
    n_duplicate = sum(duplicate), n_gaps = sum(gap_before, na.rm = TRUE),
    n_outside_deployment = sum(!in_deployment), n_qc_pass = sum(qc_pass)
  )]
  per_grid <- master[, .(
    n_files = .N, hours = sum(duration_s, na.rm = TRUE) / 3600,
    median_file_min = stats::median(duration_s, na.rm = TRUE) / 60,
    first = suppressWarnings(min(start_time, na.rm = TRUE)),
    last = suppressWarnings(max(start_time, na.rm = TRUE)),
    n_gaps = sum(gap_before, na.rm = TRUE), n_duplicate = sum(duplicate),
    n_unreadable = sum(!readable), n_outside_deployment = sum(!in_deployment)
  ), by = grid]
  list(
    overall = overall, per_grid = per_grid,
    grids_without_deployment = if (is.null(dep)) NULL else setdiff(unique(master$grid), dep$grid),
    deployments_without_audio = if (is.null(dep)) NULL else
      dep[!deployment_id %in% master$deployment_id, .(deployment_id, recorder, grid)]
  )
}

#' Stage 1: scan standardized audio and build the master metadata table
#'
#' Lists WAV/FLAC files, parses filenames, reads headers (cached, so re-runs
#' only read new files and an interrupted run resumes), joins deployments, adds
#' QC flags, and writes the master table and summaries.
#'
#' @param cfg A `pam_config` object.
#' @param force If TRUE, discard the header cache and re-read every file.
#' @return A list: `master`, `deployments`, `summary`.
#' @details Writes `metadata/audio_headers.csv` (cache), `metadata/audio_master.csv`,
#'   `outputs/audio_summary_per_grid.csv` and `outputs/deployment_issues.csv`.
#'   Times in CSV files are written as UTC (ISO 8601) by `data.table::fwrite`.
#'   Run with `pam_run_stage("01_scan", pam_scan_audio, cfg)` for logging.
#'
#'   Audio discovery uses [pam_list_audio()] (WAV + FLAC). Header reading uses
#'   [pam_audio_info()].
#' @examples
#' ex <- pam_example_project()
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' res$summary$overall
#' # the master table and summaries are also written to the project
#' list.files(ex$cfg$paths$metadata)
#' @export
pam_scan_audio <- function(cfg, force = FALSE) {
  stage <- "01_scan"; log_dir <- cfg$paths$logs
  dir.create(cfg$paths$metadata, recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$paths$outputs, recursive = TRUE, showWarnings = FALSE)

  audio_dir <- cfg$paths$audio_standardized
  if (!dir.exists(audio_dir)) {
    rlang::abort(sprintf("Audio folder not found: %s", audio_dir))
  }
  files <- pam_list_audio(audio_dir)
  if (!length(files)) {
    rlang::abort("No .wav/.flac files found in the audio folder")
  }
  pam_log("INFO", sprintf("found %d audio files (wav/flac)", length(files)), stage, log_dir)

  # header cache doubles as the resume checkpoint
  hdr_path <- file.path(cfg$paths$metadata, "audio_headers.csv")
  if (force && file.exists(hdr_path)) unlink(hdr_path)
  cached <- if (file.exists(hdr_path)) data.table::fread(hdr_path)$file_path else character()
  todo <- setdiff(files, cached)
  if (length(todo)) {
    chunks <- split(todo, ceiling(seq_along(todo) / cfg$qc$header_chunk_size))
    for (chunk in chunks) {
      data.table::fwrite(pam_audio_info(chunk), hdr_path, append = file.exists(hdr_path))
    }
  }
  pam_log("INFO", sprintf("read headers for %d new files", length(todo)), stage, log_dir)
  headers <- unique(data.table::fread(hdr_path), by = "file_path")[file_path %in% files]

  master <- pam_parse_filenames(files, cfg$filenames$pattern, cfg$filenames$timezone)
  master <- merge(master, headers, by = "file_path", all.x = TRUE, sort = FALSE)
  master <- pam_add_qc(master, cfg)

  dep <- pam_read_deployments(cfg)
  dep_issues <- pam_check_deployments(dep)
  data.table::fwrite(dep_issues, file.path(cfg$paths$outputs, "deployment_issues.csv"))
  if (nrow(dep_issues)) {
    pam_log("WARN", sprintf("%d deployment issues, see outputs/deployment_issues.csv",
                            nrow(dep_issues)), stage, log_dir)
  }
  master <- pam_match_deployments(master, dep)

  summ <- pam_audio_summary(master, dep)
  data.table::fwrite(master, file.path(cfg$paths$metadata, "audio_master.csv"))
  data.table::fwrite(summ$per_grid, file.path(cfg$paths$outputs, "audio_summary_per_grid.csv"))

  o <- summ$overall
  pam_log("INFO", sprintf(
    "%d files, %d grids, %.1f h | invalid names %d, unreadable %d, truncated %d, duplicates %d, gaps %d, outside deployment %d",
    o$n_files, o$n_grids, o$total_hours, o$n_invalid_name, o$n_unreadable,
    o$n_truncated, o$n_duplicate, o$n_gaps, o$n_outside_deployment), stage, log_dir)

  list(master = master, deployments = dep, summary = summ)
}
