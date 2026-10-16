bands <- c(0.3, 0.4, 0.5, 0.7, 1.0)

make_pool <- function() {
  set.seed(42)
  mk <- function(sp, com, n) {
    st <- sort(runif(n, 0, 15))
    data.table::data.table(
      rel = "G_0001/test.wav", filename = "test.wav", grid = "G0001", recorder = "SW01",
      scientific_name = sp, common_name = com, species = paste(sp, com, sep = "_"),
      confidence = runif(n, 0.3, 1), mean_confidence = 0.5, n_windows = 1L,
      start_time = round(st, 1), end_time = round(st, 1) + 3,
      recording_date = as.Date("2026-04-10"),
      detection_datetime = as.POSIXct("2026-04-10 08:00:00", tz = "Asia/Kolkata") + st)
  }
  p <- data.table::rbindlist(list(mk("Aus bus", "A", 150), mk("Bus cus", "B", 20),
                                  mk("Cus dus", "C", 5)))
  p[, event_id := paste(rel, scientific_name, sprintf("%.1f", start_time), sep = "|")]
  unique(p, by = "event_id")
}

mk_cfg <- function(root) {
  list(paths = list(detections = file.path(root, "det"), logs = file.path(root, "logs"),
                    audio_standardized = file.path(root, "audio"),
                    filtered = file.path(root, "filt")),
       birdnet = list(run_id = "t", input = "standardized"),
       filter = list(ffmpeg_path = "ffmpeg"),
       validation = list(bands = list(0.3, 0.4, 0.5, 0.7, 1.0), n_per_cell = 4,
                         rare_max_events = 30, rare_n = 50, clip_pad_s = 3, seed = 1,
                         spec_max_hz = 12000, spec_px = list(900, 360)))
}

make_source <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  sr <- 16000; t <- seq_len(20 * sr) / sr
  x <- 0.3 * sin(2 * pi * 3000 * t) * ((t %% 7) < 2)
  tuneR::writeWave(tuneR::Wave(left = as.integer(round(x * 32767)), samp.rate = sr, bit = 16), path)
}

have_ffmpeg <- function() nzchar(unname(Sys.which("ffmpeg")))

test_that("band index and label", {
  expect_equal(pam_band_index(c(0.3, 0.39, 0.4, 0.69, 0.7, 1.0), bands), c(1, 1, 2, 3, 4, 4))
  expect_equal(pam_band_label(c(1, 4), bands), c("0.30-0.40", "0.70-1.00"))
})

test_that("stratified sampling respects cells, seed and exclusions", {
  pool <- make_pool()
  s1 <- pam_validation_sample(pool, "stratified", bands, n_per_cell = 5, seed = 1)
  expect_true(all(s1[, .N, by = .(scientific_name, band)]$N <= 5))
  s1b <- pam_validation_sample(pool, "stratified", bands, n_per_cell = 5, seed = 1)
  expect_equal(sort(s1$event_id), sort(s1b$event_id))
  s2 <- pam_validation_sample(pool, "stratified", bands, n_per_cell = 5, seed = 2,
                              exclude_ids = s1$event_id)
  expect_length(intersect(s1$event_id, s2$event_id), 0)
})

test_that("rare, random and species strategies", {
  pool <- make_pool()
  r <- pam_validation_sample(pool, "rare", bands, rare_max_events = 30, rare_n = 50)
  expect_setequal(unique(r$scientific_name), c("Bus cus", "Cus dus"))
  expect_equal(nrow(r), pool[scientific_name %in% c("Bus cus", "Cus dus"), .N])
  expect_equal(nrow(pam_validation_sample(pool, "random", bands, n = 40)), 40)
  sp <- pam_validation_sample(pool, "stratified", bands, n_per_cell = 3, species = "bus cus")
  expect_equal(unique(sp$scientific_name), "Bus cus")
  expect_equal(nrow(pam_validation_sample(pool, "random", bands, n = 1000)), nrow(pool))
})

test_that("draw adds rounds without repeating events", {
  root <- tempfile(); dir.create(root); cfg <- mk_cfg(root); pool <- make_pool()
  n1 <- suppressMessages(pam_validation_draw(cfg, "t", "stratified", pool = pool))
  n2 <- suppressMessages(pam_validation_draw(cfg, "t", "stratified", pool = pool))
  all_s <- data.table::fread(file.path(cfg$paths$detections, "t", "validation",
                                       "validation_samples.csv"))
  expect_equal(nrow(all_s), nrow(n1) + nrow(n2))
  expect_equal(anyDuplicated(all_s$event_id), 0)
  expect_equal(all_s$sample_id, seq_len(nrow(all_s)))
  expect_equal(sort(unique(all_s$round)), c(1, 2))
  expect_true(all(all_s$clip_start_s >= 0))
})

test_that("export creates clips and spectrograms and is incremental", {
  skip_if(!have_ffmpeg(), "ffmpeg not installed")
  root <- tempfile(); dir.create(root); cfg <- mk_cfg(root)
  make_source(file.path(cfg$paths$audio_standardized, "G_0001", "test.wav"))
  suppressMessages(pam_validation_draw(cfg, "t", "rare", pool = make_pool()))
  res <- suppressMessages(pam_validation_export(cfg, "t"))
  expect_equal(res$n_failed, 0)
  vd <- file.path(cfg$paths$detections, "t", "validation")
  s <- data.table::fread(file.path(vd, "validation_samples.csv"))
  expect_true(all(file.exists(file.path(vd, "clips", s$clip_file))))
  expect_true(all(file.exists(file.path(vd, "spectrograms", s$spec_file))))
  expect_equal(suppressMessages(pam_validation_export(cfg, "t"))$n_ok, 0)
})

test_that("a missing source file is reported, not fatal", {
  skip_if(!have_ffmpeg(), "ffmpeg not installed")
  root <- tempfile(); dir.create(root); cfg <- mk_cfg(root)
  suppressMessages(pam_validation_draw(cfg, "t", "rare", pool = make_pool()))
  res <- suppressMessages(pam_validation_export(cfg, "t"))
  expect_equal(res$n_ok, 0)
  expect_gt(res$n_failed, 0)
})

test_that("wilson interval", {
  ci <- pam_wilson_ci(c(18, 5, 0), c(25, 5, 0))
  expect_equal(round(ci$low[1], 3), 0.524)
  expect_equal(round(ci$high[1], 3), 0.857)
  expect_equal(round(ci$low[2], 3), 0.566)
  expect_true(is.na(ci$low[3]))
})

test_that("metrics weight cells by pool size", {
  pool <- data.table::data.table(scientific_name = "Aus bus",
                                 confidence = c(rep(0.35, 80), rep(0.8, 20)))
  val <- data.table::data.table(
    scientific_name = "Aus bus", confidence = c(rep(0.35, 10), rep(0.8, 10)),
    verdict = c(rep("correct", 2), rep("incorrect", 8), rep("correct", 9), "incorrect"),
    true_species = c(rep("", 2), rep("Bus cus_B", 5), rep("", 3), rep("", 10)))
  m <- pam_validation_metrics(val, pool, bands)
  expect_equal(m$cells[band_idx == 1, precision], 0.2)
  expect_equal(m$cells[band_idx == 4, precision], 0.9)
  t_all <- m$thresholds[scientific_name == "ALL"]
  expect_equal(t_all[min_confidence == 0.3, precision_est], (80 * 0.2 + 20 * 0.9) / 100)
  expect_equal(t_all[min_confidence == 0.7, precision_est], 0.9)
  expect_equal(t_all[min_confidence == 0.4, coverage], 1)
  expect_equal(m$confusion[true_species == "Bus cus_B", N], 5)
  expect_equal(m$confusion[true_species == "(not given)", N], 4)
})

test_that("unsure verdicts are excluded from precision", {
  pool <- data.table::data.table(scientific_name = "Aus bus", confidence = rep(0.35, 10))
  val <- data.table::data.table(
    scientific_name = "Aus bus", confidence = rep(0.35, 6), true_species = "",
    verdict = c("correct", "correct", "incorrect", "unsure", "unsure", "unsure"))
  m <- pam_validation_metrics(val, pool, bands)
  expect_equal(m$cells$n_judged, 3)
  expect_equal(m$cells$n_unsure, 3)
  expect_equal(m$cells$precision, 2 / 3)
})

test_that("shiny app saves verdicts and resumes", {
  skip_if_not_installed("shiny")
  skip_if(!have_ffmpeg(), "ffmpeg not installed")
  root <- tempfile(); dir.create(root); cfg <- mk_cfg(root)
  make_source(file.path(cfg$paths$audio_standardized, "G_0001", "test.wav"))
  suppressMessages(pam_validation_draw(cfg, "t", "rare", pool = make_pool()))
  suppressMessages(pam_validation_export(cfg, "t"))
  rp <- file.path(cfg$paths$detections, "t", "validation", "validation_results.csv")
  read_res <- function() data.table::fread(rp, colClasses = list(
    character = c("verdict", "true_species", "note", "reviewer", "reviewed_at")))

  shiny::testServer(pam_validation_app(cfg, "t", reviewer = "me"), {
    session$setInputs(verdict = "correct", true_species = "", note = "", reviewer = "me", save = 1)
    session$setInputs(verdict = "incorrect", true_species = "Bus cus_B", note = "x",
                      reviewer = "me", save = 2)
    session$setInputs(verdict = "unsure", true_species = "", note = "", reviewer = "me", save = 3)
  })
  r <- read_res()
  expect_equal(nrow(r), 3)
  expect_setequal(r$verdict, c("correct", "incorrect", "unsure"))
  expect_equal(r[verdict == "incorrect", true_species], "Bus cus_B")
  expect_equal(anyDuplicated(r$sample_id), 0)

  shiny::testServer(pam_validation_app(cfg, "t"), {
    session$setInputs(verdict = "correct", true_species = "", note = "", reviewer = "me", save = 1)
  })
  r2 <- read_res()
  expect_equal(nrow(r2), 4)                  # a new session resumed at an unreviewed sample
  expect_equal(anyDuplicated(r2$sample_id), 0)
})
