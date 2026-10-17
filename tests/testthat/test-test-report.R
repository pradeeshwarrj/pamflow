test_that("pam_report_data handles missing files gracefully", {
  cfg <- list(
    paths = list(
      metadata = tempdir(),
      detections = tempdir(),
      occupancy = tempdir(),
      logs = tempdir()
    ),
    filenames = list(timezone = "Asia/Kolkata"),
    occupancy = list(min_effort_hours = 2)
  )
  suppressWarnings({
    data <- pamflow:::pam_report_data(cfg, "nonexistent")
  })
  expect_null(data$detections)
  expect_null(data$precision)
  expect_null(data$occupancy)
})

test_that("pam_report_excel writes a workbook", {
  skip_if_not_installed("openxlsx")
  data <- list(
    effort = data.table::data.table(
      site_id = "A",
      occasion_date = as.Date("2026-04-10"),
      effort_hours = 5,
      sufficient = TRUE
    ),
    detections = NULL,
    species_counts = data.table::data.table(
      species = "Test_sp", events = 10L, sites = 2L
    ),
    hourly_pattern = data.table::data.table(
      hour = 6L, n = 5L
    ),
    precision = NULL,
    recall = NULL,
    occupancy = data.table::data.table(
      species = "Test_sp", threshold_used = 0.5,
      n_sites = 2L, n_occasions = 3L,
      n_sites_detected = 2L, naive_occupancy = 1.0
    )
  )
  tmp <- tempfile(fileext = ".xlsx")
  pamflow:::pam_report_excel(data, tmp)
  expect_true(file.exists(tmp))
  expect_gt(file.size(tmp), 0)
  unlink(tmp)
})
