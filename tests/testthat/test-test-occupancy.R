test_that("pam_site_id: single deployment per grid", {
  dt <- data.table::data.table(
    grid = c("G0001", "G0001", "G0002"),
    deployment_id = c("d1", "d1", "d2")
  )
  pamflow:::pam_site_id(dt)
  expect_equal(dt$site_id, c("G0001", "G0001", "G0002"))
})

test_that("pam_site_id: multiple deployments per grid", {
  dt <- data.table::data.table(
    grid = c("G0001", "G0001", "G0002", "G0002"),
    deployment_id = c("d1", "d2", "d3", "d3")
  )
  pamflow:::pam_site_id(dt)
  expect_equal(dt$site_id,
               c("G0001_d1", "G0001_d2", "G0002", "G0002"))
})

test_that("pam_site_id: no deployment_id column", {
  dt <- data.table::data.table(grid = c("G0001", "G0002"))
  pamflow:::pam_site_id(dt)
  expect_equal(dt$site_id, c("G0001", "G0002"))
})

test_that("pam_daily_effort: basic calculation", {
  master <- data.table::data.table(
    site_id = c("G0001", "G0001", "G0001"),
    start_time = as.POSIXct(
      c("2026-04-10 06:00:00",
        "2026-04-10 07:00:00",
        "2026-04-11 06:00:00"),
      tz = "Asia/Kolkata"
    ),
    duration_s = c(3600, 3600, 1800),
    qc_pass = TRUE,
    in_deployment = TRUE
  )
  eff <- pamflow:::pam_daily_effort(master, tz = "Asia/Kolkata",
                                    min_effort_h = 2)
  expect_equal(nrow(eff), 2L)
  # Day 1: 2 h total
  d1 <- eff[occasion_date == as.Date("2026-04-10")]
  expect_equal(d1$effort_hours, 2)
  expect_true(d1$sufficient)
  # Day 2: 0.5 h total
  d2 <- eff[occasion_date == as.Date("2026-04-11")]
  expect_equal(d2$effort_hours, 0.5)
  expect_false(d2$sufficient)
})

test_that("pam_daily_effort: filters out bad recordings", {
  master <- data.table::data.table(
    site_id = c("G0001", "G0001"),
    start_time = as.POSIXct(
      c("2026-04-10 06:00:00", "2026-04-10 07:00:00"),
      tz = "Asia/Kolkata"
    ),
    duration_s = c(3600, 3600),
    qc_pass = c(TRUE, FALSE),
    in_deployment = c(TRUE, TRUE)
  )
  eff <- pamflow:::pam_daily_effort(master, tz = "Asia/Kolkata",
                                    min_effort_h = 2)
  expect_equal(nrow(eff), 1L)
  expect_equal(eff$effort_hours, 1)
  expect_false(eff$sufficient)
})

test_that("pam_daily_effort: midnight crossing", {
  master <- data.table::data.table(
    site_id = "G0001",
    start_time = as.POSIXct("2026-04-10 23:30:00",
                            tz = "Asia/Kolkata"),
    duration_s = 3600,
    qc_pass = TRUE,
    in_deployment = TRUE
  )
  eff <- pamflow:::pam_daily_effort(master, tz = "Asia/Kolkata",
                                    min_effort_h = 0)
  expect_equal(nrow(eff), 2L)
  d1 <- eff[occasion_date == as.Date("2026-04-10")]
  d2 <- eff[occasion_date == as.Date("2026-04-11")]
  expect_equal(d1$effort_hours, 0.5, tolerance = 0.01)
  expect_equal(d2$effort_hours, 0.5, tolerance = 0.01)
})

test_that("pam_detection_matrix: 1/0/NA assignment", {
  effort <- data.table::data.table(
    site_id = c("A", "A", "B", "B"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11",
                              "2026-04-10", "2026-04-11")),
    effort_hours = c(5, 3, 1, 4),
    sufficient = c(TRUE, TRUE, FALSE, TRUE)
  )
  events <- data.table::data.table(
    site_id = c("A", "B"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11")),
    confidence = c(0.8, 0.6)
  )
  wide <- pamflow:::pam_detection_matrix(events, effort,
                                         threshold = 0.5)
  expect_equal(nrow(wide), 2L)
  # Site A, day 1: detected
  expect_equal(wide[site_id == "A", as.character(as.Date("2026-04-10")),
                    with = FALSE][[1]], 1L)
  # Site A, day 2: surveyed, not detected
  expect_equal(wide[site_id == "A", as.character(as.Date("2026-04-11")),
                    with = FALSE][[1]], 0L)
  # Site B, day 1: insufficient effort -> NA
  expect_true(is.na(wide[site_id == "B",
                         as.character(as.Date("2026-04-10")),
                         with = FALSE][[1]]))
  # Site B, day 2: detected
  expect_equal(wide[site_id == "B", as.character(as.Date("2026-04-11")),
                    with = FALSE][[1]], 1L)
})

test_that("pam_occasion_covariates: julian date", {
  effort <- data.table::data.table(
    site_id = c("A", "A", "A"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11",
                              "2026-04-13")),
    effort_hours = c(5, 3, 4),
    sufficient = c(TRUE, TRUE, TRUE)
  )
  cov <- pamflow:::pam_occasion_covariates(effort)
  expect_equal(cov$julian_date, c(1L, 2L, 4L))
})
