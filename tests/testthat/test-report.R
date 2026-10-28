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
  # Minimal audio_master.csv
  write.csv(
    data.frame(
      file_path = "a.wav", site_id = "S1", duration_s = 300,
      recording_date = "2024-01-01", qc_pass = TRUE,
      in_deployment = TRUE,
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
