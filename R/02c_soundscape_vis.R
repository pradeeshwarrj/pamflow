#' Stage 2c: Soundscape Visualization & Diagnostics
#'
#' Generates 24-hour diel profiles, day/night comparison plots, and summary
#' visualizations for ecoacoustic soundscape indices.
#'
#' @name soundscape_vis
NULL

# Quiet R CMD check NOTES for data.table non-standard evaluation
if (getRversion() >= "2.15.1") {
  utils::globalVariables(c(
    "hour", "grid", "diel_phase", "mean_val", "sd_val",
    "val_mean", "val_sd", "index_name", "y_val"
  ))
}

#' Plot 24-Hour Diel Curves for Acoustic Indices
#'
#' Generates line plots showing index values across 0-23 hours grouped by grid site.
#'
#' @param hourly_dt \code{data.table}. Hourly summary from \code{\link{pam_soundscape_summarise}}.
#' @param indices Character vector. Acoustic indices to plot (e.g. \code{c("aci", "bio")}).
#'   If NULL, auto-detects available indices in \code{hourly_dt}.
#' @param out_dir Character. Optional output directory to save plot images.
#' @param cfg List. Optional configuration structure.
#'
#' @return A list of ggplot objects.
#' @export
pam_soundscape_plot_diel <- function(hourly_dt, indices = NULL, out_dir = NULL, cfg = NULL) {
  stage <- "02c_soundscape_vis"
  log_dir <- if (!is.null(cfg) && !is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()

  if (is.null(hourly_dt) || nrow(hourly_dt) == 0) {
    stop("hourly_dt is empty or NULL.")
  }

  dt <- data.table::copy(hourly_dt)

  if (is.null(indices)) {
    mean_cols <- grep("_mean$", names(dt), value = TRUE)
    indices <- sub("_mean$", "", mean_cols)
  }

  if (length(indices) == 0) {
    stop("No valid index columns found in hourly_dt.")
  }

  plots <- list()

  for (idx in indices) {
    mean_col <- paste0(idx, "_mean")

    if (!mean_col %in% names(dt)) next

    # Copy subset & create eager y_val column to fix ggplot lazy evaluation bug
    p_dt <- data.table::copy(dt[!is.na(get(mean_col))])
    if (nrow(p_dt) == 0) next
    p_dt[, y_val := get(mean_col)]

    p <- ggplot2::ggplot(p_dt, ggplot2::aes(x = hour, y = y_val, color = grid, group = grid)) +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::geom_point(size = 1.5) +
      ggplot2::scale_x_continuous(breaks = seq(0, 23, by = 2)) +
      ggplot2::labs(
        title = glue::glue("24-Hour Diel Profile: {toupper(idx)}"),
        x = "Local Hour (0-23)",
        y = toupper(idx),
        color = "Grid"
      ) +
      ggplot2::theme_minimal() +
      ggplot2::theme(
        panel.grid.minor = ggplot2::element_blank(),
        plot.title = ggplot2::element_text(face = "bold", size = 12)
      )

    plots[[idx]] <- p

    if (!is.null(out_dir)) {
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      file_path <- file.path(out_dir, glue::glue("diel_hourly_{idx}.png"))
      ggplot2::ggsave(file_path, plot = p, width = 8, height = 5, dpi = 300)
      pam_log("INFO", glue::glue("Saved diel hourly plot for '{idx}' to {file_path}"), stage, log_dir)
    }
  }

  plots
}


#' Plot Day vs. Night Comparisons for Acoustic Indices
#'
#' Generates bar plots comparing mean values between Day and Night phases per grid site.
#'
#' @param diel_dt \code{data.table}. Diel summary from \code{\link{pam_soundscape_summarise}}.
#' @param indices Character vector. Acoustic indices to plot. If NULL, auto-detects.
#' @param out_dir Character. Optional output directory to save plot images.
#' @param cfg List. Optional configuration structure.
#'
#' @return A list of ggplot objects.
#' @export
pam_soundscape_plot_phase <- function(diel_dt, indices = NULL, out_dir = NULL, cfg = NULL) {
  stage <- "02c_soundscape_vis"
  log_dir <- if (!is.null(cfg) && !is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()

  if (is.null(diel_dt) || nrow(diel_dt) == 0) {
    stop("diel_dt is empty or NULL.")
  }

  dt <- data.table::copy(diel_dt)

  if (is.null(indices)) {
    mean_cols <- grep("_mean$", names(dt), value = TRUE)
    indices <- sub("_mean$", "", mean_cols)
  }

  if (length(indices) == 0) {
    stop("No valid index columns found in diel_dt.")
  }

  plots <- list()

  for (idx in indices) {
    mean_col <- paste0(idx, "_mean")

    if (!mean_col %in% names(dt)) next

    # Copy subset & create eager y_val column to fix ggplot lazy evaluation bug
    p_dt <- data.table::copy(dt[!is.na(get(mean_col))])
    if (nrow(p_dt) == 0) next
    p_dt[, y_val := get(mean_col)]

    p <- ggplot2::ggplot(p_dt, ggplot2::aes(x = grid, y = y_val, fill = diel_phase)) +
      ggplot2::geom_bar(stat = "identity", position = ggplot2::position_dodge(width = 0.8), width = 0.7) +
      ggplot2::labs(
        title = glue::glue("Day vs. Night Phase Comparison: {toupper(idx)}"),
        x = "Grid",
        y = toupper(idx),
        fill = "Diel Phase"
      ) +
      ggplot2::scale_fill_manual(values = c("Day" = "#E69F00", "Night" = "#2B5C8F")) +
      ggplot2::theme_minimal() +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold", size = 12)
      )

    plots[[idx]] <- p

    if (!is.null(out_dir)) {
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      file_path <- file.path(out_dir, glue::glue("diel_phase_{idx}.png"))
      ggplot2::ggsave(file_path, plot = p, width = 7, height = 4.5, dpi = 300)
      pam_log("INFO", glue::glue("Saved diel phase plot for '{idx}' to {file_path}"), stage, log_dir)
    }
  }

  plots
}


#' Generate HTML Soundscape Diagnostic Report
#'
#' Compiles an HTML diagnostic report summarizing soundscape indices, site covariates,
#' and diel visualizations using the template at \code{inst/rmd/soundscape_report.Rmd}.
#'
#' @param cfg List. Parsed configuration structure from \code{\link{pam_config_read}}.
#' @param sc_results List. Optional return object from \code{\link{pam_soundscape_run}}.
#' @param vis_results List. Return object from \code{\link{pam_soundscape_plot_diel}} / \code{\link{pam_soundscape_plot_phase}}.
#'
#' @return Character. Path to the generated HTML report file.
#' @export
pam_soundscape_report <- function(cfg, sc_results = NULL, vis_results = NULL) {
  stage <- "02c_soundscape_vis"
  log_dir <- if (!is.null(cfg) && !is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()

  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    pam_log("WARN", "rmarkdown package missing. Skipping HTML report generation.", stage, log_dir)
    return(NULL)
  }

  run_id <- pam_or(cfg$run_id, pam_or(cfg$soundscape$run_id, "run01"))
  out_dir <- file.path(pam_or(cfg$paths$project_root, "."), "data", "soundscape", run_id, "reports")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  template_path <- system.file("rmd", "soundscape_report.Rmd", package = "pamflow")
  if (template_path == "" || !file.exists(template_path)) {
    template_path <- file.path(pam_or(cfg$paths$project_root, "."), "inst", "rmd", "soundscape_report.Rmd")
  }
  if (!file.exists(template_path)) {
    template_path <- file.path(getwd(), "inst", "rmd", "soundscape_report.Rmd")
  }

  if (!file.exists(template_path)) {
    pam_log("WARN", "Report template not found at inst/rmd/soundscape_report.Rmd. Skipping report.", stage, log_dir)
    return(NULL)
  }

  if (is.null(sc_results)) {
    cov_path <- file.path(pam_or(cfg$paths$project_root, "."), "data", "soundscape", run_id, "soundscape_site_covariates.csv")
    cov_dt <- if (file.exists(cov_path)) data.table::fread(cov_path) else NULL
  } else {
    cov_dt <- sc_results$site_covariates
  }

  out_file <- file.path(out_dir, paste0("Soundscape_Report_", run_id, ".html"))

  hourly_plots <- if (!is.null(vis_results)) vis_results$hourly_plots else NULL
  diel_plots   <- if (!is.null(vis_results)) vis_results$diel_plots else NULL

  rmarkdown::render(
    input = template_path,
    output_file = out_file,
    params = list(
      run_id = run_id,
      hourly_plots = hourly_plots,
      diel_plots = diel_plots,
      cov_dt = cov_dt
    ),
    envir = new.env(),
    quiet = TRUE
  )

  pam_log("INFO", glue::glue("HTML Soundscape report generated: {out_file}"), stage, log_dir)
  out_file
}


#' Run Stage 2c Soundscape Visualization Pipeline
#'
#' Takes parsed config and optional previous Stage 2b results, loads soundscape
#' summary tables, exports diagnostic diel plots, and generates an HTML report.
#'
#' @param cfg List. Parsed configuration structure from \code{\link{pam_config_read}}.
#' @param sc_results List. Optional return object from \code{\link{pam_soundscape_run}}.
#' @param generate_report Logical. If TRUE, compiles an HTML diagnostic report.
#'
#' @return A named list of generated ggplot objects.
#' @export
pam_soundscape_run_vis <- function(cfg, sc_results = NULL, generate_report = TRUE) {
  stage <- "02c_soundscape_vis"
  log_dir <- if (!is.null(cfg$paths$logs)) cfg$paths$logs else tempdir()
  run_id <- pam_or(cfg$run_id, pam_or(cfg$soundscape$run_id, "run01"))

  pam_log("INFO", glue::glue("Starting Stage 2c Soundscape Visualization for run_id: '{run_id}'"), stage, log_dir)

  out_dir <- file.path(pam_or(cfg$paths$project_root, "."), "data", "soundscape", run_id, "plots")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(sc_results)) {
    hourly_dt <- sc_results$hourly
    diel_dt   <- sc_results$diel
  } else {
    sc_dir_candidates <- c(
      file.path(pam_or(cfg$paths$project_root, "."), "data", "soundscape", run_id),
      file.path(pam_or(cfg$paths$output, cfg$data$output), "soundscape", run_id)
    )
    sc_dir <- NULL
    for (cand in sc_dir_candidates) {
      if (!is.null(cand) && dir.exists(cand)) {
        sc_dir <- cand
        break
      }
    }
    if (is.null(sc_dir)) {
      sc_dir <- file.path(pam_or(cfg$paths$project_root, "."), "data", "soundscape", run_id)
    }

    hourly_path <- file.path(sc_dir, "soundscape_hourly.csv")
    diel_path   <- file.path(sc_dir, "soundscape_diel_summary.csv")

    if (!file.exists(hourly_path) || !file.exists(diel_path)) {
      stop(glue::glue("Soundscape summary files not found in: {sc_dir}. Run Stage 2b first."))
    }

    hourly_dt <- data.table::fread(hourly_path)
    diel_dt   <- data.table::fread(diel_path)
  }

  hourly_plots <- pam_soundscape_plot_diel(hourly_dt, out_dir = out_dir, cfg = cfg)
  diel_plots   <- pam_soundscape_plot_phase(diel_dt, out_dir = out_dir, cfg = cfg)

  vis_res <- list(
    hourly_plots = hourly_plots,
    diel_plots   = diel_plots
  )

  if (generate_report) {
    pam_soundscape_report(cfg, sc_results = sc_results, vis_results = vis_res)
  }

  pam_log("INFO", glue::glue("Stage 2c Soundscape Visualization completed. Plots saved to: {out_dir}"), stage, log_dir)

  vis_res
}
