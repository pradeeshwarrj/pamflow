test_that("pam_soundscape_plot_diel creates ggplot object", {
  hourly_dt <- data.table::data.table(
    grid = rep(c("G01", "G02"), each = 24),
    hour = rep(0:23, 2),
    aci_mean = runif(48, 100, 200),
    aci_sd = runif(48, 5, 15),
    bio_mean = runif(48, 2, 8),
    bio_sd = runif(48, 0.5, 1.5)
  )

  p_list <- pam_soundscape_plot_diel(hourly_dt)
  expect_type(p_list, "list")
  expect_named(p_list, c("aci", "bio"))
  expect_s3_class(p_list$aci, "ggplot")
})

test_that("pam_soundscape_plot_phase creates ggplot object", {
  diel_dt <- data.table::data.table(
    grid = rep(c("G01", "G02"), each = 2),
    diel_phase = rep(c("Day", "Night"), 2),
    aci_mean = c(150, 120, 160, 110),
    aci_sd = c(10, 8, 12, 9),
    bio_mean = c(5, 2, 6, 3),
    bio_sd = c(1, 0.5, 1.2, 0.6)
  )

  p_list <- pam_soundscape_plot_phase(diel_dt)
  expect_type(p_list, "list")
  expect_named(p_list, c("aci", "bio"))
  expect_s3_class(p_list$aci, "ggplot")
})

# ── helpers ───────────────────────────────────────────────────────────────────

mk_hourly <- function() {
  data.table::data.table(
    grid = rep(c("G01", "G02"), each = 24), hour = rep(0:23, 2),
    aci_mean = seq_len(48) + 100, bio_mean = seq_len(48) / 10
  )
}

mk_diel <- function() {
  data.table::data.table(
    grid = rep(c("G01", "G02"), each = 2), diel_phase = rep(c("Day", "Night"), 2),
    aci_mean = c(150, 120, 160, 110), bio_mean = c(5, 2, 6, 3)
  )
}

# ── plot_diel / plot_phase: inputs and options ────────────────────────────────

test_that("pam_soundscape_plot_diel: errors on NULL or empty input", {
  expect_error(pam_soundscape_plot_diel(NULL), "empty or NULL")
  expect_error(pam_soundscape_plot_diel(data.table::data.table()), "empty or NULL")
})

test_that("pam_soundscape_plot_diel: errors when no *_mean columns exist", {
  expect_error(pam_soundscape_plot_diel(data.table::data.table(grid = "G1", hour = 1L)),
               "No valid index columns")
})

test_that("pam_soundscape_plot_diel: respects indices and skips unknown ones", {
  p <- pam_soundscape_plot_diel(mk_hourly(), indices = c("bio", "nope"))
  expect_named(p, "bio")
})

test_that("pam_soundscape_plot_diel: skips indices that are entirely NA", {
  dt <- mk_hourly()
  dt[, aci_mean := NA_real_]
  expect_named(pam_soundscape_plot_diel(dt), "bio")
})

test_that("pam_soundscape_plot_diel: saves PNG files when out_dir is given", {
  skip_if_not_installed("ggplot2")
  out <- file.path(withr::local_tempdir(), "plots")
  cfg <- list(paths = list(logs = withr::local_tempdir()))
  suppressMessages(pam_soundscape_plot_diel(mk_hourly(), indices = "aci", out_dir = out, cfg = cfg))
  expect_true(file.exists(file.path(out, "diel_hourly_aci.png")))
})

test_that("pam_soundscape_plot_phase: errors on NULL, empty and no-index input", {
  expect_error(pam_soundscape_plot_phase(NULL), "empty or NULL")
  expect_error(pam_soundscape_plot_phase(data.table::data.table()), "empty or NULL")
  expect_error(pam_soundscape_plot_phase(data.table::data.table(grid = "G1", diel_phase = "Day")),
               "No valid index columns")
})

test_that("pam_soundscape_plot_phase: respects indices and skips unknown/all-NA ones", {
  expect_named(pam_soundscape_plot_phase(mk_diel(), indices = c("aci", "nope")), "aci")
  dt <- mk_diel(); dt[, bio_mean := NA_real_]
  expect_named(pam_soundscape_plot_phase(dt), "aci")
})

test_that("pam_soundscape_plot_phase: saves PNG files when out_dir is given", {
  skip_if_not_installed("ggplot2")
  out <- file.path(withr::local_tempdir(), "plots")
  cfg <- list(paths = list(logs = withr::local_tempdir()))
  suppressMessages(pam_soundscape_plot_phase(mk_diel(), indices = "bio", out_dir = out, cfg = cfg))
  expect_true(file.exists(file.path(out, "diel_phase_bio.png")))
})

# ── pam_soundscape_run_vis ────────────────────────────────────────────────────

mk_vis_cfg <- function(tmp) {
  list(paths = list(project_root = tmp, logs = file.path(tmp, "logs")), run_id = "run01")
}

test_that("pam_soundscape_run_vis: plots from sc_results and writes PNGs", {
  tmp <- withr::local_tempdir()
  res <- suppressMessages(pam_soundscape_run_vis(
    mk_vis_cfg(tmp), sc_results = list(hourly = mk_hourly(), diel = mk_diel()),
    generate_report = FALSE))
  expect_named(res, c("hourly_plots", "diel_plots"))
  expect_named(res$hourly_plots, c("aci", "bio"))
  plots_dir <- file.path(tmp, "data", "soundscape", "run01", "plots")
  expect_true(file.exists(file.path(plots_dir, "diel_hourly_aci.png")))
  expect_true(file.exists(file.path(plots_dir, "diel_phase_bio.png")))
})

test_that("pam_soundscape_run_vis: reads summary CSVs from disk when sc_results is NULL", {
  tmp <- withr::local_tempdir()
  sc_dir <- file.path(tmp, "data", "soundscape", "run01")
  dir.create(sc_dir, recursive = TRUE)
  data.table::fwrite(mk_hourly(), file.path(sc_dir, "soundscape_hourly.csv"))
  data.table::fwrite(mk_diel(), file.path(sc_dir, "soundscape_diel_summary.csv"))
  res <- suppressMessages(pam_soundscape_run_vis(mk_vis_cfg(tmp), generate_report = FALSE))
  expect_named(res$diel_plots, c("aci", "bio"))
})

test_that("pam_soundscape_run_vis: errors when summary CSVs are missing", {
  tmp <- withr::local_tempdir()
  expect_error(suppressMessages(pam_soundscape_run_vis(mk_vis_cfg(tmp), generate_report = FALSE)),
               "Soundscape summary files not found")
})

test_that("pam_soundscape_run_vis: generate_report = TRUE calls pam_soundscape_report", {
  tmp <- withr::local_tempdir()
  called <- FALSE
  testthat::local_mocked_bindings(
    pam_soundscape_report = function(cfg, sc_results = NULL, vis_results = NULL) {
      called <<- TRUE
      expect_named(vis_results, c("hourly_plots", "diel_plots"))
      "report.html"
    },
    .package = "pamflow"
  )
  suppressMessages(pam_soundscape_run_vis(
    mk_vis_cfg(tmp), sc_results = list(hourly = mk_hourly(), diel = mk_diel())))
  expect_true(called)
})

# ── pam_soundscape_report ─────────────────────────────────────────────────────

test_that("pam_soundscape_report: renders via rmarkdown and returns the output path", {
  skip_if_not_installed("rmarkdown")
  skip_if(!nzchar(system.file("rmd", "soundscape_report.Rmd", package = "pamflow")),
          "soundscape template not available")
  tmp <- withr::local_tempdir()
  rendered <- NULL
  testthat::local_mocked_bindings(
    render = function(input, output_file, params, ...) {
      rendered <<- params
      file.create(output_file)
      invisible(output_file)
    },
    .package = "rmarkdown"
  )
  cov <- data.table::data.table(grid = "G1", aci_day_mean = 1)
  out <- suppressMessages(pam_soundscape_report(
    mk_vis_cfg(tmp), sc_results = list(site_covariates = cov),
    vis_results = list(hourly_plots = list(), diel_plots = list())))
  expect_equal(basename(out), "Soundscape_Report_run01.html")
  expect_true(file.exists(out))
  expect_equal(rendered$run_id, "run01")
  expect_equal(rendered$cov_dt, cov)
})

test_that("pam_soundscape_report: reads site covariates from disk when sc_results is NULL", {
  skip_if_not_installed("rmarkdown")
  skip_if(!nzchar(system.file("rmd", "soundscape_report.Rmd", package = "pamflow")),
          "soundscape template not available")
  tmp <- withr::local_tempdir()
  sc_dir <- file.path(tmp, "data", "soundscape", "run01")
  dir.create(sc_dir, recursive = TRUE)
  data.table::fwrite(data.table::data.table(grid = "G1", aci_day_mean = 2),
                     file.path(sc_dir, "soundscape_site_covariates.csv"))
  got <- NULL
  testthat::local_mocked_bindings(
    render = function(input, output_file, params, ...) { got <<- params; invisible(output_file) },
    .package = "rmarkdown"
  )
  suppressMessages(pam_soundscape_report(mk_vis_cfg(tmp)))
  expect_equal(got$cov_dt$aci_day_mean, 2)
})
