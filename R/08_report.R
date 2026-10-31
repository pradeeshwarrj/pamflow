# Stage 8: Reports (HTML, PDF, Excel)
# Gathers outputs from all stages and renders summary reports.

#' Gather report data from all completed stages
#'
#' Reads outputs from Stages 1, 4, 5, 5b and 6 and returns a single
#' list suitable for passing to the report template or Excel writer.
#' Missing stages are returned as NULL with a warning.
#'
#' @param cfg A list from \code{pam_config_read}.
#' @param run_id Character. The detection run to report on.
#' @return A named list with elements \code{effort}, \code{detections},
#'   \code{species_counts}, \code{hourly_pattern}, \code{precision},
#'   \code{recall}, \code{occupancy}, and the ecological products
#'   \code{activity_hour}, \code{activity_week}, \code{richness_sites},
#'   \code{richness_estimates}, \code{richness_accumulation} and
#'   \code{thresholds} (see \code{pam_report_ecology}).
#' @keywords internal
pam_report_data <- function(cfg, run_id) {
  out <- list(
    effort = NULL,
    detections = NULL,
    species_counts = NULL,
    hourly_pattern = NULL,
    precision = NULL,
    recall = NULL,
    occupancy = NULL,
    activity_hour = NULL,
    activity_week = NULL,
    richness_sites = NULL,
    richness_estimates = NULL,
    richness_accumulation = NULL,
    thresholds = NULL
  )

  # ---- Effort (Stage 1) ----
  master_path <- file.path(cfg$paths$metadata, "audio_master.csv")
  if (file.exists(master_path)) {
    master <- data.table::fread(master_path)
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
    if ("grid" %in% names(master)) {
      pam_site_id(master)
    }
    min_effort_h <- if (!is.null(cfg$occupancy$min_effort_hours)) {
      cfg$occupancy$min_effort_hours
    } else {
      2
    }
    out$effort <- pam_daily_effort(master, tz = tz,
                                   min_effort_h = min_effort_h)
  } else {
    pam_log("WARN", "audio_master.csv not found; skipping effort",
            stage = "08_report", log_dir = cfg$paths$logs)
  }

  # ---- Detections (Stage 4) ----
  det_path <- file.path(cfg$paths$detections, run_id,
                        "processed", "detections_clean.csv")
  if (file.exists(det_path)) {
    det <- data.table::fread(det_path)
    out$detections <- det

    out$species_counts <- det[, .(
      events = .N,
      sites = data.table::uniqueN(grid)
    ), by = species][order(-events)]

    if ("detection_datetime" %in% names(det)) {
      det[, hour := as.integer(
        substr(as.character(detection_datetime), 12, 13)
      )]
      out$hourly_pattern <- det[, .(n = .N), by = hour][order(hour)]
    }
  } else {
    pam_log("WARN",
            paste("detections_clean.csv not found for run", run_id),
            stage = "08_report", log_dir = cfg$paths$logs)
  }

  # ---- Validation precision (Stage 5) ----
  prec_path <- file.path(cfg$paths$detections, run_id,
                         "validation", "precision_by_cell.csv")
  if (file.exists(prec_path)) {
    out$precision <- data.table::fread(prec_path)
  }

  # ---- Validation recall (Stage 5b) ----
  recall_path <- file.path(cfg$paths$detections, run_id,
                           "validation",
                           "recall_by_species_threshold.csv")
  if (file.exists(recall_path)) {
    out$recall <- data.table::fread(recall_path)
  }

  # ---- Occupancy (Stage 6) ----
  occ_path <- file.path(cfg$paths$occupancy, run_id,
                        "occupancy_summary.csv")
  if (file.exists(occ_path)) {
    out$occupancy <- data.table::fread(occ_path)
  }

  # ---- Activity, richness and thresholds ----
  ecology <- pam_report_ecology(cfg, run_id, out)
  out[names(ecology)] <- ecology

  return(out)
}


#' Activity, richness and threshold tables for the report
#'
#' Computes the tables of the ecological products from the cleaned detections
#' and the recording effort. Anything that cannot be computed (for example when
#' a stage has not been run) is left \code{NULL} and noted in the log; it never
#' stops the report.
#'
#' @param cfg A list from \code{pam_config_read}.
#' @param run_id Character. The detection run.
#' @param data The list built so far by \code{pam_report_data}.
#' @return A named list: \code{activity_hour} and \code{activity_week}
#'   (detections per recorded hour by hour of day and by week),
#'   \code{richness_sites}, \code{richness_estimates},
#'   \code{richness_accumulation} (see \code{pam_richness}) and
#'   \code{thresholds} (the species thresholds saved by
#'   \code{pam_species_thresholds}, when present).
#' @keywords internal
pam_report_ecology <- function(cfg, run_id, data) {
  out <- list(activity_hour = NULL, activity_week = NULL, richness_sites = NULL,
              richness_estimates = NULL, richness_accumulation = NULL, thresholds = NULL)
  skipped <- function(what, e) {
    pam_log("INFO", sprintf("%s not added to the report: %s", what, conditionMessage(e)),
            stage = "08_report", log_dir = cfg$paths$logs)
  }
  usable <- function(x) !is.null(x) && nrow(x) > 0L
  activity_columns <- c("period", "species", "scientific_name", "n_detections",
                        "effort_hours", "detections_per_hour", "relative_activity")

  if (usable(data$detections) && usable(data$effort)) {
    tryCatch({
      activity <- suppressMessages(pam_activity(cfg, run_id, by = "hour"))
      out$activity_hour <- activity[, activity_columns, with = FALSE]
    }, error = function(e) skipped("Hourly activity", e))
    tryCatch({
      activity <- suppressMessages(pam_activity(cfg, run_id, by = "week"))
      out$activity_week <- activity[, activity_columns, with = FALSE]
    }, error = function(e) skipped("Weekly activity", e))
    tryCatch({
      richness <- suppressWarnings(suppressMessages(pam_richness(cfg, run_id)))
      if (nrow(richness$sites) > 0L) {
        out$richness_sites <- richness$sites
        out$richness_estimates <- richness$estimates
        out$richness_accumulation <- richness$accumulation
      }
    }, error = function(e) skipped("Richness", e))
  }

  thresholds_path <- file.path(cfg$paths$detections, run_id, "validation", "species_thresholds.csv")
  if (file.exists(thresholds_path)) {
    out$thresholds <- tryCatch(data.table::fread(thresholds_path), error = function(e) NULL)
  }
  out
}


#' Write summary tables to an Excel workbook
#'
#' Creates one sheet per report section with the key summary tables.
#'
#' @param data A list from \code{pam_report_data}.
#' @param output_path Character. Path for the \code{.xlsx} file.
#' @return Invisibly, the output path.
#' @keywords internal
pam_report_excel <- function(data, output_path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Package 'openxlsx' is needed for Excel output. ",
         "Install with install.packages('openxlsx').", call. = FALSE)
  }

  wb <- openxlsx::createWorkbook()

  if (!is.null(data$effort) && nrow(data$effort) > 0) {
    openxlsx::addWorksheet(wb, "Effort")
    openxlsx::writeData(wb, "Effort", data$effort)
  }

  if (!is.null(data$species_counts) &&
      nrow(data$species_counts) > 0) {
    openxlsx::addWorksheet(wb, "Detections")
    openxlsx::writeData(wb, "Detections", data$species_counts)
  }

  if (!is.null(data$hourly_pattern) &&
      nrow(data$hourly_pattern) > 0) {
    openxlsx::addWorksheet(wb, "Hourly_Pattern")
    openxlsx::writeData(wb, "Hourly_Pattern", data$hourly_pattern)
  }

  if (!is.null(data$precision) && nrow(data$precision) > 0) {
    openxlsx::addWorksheet(wb, "Precision")
    openxlsx::writeData(wb, "Precision", data$precision)
  }

  if (!is.null(data$recall) && nrow(data$recall) > 0) {
    openxlsx::addWorksheet(wb, "Recall")
    openxlsx::writeData(wb, "Recall", data$recall)
  }

  if (!is.null(data$occupancy) && nrow(data$occupancy) > 0) {
    openxlsx::addWorksheet(wb, "Occupancy")
    openxlsx::writeData(wb, "Occupancy", data$occupancy)
  }

  ecological_sheets <- list(
    Richness_Sites = data$richness_sites,
    Richness_Estimates = data$richness_estimates,
    Species_Accumulation = data$richness_accumulation,
    Activity_Hour = data$activity_hour,
    Activity_Week = data$activity_week,
    Species_Thresholds = data$thresholds
  )
  for (sheet in names(ecological_sheets)) {
    table <- ecological_sheets[[sheet]]
    if (!is.null(table) && nrow(table) > 0) {
      openxlsx::addWorksheet(wb, sheet)
      openxlsx::writeData(wb, sheet, table)
    }
  }

  openxlsx::saveWorkbook(wb, output_path, overwrite = TRUE)
  invisible(output_path)
}


#' Generate PAM workflow reports
#'
#' Gathers outputs from all completed stages and renders summary
#' reports in HTML, PDF and/or Excel format.
#'
#' @param cfg A list from \code{pam_config_read}.
#' @param run_id Character. The detection run to report on. Defaults to
#'   \code{cfg$birdnet$run_id}.
#' @param formats Character vector. One or more of \code{"html"},
#'   \code{"pdf"}, \code{"excel"}. Defaults to
#'   \code{cfg$report$formats}.
#' @param output_dir Character. Directory for the output files.
#'   Defaults to \code{cfg$paths$reports}.
#' @param force Logical. Overwrite existing reports? Default FALSE.
#' @return Invisibly, a character vector of generated file paths.
#' @details
#' HTML and PDF are rendered from an R Markdown template using
#' \code{rmarkdown::render}. PDF requires a LaTeX installation
#' (e.g. \code{tinytex::install_tinytex()}). If PDF rendering fails,
#' a warning is issued and the other formats are still produced.
#'
#' Excel output is a multi-sheet workbook with one sheet per report
#' section, created with \code{openxlsx}.
#'
#' Besides recording effort, detections, validation and occupancy, the report
#' includes species richness and diversity per site (with the species
#' accumulation curve and the Chao2 estimate), activity patterns (detections
#' per recorded hour by hour of the day and by week) and the per-species
#' thresholds saved by \code{pam_species_thresholds()}. A section is left out
#' when its inputs are not available.
#'
#' @examples
#' \donttest{
#' if (requireNamespace("rmarkdown", quietly = TRUE) && rmarkdown::pandoc_available()) {
#'   ex <- pam_example_project()
#'   res <- suppressMessages(pam_scan_audio(ex$cfg))
#'   proc <- suppressMessages(pam_process_detections(ex$cfg))
#'   occ <- suppressMessages(pam_build_occupancy(ex$cfg))
#'   files <- suppressMessages(pam_report(ex$cfg, formats = "html"))
#'   basename(files)
#' }
#' }
#' @export
pam_report <- function(cfg,
                       run_id = cfg$birdnet$run_id,
                       formats = cfg$report$formats,
                       output_dir = cfg$paths$reports,
                       force = FALSE) {
  stage <- "08_report"

  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop("Package 'rmarkdown' is needed. ",
         "Install with install.packages('rmarkdown').", call. = FALSE)
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  pam_log("INFO",
          paste("Generating reports for run:", run_id),
          stage = stage, log_dir = cfg$paths$logs)

  # ---- Gather data ----
  data <- pam_report_data(cfg, run_id)

  # ---- Report parameters ----
  title <- if (!is.null(cfg$report$title) &&
               nzchar(cfg$report$title)) {
    cfg$report$title
  } else {
    "PAM Workflow Report"
  }
  author <- if (!is.null(cfg$report$author)) {
    cfg$report$author
  } else {
    ""
  }

  rmd_params <- list(
    run_id = run_id,
    title = title,
    author = author,
    effort = data$effort,
    detections = data$detections,
    species_counts = data$species_counts,
    hourly_pattern = data$hourly_pattern,
    precision = data$precision,
    recall = data$recall,
    occupancy = data$occupancy,
    activity_hour = data$activity_hour,
    activity_week = data$activity_week,
    richness_sites = data$richness_sites,
    richness_estimates = data$richness_estimates,
    richness_accumulation = data$richness_accumulation,
    thresholds = data$thresholds
  )

  generated <- character()

  # ---- Find template ----
  template <- system.file("rmd", "pam_report.Rmd", package = "pamflow")
  if (!nzchar(template)) {
    stop("Report template not found. Is the package installed?",
         call. = FALSE)
  }

  # ---- HTML ----
  if ("html" %in% formats) {
    html_out <- file.path(output_dir,
                          paste0("report_", run_id, ".html"))
    if (!force && file.exists(html_out)) {
      pam_log("INFO", "HTML report exists; skipping (use force=TRUE)",
              stage = stage, log_dir = cfg$paths$logs)
    } else {
      pam_log("INFO", "Rendering HTML report...",
              stage = stage, log_dir = cfg$paths$logs)
      tryCatch({
        rmarkdown::render(
          input = template,
          output_format = "html_document",
          output_file = basename(html_out),
          output_dir = output_dir,
          params = rmd_params,
          quiet = TRUE
        )
        generated <- c(generated, html_out)
        pam_log("INFO", paste("HTML:", html_out),
                stage = stage, log_dir = cfg$paths$logs)
      }, error = function(e) {
        pam_log("WARN",
                paste("HTML rendering failed:", conditionMessage(e)),
                stage = stage, log_dir = cfg$paths$logs)
      })
    }
  }

  # ---- PDF ----
  if ("pdf" %in% formats) {
    pdf_out <- file.path(output_dir,
                         paste0("report_", run_id, ".pdf"))
    if (!force && file.exists(pdf_out)) {
      pam_log("INFO", "PDF report exists; skipping (use force=TRUE)",
              stage = stage, log_dir = cfg$paths$logs)
    } else {
      pam_log("INFO", "Rendering PDF report...",
              stage = stage, log_dir = cfg$paths$logs)
      tryCatch({
        rmarkdown::render(
          input = template,
          output_format = "pdf_document",
          output_file = basename(pdf_out),
          output_dir = output_dir,
          params = rmd_params,
          quiet = TRUE
        )
        generated <- c(generated, pdf_out)
        pam_log("INFO", paste("PDF:", pdf_out),
                stage = stage, log_dir = cfg$paths$logs)
      }, error = function(e) {
        pam_log("WARN",
                paste("PDF rendering failed:", conditionMessage(e),
                      "\nInstall LaTeX with: tinytex::install_tinytex()"),
                stage = stage, log_dir = cfg$paths$logs)
      })
    }
  }

  # ---- Excel ----
  if ("excel" %in% formats) {
    xlsx_out <- file.path(output_dir,
                          paste0("report_", run_id, ".xlsx"))
    if (!force && file.exists(xlsx_out)) {
      pam_log("INFO", "Excel report exists; skipping (use force=TRUE)",
              stage = stage, log_dir = cfg$paths$logs)
    } else {
      pam_log("INFO", "Writing Excel report...",
              stage = stage, log_dir = cfg$paths$logs)
      tryCatch({
        pam_report_excel(data, xlsx_out)
        generated <- c(generated, xlsx_out)
        pam_log("INFO", paste("Excel:", xlsx_out),
                stage = stage, log_dir = cfg$paths$logs)
      }, error = function(e) {
        pam_log("WARN",
                paste("Excel writing failed:", conditionMessage(e)),
                stage = stage, log_dir = cfg$paths$logs)
      })
    }
  }

  pam_log("INFO",
          paste("Report generation complete.",
                length(generated), "files produced."),
          stage = stage, log_dir = cfg$paths$logs)

  invisible(generated)
}
