test_that("pam_report_data: missing all CSV files returns all-NULL list with warnings", {
  cfg <- list(
    paths = list(
      metadata   = withr::local_tempdir(),
      detections = withr::local_tempdir(),
      validation = withr::local_tempdir(),
      occupancy  = withr::local_tempdir(),
      logs       = withr::local_tempdir()
    )
  )
  run_id <- "test_run"
  # No CSV files created — every read should warn and return NULL
  result <- suppressWarnings(pamflow:::pam_report_data(cfg, run_id))
  expect_type(result, "list")
  expect_null(result$effort)
  expect_null(result$detections)
  expect_null(result$precision)
  expect_null(result$recall)
  expect_null(result$occupancy)
})

test_that("pam_report_data: reads audio_master.csv when present", {
  meta_dir <- withr::local_tempdir()
  cfg <- list(
    paths = list(
      metadata   = meta_dir,
      detections = withr::local_tempdir(),
      validation = withr::local_tempdir(),
      occupancy  = withr::local_tempdir(),
      logs       = withr::local_tempdir()
    )
  )
  # Minimal audio_master.csv — must include start_time for pam_daily_effort
  write.csv(
    data.frame(
      file_path      = "a.wav",
      site_id        = "S1",
      duration_s     = 300,
      recording_date = "2024-01-01",
      start_time     = "2024-01-01 08:00:00",
      qc_pass        = TRUE,
      in_deployment  = TRUE,
      stringsAsFactors = FALSE
    ),
    file.path(meta_dir, "audio_master.csv"),
    row.names = FALSE
  )
  result <- suppressWarnings(pamflow:::pam_report_data(cfg, "run1"))
  expect_false(is.null(result$effort))
})

test_that("pam_report_excel: requires openxlsx and creates xlsx with at least one sheet", {
  skip_if_not_installed("openxlsx")
  out <- tempfile(fileext = ".xlsx")
  data <- list(
    effort     = data.frame(site = "S1", days = 5),
    detections = data.frame(species = "Turdus merula", n = 10),
    precision  = NULL,
    recall     = NULL,
    occupancy  = NULL
  )
  result <- pamflow:::pam_report_excel(data, out)
  expect_equal(result, out)
  expect_true(file.exists(out))
  wb <- openxlsx::loadWorkbook(out)
  expect_gte(length(openxlsx::sheets(wb)), 1L)
})

test_that("pam_report_excel: NULL-only data still creates a workbook file", {
  skip_if_not_installed("openxlsx")
  out <- tempfile(fileext = ".xlsx")
  data <- list(effort = NULL, detections = NULL, precision = NULL,
               recall = NULL, occupancy = NULL)
  # May warn about empty workbook, but should not error
  suppressWarnings(pamflow:::pam_report_excel(data, out))
  expect_true(file.exists(out))
})

test_that("pam_report_excel: errors clearly when openxlsx is missing", {
  skip_if(requireNamespace("openxlsx", quietly = TRUE),
          "openxlsx is installed — cannot test missing-package path")
  expect_error(pamflow:::pam_report_excel(list(), tempfile(fileext = ".xlsx")),
               "openxlsx")
})

# ── pam_report_data: individual path coverage ────────────────────────────────

test_that("pam_report_data: detections_clean.csv populates detections and species_counts", {
  det_dir  <- withr::local_tempdir()
  run_id   <- "run1"
  proc_dir <- file.path(det_dir, run_id, "processed")
  dir.create(proc_dir, recursive = TRUE)

  write.csv(
    data.frame(
      species          = c("Turdus merula_Common Blackbird",
                           "Turdus merula_Common Blackbird",
                           "Parus major_Great Tit"),
      scientific_name  = c("Turdus merula", "Turdus merula", "Parus major"),
      common_name      = c("Common Blackbird", "Common Blackbird", "Great Tit"),
      confidence       = c(0.90, 0.85, 0.75),
      grid             = c("GRID1", "GRID1", "GRID2"),
      stringsAsFactors = FALSE
    ),
    file.path(proc_dir, "detections_clean.csv"),
    row.names = FALSE
  )

  cfg <- list(
    paths = list(
      metadata   = withr::local_tempdir(),
      detections = det_dir,
      validation = withr::local_tempdir(),
      occupancy  = withr::local_tempdir(),
      logs       = withr::local_tempdir()
    )
  )

  result <- suppressWarnings(pamflow:::pam_report_data(cfg, run_id))

  expect_false(is.null(result$detections))
  expect_equal(nrow(result$detections), 3L)
  expect_false(is.null(result$species_counts))
  # Two distinct species: Turdus merula (2 events), Parus major (1), sorted descending
  expect_equal(nrow(result$species_counts), 2L)
  expect_equal(result$species_counts$events[1], 2L)
})

test_that("pam_report_data: detection_datetime column populates hourly_pattern", {
  det_dir  <- withr::local_tempdir()
  run_id   <- "run1"
  proc_dir <- file.path(det_dir, run_id, "processed")
  dir.create(proc_dir, recursive = TRUE)

  write.csv(
    data.frame(
      species            = c("Turdus merula_Common Blackbird",
                             "Turdus merula_Common Blackbird"),
      scientific_name    = c("Turdus merula", "Turdus merula"),
      common_name        = c("Common Blackbird", "Common Blackbird"),
      confidence         = c(0.9, 0.8),
      grid               = c("GRID1", "GRID1"),
      detection_datetime = c("2024-01-01 06:10:00", "2024-01-01 06:45:00"),
      stringsAsFactors   = FALSE
    ),
    file.path(proc_dir, "detections_clean.csv"),
    row.names = FALSE
  )

  cfg <- list(
    paths = list(
      metadata   = withr::local_tempdir(),
      detections = det_dir,
      validation = withr::local_tempdir(),
      occupancy  = withr::local_tempdir(),
      logs       = withr::local_tempdir()
    )
  )

  result <- suppressWarnings(pamflow:::pam_report_data(cfg, run_id))

  expect_false(is.null(result$hourly_pattern))
  expect_true("hour" %in% names(result$hourly_pattern))
  expect_equal(result$hourly_pattern$hour[1], 6L)
  expect_equal(result$hourly_pattern$n[1], 2L)
})

test_that("pam_report_data: precision_by_cell.csv populates precision when present", {
  det_dir <- withr::local_tempdir()
  run_id  <- "run1"
  val_dir <- file.path(det_dir, run_id, "validation")
  dir.create(val_dir, recursive = TRUE)

  write.csv(
    data.frame(
      species          = "Turdus merula",
      precision        = 0.90,
      stringsAsFactors = FALSE
    ),
    file.path(val_dir, "precision_by_cell.csv"),
    row.names = FALSE
  )

  cfg <- list(
    paths = list(
      metadata   = withr::local_tempdir(),
      detections = det_dir,
      validation = withr::local_tempdir(),
      occupancy  = withr::local_tempdir(),
      logs       = withr::local_tempdir()
    )
  )

  result <- suppressWarnings(pamflow:::pam_report_data(cfg, run_id))

  expect_false(is.null(result$precision))
  expect_equal(result$precision$species[1], "Turdus merula")
})

test_that("pam_report_data: recall_by_species_threshold.csv populates recall when present", {
  det_dir <- withr::local_tempdir()
  run_id  <- "run1"
  val_dir <- file.path(det_dir, run_id, "validation")
  dir.create(val_dir, recursive = TRUE)

  write.csv(
    data.frame(
      species          = "Turdus merula",
      recall           = 0.80,
      threshold        = 0.5,
      stringsAsFactors = FALSE
    ),
    file.path(val_dir, "recall_by_species_threshold.csv"),
    row.names = FALSE
  )

  cfg <- list(
    paths = list(
      metadata   = withr::local_tempdir(),
      detections = det_dir,
      validation = withr::local_tempdir(),
      occupancy  = withr::local_tempdir(),
      logs       = withr::local_tempdir()
    )
  )

  result <- suppressWarnings(pamflow:::pam_report_data(cfg, run_id))

  expect_false(is.null(result$recall))
  expect_equal(result$recall$species[1], "Turdus merula")
})

test_that("pam_report_data: occupancy_summary.csv populates occupancy when present", {
  occ_dir <- withr::local_tempdir()
  run_id  <- "run1"
  run_occ <- file.path(occ_dir, run_id)
  dir.create(run_occ, recursive = TRUE)

  write.csv(
    data.frame(
      species          = "Turdus merula",
      psi_mean         = 0.72,
      psi_se           = 0.06,
      stringsAsFactors = FALSE
    ),
    file.path(run_occ, "occupancy_summary.csv"),
    row.names = FALSE
  )

  cfg <- list(
    paths = list(
      metadata   = withr::local_tempdir(),
      detections = withr::local_tempdir(),
      validation = withr::local_tempdir(),
      occupancy  = occ_dir,
      logs       = withr::local_tempdir()
    )
  )

  result <- suppressWarnings(pamflow:::pam_report_data(cfg, run_id))

  expect_false(is.null(result$occupancy))
  expect_equal(result$occupancy$species[1], "Turdus merula")
})

# ── pam_report_data: effort branch (audio_master.csv present) ─────────────────

test_that("pam_report_data: audio_master.csv present populates effort", {
  meta_dir <- withr::local_tempdir()
  det_dir  <- withr::local_tempdir()
  run_id   <- "run_effort"

  # Write a minimal audio_master with valid entries
  master <- data.table::data.table(
    file_path     = file.path(meta_dir, "rec.wav"),
    grid          = "GRID1",
    deployment_id = "D01",
    start_time    = "2024-03-01T06:00:00Z",
    duration_s    = 7200,
    qc_pass       = TRUE,
    in_deployment = TRUE
  )
  data.table::fwrite(master, file.path(meta_dir, "audio_master.csv"))

  cfg <- list(
    filenames  = list(timezone = "UTC"),
    occupancy  = list(min_effort_hours = 2),
    paths = list(
      metadata   = meta_dir,
      detections = det_dir,
      validation = withr::local_tempdir(),
      occupancy  = withr::local_tempdir(),
      logs       = withr::local_tempdir()
    )
  )

  result <- suppressWarnings(pamflow:::pam_report_data(cfg, run_id))
  expect_false(is.null(result$effort))
  expect_s3_class(result$effort, "data.table")
  expect_true("effort_hours" %in% names(result$effort))
})

# ── pam_report_excel: writes xlsx with expected sheets ───────────────────────

test_that("pam_report_excel: writes xlsx and returns path", {
  skip_if_not_installed("openxlsx")
  out <- tempfile(fileext = ".xlsx")
  data <- list(
    effort = data.table::data.table(
      site_id = "S1", occasion_date = as.Date("2024-01-01"),
      effort_hours = 4, sufficient = TRUE
    ),
    species_counts = data.table::data.table(
      species = "Turdus merula_Common Blackbird", events = 5L, sites = 1L
    ),
    hourly_pattern = data.table::data.table(hour = 6L, n = 3L),
    precision      = NULL,
    recall         = NULL,
    occupancy      = NULL
  )
  result <- pamflow:::pam_report_excel(data, out)
  expect_equal(result, out)
  expect_true(file.exists(out))
  wb <- openxlsx::loadWorkbook(out)
  expect_true("Effort" %in% openxlsx::sheets(wb))
  expect_true("Detections" %in% openxlsx::sheets(wb))
  expect_true("Hourly_Pattern" %in% openxlsx::sheets(wb))
  unlink(out)
})

test_that("pam_report_excel: aborts informatively when openxlsx missing", {
  # Simulate openxlsx being absent by mocking requireNamespace
  with_mocked_bindings(
    requireNamespace = function(pkg, ...) FALSE,
    .package = "base",
    expect_error(
      pamflow:::pam_report_excel(list(), tempfile(fileext = ".xlsx")),
      "openxlsx"
    )
  )
})

test_that("pam_report_excel: NULL sections add none of the named section sheets", {
  skip_if_not_installed("openxlsx")
  out <- tempfile(fileext = ".xlsx")
  data <- list(
    effort = NULL, species_counts = NULL, hourly_pattern = NULL,
    precision = NULL, recall = NULL, occupancy = NULL
  )
  # openxlsx warns "Workbook does not contain any worksheets" when saving
  # an empty workbook and auto-adds a blank sheet — suppress that known noise.
  suppressWarnings(result <- pamflow:::pam_report_excel(data, out))
  wb     <- openxlsx::loadWorkbook(out)
  sheets <- openxlsx::sheets(wb)
  # None of the *content* sheets should have been created
  expect_false("Effort"         %in% sheets)
  expect_false("Detections"     %in% sheets)
  expect_false("Hourly_Pattern" %in% sheets)
  expect_false("Precision"      %in% sheets)
  expect_false("Recall"         %in% sheets)
  expect_false("Occupancy"      %in% sheets)
  unlink(out)
})

# ── pam_report_excel: all sections ────────────────────────────────────────────

test_that("pam_report_excel: writes Precision, Recall and Occupancy sheets when present", {
  skip_if_not_installed("openxlsx")
  out <- withr::local_tempfile(fileext = ".xlsx")
  data <- list(
    effort = NULL, species_counts = NULL, hourly_pattern = NULL,
    precision = data.table::data.table(species = "A", precision = 0.9),
    recall    = data.table::data.table(species = "A", recall = 0.8),
    occupancy = data.table::data.table(species = "A", naive_occupancy = 0.5)
  )
  pamflow:::pam_report_excel(data, out)
  sheets <- openxlsx::sheets(openxlsx::loadWorkbook(out))
  expect_true(all(c("Precision", "Recall", "Occupancy") %in% sheets))
  expect_false("Effort" %in% sheets)
})

test_that("pam_report_excel: zero-row tables do not create sheets", {
  skip_if_not_installed("openxlsx")
  out <- withr::local_tempfile(fileext = ".xlsx")
  data <- list(effort = data.table::data.table(site_id = character()),
               species_counts = NULL, hourly_pattern = NULL,
               precision = NULL, recall = NULL, occupancy = NULL)
  suppressWarnings(pamflow:::pam_report_excel(data, out))
  expect_false("Effort" %in% openxlsx::sheets(openxlsx::loadWorkbook(out)))
})

# ── pam_report orchestration ──────────────────────────────────────────────────

make_report_cfg <- function(tmp) {
  list(
    paths = list(metadata = file.path(tmp, "meta"), detections = file.path(tmp, "det"),
                 occupancy = file.path(tmp, "occ"), logs = file.path(tmp, "logs"),
                 reports = file.path(tmp, "reports")),
    birdnet = list(run_id = "run1"),
    report = list(formats = "excel", title = "T", author = "A")
  )
}

skip_if_no_report_template <- function() {
  skip_if_not_installed("rmarkdown")
  skip_if(!nzchar(system.file("rmd", "pam_report.Rmd", package = "pamflow")),
          "report template not available")
}

test_that("pam_report: excel format writes workbook, skips when present, rewrites on force", {
  skip_if_no_report_template()
  skip_if_not_installed("openxlsx")
  tmp <- withr::local_tempdir()
  cfg <- make_report_cfg(tmp)
  gen <- suppressWarnings(suppressMessages(pam_report(cfg)))
  expect_equal(basename(gen), "report_run1.xlsx")
  expect_true(file.exists(gen))

  gen2 <- suppressWarnings(suppressMessages(pam_report(cfg)))
  expect_length(gen2, 0L)

  gen3 <- suppressWarnings(suppressMessages(pam_report(cfg, force = TRUE)))
  expect_equal(gen3, gen)
})

test_that("pam_report: creates output_dir and defaults title/author when unset", {
  skip_if_no_report_template()
  skip_if_not_installed("openxlsx")
  tmp <- withr::local_tempdir()
  cfg <- make_report_cfg(tmp)
  cfg$report$title <- NULL
  cfg$report$author <- NULL
  out_dir <- file.path(tmp, "new", "dir")
  gen <- suppressWarnings(suppressMessages(pam_report(cfg, output_dir = out_dir)))
  expect_true(dir.exists(out_dir))
  expect_length(gen, 1L)
})

test_that("pam_report: html and pdf use rmarkdown::render and are listed when produced", {
  skip_if_no_report_template()
  tmp <- withr::local_tempdir()
  cfg <- make_report_cfg(tmp)
  cfg$report$formats <- c("html", "pdf")
  testthat::local_mocked_bindings(
    render = function(input, output_format, output_file, output_dir, ...) {
      file.create(file.path(output_dir, output_file))
      invisible(NULL)
    },
    .package = "rmarkdown"
  )
  gen <- suppressMessages(pam_report(cfg))
  expect_equal(basename(gen), c("report_run1.html", "report_run1.pdf"))
  # second call: both exist and are skipped
  expect_length(suppressMessages(pam_report(cfg)), 0L)
})

test_that("pam_report: render failures are logged and do not abort other formats", {
  skip_if_no_report_template()
  skip_if_not_installed("openxlsx")
  tmp <- withr::local_tempdir()
  cfg <- make_report_cfg(tmp)
  cfg$report$formats <- c("html", "pdf", "excel")
  testthat::local_mocked_bindings(
    render = function(...) stop("no latex"),
    .package = "rmarkdown"
  )
  gen <- suppressWarnings(suppressMessages(pam_report(cfg)))
  expect_equal(basename(gen), "report_run1.xlsx")
  log_txt <- paste(readLines(file.path(tmp, "logs", "08_report.log")), collapse = "\n")
  expect_match(log_txt, "HTML rendering failed")
  expect_match(log_txt, "PDF rendering failed")
})

test_that("pam_report: excel failure is logged and not listed", {
  skip_if_no_report_template()
  tmp <- withr::local_tempdir()
  cfg <- make_report_cfg(tmp)
  testthat::local_mocked_bindings(
    pam_report_excel = function(...) stop("disk full"),
    .package = "pamflow"
  )
  gen <- suppressWarnings(suppressMessages(pam_report(cfg)))
  expect_length(gen, 0L)
  log_txt <- paste(readLines(file.path(tmp, "logs", "08_report.log")), collapse = "\n")
  expect_match(log_txt, "Excel writing failed")
})
