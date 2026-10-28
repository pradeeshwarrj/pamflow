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

# ── pam_site_covariates ───────────────────────────────────────────────────────

test_that("pam_site_covariates: merges effort totals per site", {
  master <- data.table::data.table(
    site_id       = c("G0001", "G0001", "G0002"),
    grid          = c("G0001", "G0001", "G0002"),
    deployment_id = c("d1",    "d1",    "d2"),
    latitude      = c(12.34,   12.34,   12.50),
    longitude     = c(77.56,   77.56,   77.60)
  )
  effort <- data.table::data.table(
    site_id       = c("G0001", "G0001", "G0002"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11", "2026-04-10")),
    effort_hours  = c(5, 4, 3),
    sufficient    = c(TRUE, TRUE, TRUE)
  )
  cov <- pamflow:::pam_site_covariates(master, effort)

  expect_s3_class(cov, "data.table")
  expect_equal(nrow(cov), 2L)   # 2 unique sites
  g1 <- cov[site_id == "G0001"]
  g2 <- cov[site_id == "G0002"]
  expect_equal(g1$total_effort_hours,   9)
  expect_equal(g1$n_occasions_surveyed, 2L)
  expect_equal(g2$total_effort_hours,   3)
  expect_equal(g2$n_occasions_surveyed, 1L)
})

test_that("pam_site_covariates: site with no effort rows gets zeros", {
  master <- data.table::data.table(
    site_id = "G0099", grid = "G0099", deployment_id = "d99",
    latitude = 12.0, longitude = 77.0
  )
  effort <- data.table::data.table(
    site_id = character(), occasion_date = as.Date(character()),
    effort_hours = numeric(), sufficient = logical()
  )
  cov <- pamflow:::pam_site_covariates(master, effort)

  expect_equal(nrow(cov), 1L)
  expect_equal(cov$total_effort_hours,   0)
  expect_equal(cov$n_occasions_surveyed, 0L)
})

# ── pam_build_occupancy (orchestrator) ───────────────────────────────────────

test_that("pam_build_occupancy: skips rebuild when outputs exist and force = FALSE", {
  tmp <- withr::local_tempdir()
  occ_dir <- file.path(tmp, "occupancy", "run01")
  dir.create(occ_dir, recursive = TRUE)
  # Pre-create the summary sentinel that signals a complete run
  writeLines("done", file.path(occ_dir, "occupancy_summary.csv"))

  cfg <- list(
    paths = list(
      metadata   = tmp,
      detections = tmp,
      occupancy  = file.path(tmp, "occupancy"),
      logs       = file.path(tmp, "logs")
    ),
    filenames  = list(timezone = "Asia/Kolkata"),
    occupancy  = list(run_id = "run01", min_effort_hours = 2, min_detections = 1),
    processing = list(min_confidence = 0.5,
                      species_thresholds_file = NULL)
  )

  result <- pam_build_occupancy(cfg, run_id = "run01", force = FALSE)
  expect_null(result)   # returns invisible(NULL) when skipped
})

test_that("pam_build_occupancy: errors informatively when audio_master.csv missing", {
  tmp <- withr::local_tempdir()
  cfg <- list(
    paths = list(
      metadata   = tmp,
      detections = tmp,
      occupancy  = file.path(tmp, "occupancy"),
      logs       = file.path(tmp, "logs")
    ),
    filenames  = list(timezone = "Asia/Kolkata"),
    occupancy  = list(run_id = "run01", min_effort_hours = 2, min_detections = 1),
    processing = list(min_confidence = 0.5,
                      species_thresholds_file = NULL)
  )
  expect_error(
    pam_build_occupancy(cfg, run_id = "run01", force = TRUE),
    "audio_master.csv not found"
  )
})

# ── additional edge cases ─────────────────────────────────────────────────────

test_that("pam_site_id: adds site_id even when all rows have qc_pass FALSE", {
  dt <- data.table::data.table(
    grid          = "G1",
    deployment_id = "d1",
    qc_pass       = FALSE
  )
  pamflow:::pam_site_id(dt)
  expect_true("site_id" %in% names(dt))
  expect_equal(nrow(dt), 1L)
})

test_that("pam_daily_effort: recording below min_effort_h is flagged insufficient", {
  m <- data.table::data.table(
    site_id       = "G1_R1",
    start_time    = as.POSIXct("2024-01-01 06:00:00", tz = "UTC"),
    duration_s    = 3600,     # 1 hour — below 2 h threshold
    qc_pass       = TRUE,
    in_deployment = TRUE
  )
  eff <- pamflow:::pam_daily_effort(m, tz = "UTC", min_effort_h = 2)
  expect_false(eff$sufficient[1])
})

test_that("pam_detection_matrix: detection below threshold becomes 0 not 1", {
  effort <- data.table::data.table(
    site_id       = "G1_R1",
    occasion_date = as.Date("2024-01-01"),
    effort_hours  = 8,
    sufficient    = TRUE
  )
  events <- data.table::data.table(
    site_id       = "G1_R1",
    occasion_date = as.Date("2024-01-01"),
    confidence    = 0.3    # below default threshold of 0.5
  )
  wide <- pamflow:::pam_detection_matrix(events, effort, threshold = 0.5)
  expect_equal(wide[site_id == "G1_R1", "2024-01-01", with = FALSE][[1]], 0L)
})

test_that("pam_detection_matrix: insufficient effort day is NA", {
  effort <- data.table::data.table(
    site_id       = "G1_R1",
    occasion_date = as.Date("2024-01-01"),
    effort_hours  = 0.5,
    sufficient    = FALSE
  )
  events <- data.table::data.table(
    site_id       = character(),
    occasion_date = as.Date(character()),
    confidence    = numeric()
  )
  wide <- pamflow:::pam_detection_matrix(events, effort, threshold = 0.5)
  expect_true(is.na(wide[site_id == "G1_R1", "2024-01-01", with = FALSE][[1]]))
})

test_that("pam_occasion_covariates: empty effort returns table with julian_date column", {
  eff_empty <- data.table::data.table(
    site_id       = character(),
    occasion_date = as.Date(character()),
    effort_hours  = numeric(),
    sufficient    = logical()
  )
  cov <- pamflow:::pam_occasion_covariates(eff_empty)
  expect_true("julian_date" %in% names(cov))
  expect_equal(nrow(cov), 0L)
})
