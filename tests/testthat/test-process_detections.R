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
