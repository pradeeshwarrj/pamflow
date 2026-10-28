make_det <- function() {
  t0 <- as.POSIXct("2026-04-05 06:00:00", tz = "Asia/Kolkata")
  det <- data.table::data.table(
    rel = "G_1/a.wav", filename = "a.wav", grid = "G0001",
    scientific_name = c("Aus bus", "Aus bus", "Aus bus", "Cus dus", "Eus fus", "Aus bus", "Aus bus"),
    common_name = c("A", "A", "A", "C", "E", "A", "A"),
    species = c("Aus bus_A", "Aus bus_A", "Aus bus_A", "Cus dus_C", "Eus fus_E", "Aus bus_A", "Aus bus_A"),
    confidence = c(0.9, 0.8, 0.4, 0.95, 0.9, 0.9, 0.9),
    start_time = c(0, 2, 10, 0, 0, 3598, 3600),
    end_time = c(3, 5, 13, 3, 3, 3601, 3610),
    file_duration_s = 3600, recording_start = t0, in_deployment = TRUE)
  det[, detection_datetime := recording_start + start_time]
  det[]
}
pc <- list(min_confidence = 0.5, species_whitelist = list(), species_blacklist = list("Cus dus"),
           date_range = list(), drop_outside_deployment = TRUE, max_overrun_s = 3, merge_gap_s = 0)

test_that("rules remove the right rows and overlapping windows merge into events", {
  res <- pam_clean_detections(make_det(), pc)
  expect_equal(nrow(res$clean), 3)
  ev <- res$clean[scientific_name == "Aus bus"][order(start_time)]
  expect_equal(ev$start_time, c(0, 3598))
  expect_equal(ev$end_time, c(5, 3601))
  expect_equal(ev$n_windows, c(2, 1))
  expect_equal(ev$confidence[1], 0.9)
  expect_setequal(res$removed$reason,
                  c("below confidence threshold", "species on blacklist", "beyond end of recording"))
})

test_that("species thresholds override the global threshold", {
  thr <- data.table::data.table(scientific_name = "Aus bus", threshold = 0.3)
  res <- pam_clean_detections(make_det(), pc, thresholds = thr)
  expect_true(10 %in% res$clean$start_time)
})

test_that("detections outside the deployment window are dropped", {
  det <- make_det(); det[, in_deployment := FALSE]
  res <- pam_clean_detections(det, pc)
  expect_equal(nrow(res$clean), 0)
  expect_true("outside deployment window" %in% res$removed$reason)
})

test_that("whitelist keeps only listed species", {
  pc2 <- pc
  pc2$species_blacklist <- list()
  pc2$species_whitelist <- list("eus fus")
  res <- pam_clean_detections(make_det(), pc2)
  expect_equal(unique(res$clean$scientific_name), "Eus fus")
})

# ── pam_resolve_path ──────────────────────────────────────────────────────────

test_that("pam_resolve_path: NULL input returns NULL", {
  expect_null(pamflow:::pam_resolve_path(NULL, "/root"))
})

test_that("pam_resolve_path: NA input returns NULL", {
  expect_null(pamflow:::pam_resolve_path(NA_character_, "/root"))
})

test_that("pam_resolve_path: absolute path is returned unchanged", {
  expect_equal(pamflow:::pam_resolve_path("/abs/path/file.csv", "/root"),
               "/abs/path/file.csv")
})

test_that("pam_resolve_path: relative path is joined to root", {
  result <- pamflow:::pam_resolve_path("sub/file.csv", "/my/root")
  expect_equal(result, "/my/root/sub/file.csv")
})

# ── pam_or ────────────────────────────────────────────────────────────────────

test_that("pam_or: returns y when x is NULL", {
  expect_equal(pamflow:::pam_or(NULL, 42), 42)
})

test_that("pam_or: returns x when x is not NULL", {
  expect_equal(pamflow:::pam_or(7, 99), 7)
})

test_that("pam_or: returns x when x is FALSE (not NULL)", {
  expect_equal(pamflow:::pam_or(FALSE, "fallback"), FALSE)
})

# ── pam_match_species ─────────────────────────────────────────────────────────

test_that("pam_match_species: matches scientific_name case-insensitively", {
  det <- data.table::data.table(
    scientific_name = "Turdus merula",
    common_name     = "Common Blackbird",
    species         = "Turdus merula_Common Blackbird"
  )
  expect_true(pamflow:::pam_match_species(det, c("turdus merula"))[1])
})

test_that("pam_match_species: matches common_name", {
  det <- data.table::data.table(
    scientific_name = "Turdus merula",
    common_name     = "Common Blackbird",
    species         = "Turdus merula_Common Blackbird"
  )
  expect_true(pamflow:::pam_match_species(det, c("common blackbird"))[1])
})

test_that("pam_match_species: returns FALSE when no match", {
  det <- data.table::data.table(
    scientific_name = "Turdus merula",
    common_name     = "Common Blackbird",
    species         = "Turdus merula_Common Blackbird"
  )
  expect_false(pamflow:::pam_match_species(det, c("Parus major"))[1])
})

# ── pam_fwrite_local ──────────────────────────────────────────────────────────

test_that("pam_fwrite_local: writes CSV with POSIXct as formatted text", {
  dt <- data.table::data.table(
    id   = 1L,
    ts   = as.POSIXct("2024-06-15 08:30:00", tz = "UTC"),
    val  = 3.14
  )
  out <- tempfile(fileext = ".csv")
  pamflow:::pam_fwrite_local(dt, out)
  expect_true(file.exists(out))
  lines <- readLines(out)
  # POSIXct column should be text, not a numeric epoch
  expect_true(grepl("2024-06-15", lines[2]))
  unlink(out)
})

test_that("pam_fwrite_local: returns the output path invisibly", {
  dt  <- data.table::data.table(x = 1L)
  out <- tempfile(fileext = ".csv")
  res <- pamflow:::pam_fwrite_local(dt, out)
  expect_equal(res, out)
  unlink(out)
})

# ── pam_clean_detections: additional branch coverage ─────────────────────────

test_that("pam_clean_detections: date_range filter removes out-of-range rows", {
  det <- make_det()
  pc2 <- pc
  pc2$date_range <- list("2026-04-06", "2026-04-10")  # row date is 2026-04-05
  pc2$species_blacklist <- list()
  res <- pam_clean_detections(det, pc2)
  expect_true("outside date range" %in% res$removed$reason)
  expect_equal(nrow(res$clean), 0L)
})

test_that("pam_clean_detections: date_range keeps in-range rows", {
  det <- make_det()
  pc2 <- pc
  pc2$date_range <- list("2026-04-01", "2026-04-10")
  pc2$species_blacklist <- list()
  res <- pam_clean_detections(det, pc2)
  expect_false("outside date range" %in% res$removed$reason)
})

test_that("pam_clean_detections: seasonal filter keeps species in season", {
  det <- make_det()
  # Eus fus in season April (month 4): month_start=3, month_end=5
  seasons <- data.table::data.table(
    scientific_name = "Eus fus",
    month_start     = 3L,
    month_end       = 5L
  )
  pc2 <- pc
  pc2$species_blacklist <- list()
  res <- pam_clean_detections(det, pc2, seasons = seasons)
  expect_false("outside species season" %in% res$removed$reason)
})

test_that("pam_clean_detections: seasonal filter (year-wrap) removes out-of-season", {
  det <- make_det()  # detections in April (month 4)
  # Species only in season Nov-Jan (wraps year boundary)
  seasons <- data.table::data.table(
    scientific_name = "Eus fus",
    month_start     = 11L,
    month_end       = 1L
  )
  pc2 <- pc
  pc2$species_blacklist <- list()
  res <- pam_clean_detections(det, pc2, seasons = seasons)
  expect_true("outside species season" %in% res$removed$reason)
})

test_that("pam_clean_detections: steps table records each rule applied", {
  res <- pam_clean_detections(make_det(), pc)
  expect_s3_class(res$steps, "data.table")
  expect_true("rule" %in% names(res$steps))
  expect_true("n_before" %in% names(res$steps))
  expect_true("n_removed" %in% names(res$steps))
  expect_true(nrow(res$steps) > 0L)
})

test_that("pam_clean_detections: merge_gap_s joins detections within gap", {
  t0 <- as.POSIXct("2026-04-05 06:00:00", tz = "Asia/Kolkata")
  det <- data.table::data.table(
    rel             = "G/a.wav",
    filename        = "a.wav",
    grid            = "G0001",
    scientific_name = c("Aus bus", "Aus bus"),
    common_name     = c("A", "A"),
    species         = c("Aus bus_A", "Aus bus_A"),
    confidence      = c(0.9, 0.8),
    start_time      = c(0, 6),   # gap of 3 s between end_time=3 and start_time=6
    end_time        = c(3, 9),
    file_duration_s = 3600,
    recording_start = t0,
    in_deployment   = TRUE
  )
  det[, detection_datetime := recording_start + start_time]

  pc_gap <- list(min_confidence = 0.5, species_whitelist = list(),
                 species_blacklist = list(), date_range = list(),
                 drop_outside_deployment = TRUE, max_overrun_s = 3,
                 merge_gap_s = 5)   # gap <= 5 s → merged into one event
  res <- pam_clean_detections(det, pc_gap)
  expect_equal(nrow(res$clean), 1L)   # two windows merged into one event
  expect_equal(res$clean$n_windows[1], 2L)
})

test_that("pam_clean_detections: all removed leaves empty clean table", {
  det <- make_det()
  pc_strict <- list(min_confidence = 1.0, species_whitelist = list(),
                    species_blacklist = list(), date_range = list(),
                    drop_outside_deployment = TRUE, max_overrun_s = 3,
                    merge_gap_s = 0)
  res <- pam_clean_detections(det, pc_strict)
  expect_equal(nrow(res$clean), 0L)
  expect_true(nrow(res$removed) > 0L)
})
