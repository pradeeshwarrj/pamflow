tz <- "Asia/Kolkata"

mk_master <- function() {
  t0 <- as.POSIXct("2026-04-10 03:30:00", tz = tz)
  data.table::data.table(
    rel = c("A.wav", "B.wav", "C.wav", "D.wav"), grid = "G1", recording_start = t0,
    duration_s = c(3600, 125, 3600, 3600),
    qc_pass = c(TRUE, TRUE, TRUE, FALSE), in_deployment = c(TRUE, TRUE, FALSE, TRUE))
}

mk_cfg_gt <- function(root, seg_s = 60) {
  list(paths = list(metadata = file.path(root, "meta"), validation = file.path(root, "val"),
                    detections = file.path(root, "det"), logs = file.path(root, "logs"),
                    audio_standardized = file.path(root, "audio"),
                    filtered = file.path(root, "filt")),
       filenames = list(timezone = tz), birdnet = list(run_id = "t"),
       filter = list(ffmpeg_path = "ffmpeg"),
       validation = list(bands = list(0.3, 0.4, 0.5, 0.7, 1.0)),
       recall = list(segment_s = seg_s, n_segments = 5, hours = list(), audio = "standardized",
                     spec_px = list(1600, 400), spec_max_hz = 12000, seed = 1))
}

write_master_gt <- function(cfg, rels, dur) {
  dir.create(cfg$paths$metadata, recursive = TRUE)
  data.table::fwrite(
    data.table::data.table(file_path = file.path(cfg$paths$audio_standardized, rels), grid = "G1",
                           duration_s = dur, start_time = "2026-04-10T00:00:00Z",
                           qc_pass = TRUE, in_deployment = TRUE),
    file.path(cfg$paths$metadata, "audio_master.csv"))
}

make_source_gt <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  sr <- 16000; t <- seq_len(60 * sr) / sr
  x <- 0.3 * sin(2 * pi * 3000 * t) * ((t %% 7) < 2)
  tuneR::writeWave(tuneR::Wave(left = as.integer(round(x * 32767)), samp.rate = sr, bit = 16), path)
}

have_ffmpeg_gt <- function() nzchar(unname(Sys.which("ffmpeg")))

test_that("frame cuts full segments from eligible files only", {
  f <- pam_recall_frame(mk_master(), 60)
  expect_equal(nrow(f), 62)
  expect_setequal(unique(f$rel), c("A.wav", "B.wav"))
  expect_equal(f[rel == "B.wav", seg_start], c(0, 60))
  expect_equal(anyDuplicated(f$seg_key), 0)
  h <- pam_recall_frame(mk_master(), 60, hours = c(4, 5))
  expect_true(all(h$hour == 4))
  expect_equal(nrow(h[rel == "A.wav"]), 30)
  expect_error(pam_recall_frame(mk_master()[rel == "C.wav"], 60), "No eligible")
})

test_that("sampling is reproducible and never repeats a segment", {
  f <- pam_recall_frame(mk_master(), 60)
  s1 <- pam_recall_sample(f, 10, seed = 1)
  expect_equal(s1$seg_key, pam_recall_sample(f, 10, seed = 1)$seg_key)
  s2 <- pam_recall_sample(f, 10, seed = 2, exclude_keys = s1$seg_key)
  expect_length(intersect(s1$seg_key, s2$seg_key), 0)
  expect_equal(nrow(pam_recall_sample(f, 1000)), nrow(f))
})

test_that("draw adds rounds, honours the run's processed files, never repeats", {
  root <- tempfile(); dir.create(root); cfg <- mk_cfg_gt(root)
  write_master_gt(cfg, c("G_1/x.wav", "G_1/y.wav"), c(600, 600))
  dir.create(file.path(cfg$paths$detections, "t"), recursive = TRUE)
  data.table::fwrite(data.table::data.table(rel = "G_1/x.wav", ok = TRUE),
                     file.path(cfg$paths$detections, "t", "file_results.csv"))
  suppressMessages(pam_recall_draw(cfg, 6, "t"))
  suppressMessages(pam_recall_draw(cfg, 6, "t"))
  all_s <- data.table::fread(file.path(root, "val", "ground_truth", "recall_segments.csv"))
  expect_equal(unique(all_s$rel), "G_1/x.wav")      # y.wav was not processed by the run
  expect_equal(nrow(all_s), 10)                     # only 10 segments exist in x.wav
  expect_equal(anyDuplicated(all_s$seg_key), 0)
  expect_equal(all_s$segment_id, 1:10)
  expect_equal(unique(all_s$hour), 5)               # 00:00 UTC is 05:30 local
})

test_that("export makes segment clips and spectrograms", {
  skip_if(!have_ffmpeg_gt(), "ffmpeg not installed")
  root <- tempfile(); dir.create(root); cfg <- mk_cfg_gt(root, seg_s = 20)
  write_master_gt(cfg, "G_1/x.wav", 60)
  make_source_gt(file.path(cfg$paths$audio_standardized, "G_1", "x.wav"))
  suppressMessages(pam_recall_draw(cfg, 3, NULL))
  res <- suppressMessages(pam_recall_export(cfg))
  expect_equal(res$n_failed, 0)
  gt <- file.path(root, "val", "ground_truth")
  s <- data.table::fread(file.path(gt, "recall_segments.csv"))
  expect_true(all(file.exists(file.path(gt, "clips", s$clip_file))))
  expect_true(all(file.exists(file.path(gt, "spectrograms", s$spec_file))))
  expect_equal(suppressMessages(pam_recall_export(cfg))$n_ok, 0)
})

test_that("recall metrics match a hand calculation", {
  segs <- data.table::data.table(segment_id = 1:4, rel = "f1",
                                 seg_start = c(0, 60, 120, 180), seg_end = c(60, 120, 180, 240))
  truth <- data.table::data.table(
    segment_id = 1:4, present = c("Aus a_X;Bus b_Y", "Aus a_X", "", "Bus b_Y"),
    possible = c("", "", "", "Aus a_X"), other = "", none_audible = c(FALSE, FALSE, TRUE, FALSE))
  ev <- data.table::data.table(
    rel = "f1", scientific_name = c("Aus a", "Bus b", "Aus a", "Bus b", "Aus a"),
    start_time = c(10, 20, 130, 190, 200), end_time = c(13, 23, 133, 193, 203),
    confidence = c(0.9, 0.35, 0.4, 0.8, 0.6))
  m <- pam_recall_metrics(truth, segs, ev, classes = c("Aus a", "Bus b"), thresholds = c(0.3, 0.5))
  g <- function(sp, th) m[scientific_name == sp & threshold == th]
  cnt <- function(x) unlist(x[, .(tp, fn, fp, tn)])
  expect_equal(cnt(g("Aus a", 0.3)), c(tp = 1, fn = 1, fp = 1, tn = 0))
  expect_equal(cnt(g("Bus b", 0.3)), c(tp = 2, fn = 0, fp = 0, tn = 2))
  expect_equal(cnt(g("ALL", 0.3)), c(tp = 3, fn = 1, fp = 1, tn = 2))
  expect_equal(g("ALL", 0.3)$recall, 0.75)
  expect_equal(g("ALL", 0.3)$precision, 0.75)
  expect_equal(g("ALL", 0.3)$f1, 0.75)
  expect_equal(cnt(g("Aus a", 0.5)), c(tp = 1, fn = 1, fp = 0, tn = 1))
  expect_equal(cnt(g("Bus b", 0.5)), c(tp = 1, fn = 1, fp = 0, tn = 2))
  expect_equal(g("ALL", 0.5)$recall, 0.5)
  expect_equal(g("ALL", 0.5)$n_present, 4)
})

test_that("events outside a segment do not count and boundaries are exclusive", {
  segs <- data.table::data.table(segment_id = 1L, rel = "f1", seg_start = 60, seg_end = 120)
  truth <- data.table::data.table(segment_id = 1L, present = "", possible = "", other = "",
                                  none_audible = TRUE)
  ev <- data.table::data.table(rel = "f1", scientific_name = "Aus a",
                               start_time = c(57, 120, 30), end_time = c(60, 123, 40),
                               confidence = 0.9)
  m <- pam_recall_metrics(truth, segs, ev, classes = "Aus a", thresholds = 0.3)
  expect_equal(m[scientific_name == "Aus a", fp], 0)       # touching the boundary is not overlap
  ev2 <- data.table::data.table(rel = "f1", scientific_name = "Aus a",
                                start_time = 118, end_time = 121, confidence = 0.9)
  m2 <- pam_recall_metrics(truth, segs, ev2, classes = "Aus a", thresholds = 0.3)
  expect_equal(m2[scientific_name == "Aus a", fp], 1)      # straddling the end does overlap
})

test_that("annotation app saves, validates and resumes", {
  skip_if_not_installed("shiny")
  skip_if(!have_ffmpeg_gt(), "ffmpeg not installed")
  root <- tempfile(); dir.create(root); cfg <- mk_cfg_gt(root, seg_s = 20)
  write_master_gt(cfg, "G_1/x.wav", 60)
  make_source_gt(file.path(cfg$paths$audio_standardized, "G_1", "x.wav"))
  suppressMessages(pam_recall_draw(cfg, 3, NULL))
  suppressMessages(pam_recall_export(cfg))
  rp <- file.path(root, "val", "ground_truth", "recall_annotations.csv")
  read_res <- function() data.table::fread(rp, colClasses = list(
    character = c("present", "possible", "other", "note", "reviewer", "reviewed_at")))

  shiny::testServer(pam_annotation_app(cfg, "me"), {
    # nothing chosen: rejected
    session$setInputs(present = NULL, possible = NULL, other = "", none = FALSE, note = "",
                      reviewer = "me", save = 1)
    # contradiction: rejected
    session$setInputs(present = "Aus a_X", possible = "Bus b_Y", other = "", none = TRUE,
                      note = "", reviewer = "me", save = 2)
    session$setInputs(present = c("Aus a_X", "Bus b_Y"), possible = character(0),
                      other = "mystery frog", none = FALSE, note = "n", reviewer = "me", save = 3)
    session$setInputs(present = character(0), possible = character(0), other = "", none = TRUE,
                      note = "", reviewer = "me", save = 4)
  })
  r <- read_res()
  expect_equal(nrow(r), 2)
  expect_setequal(r$present, c("Aus a_X;Bus b_Y", ""))
  expect_equal(r[present != "", other], "mystery frog")
  expect_true(r[present == "", none_audible])

  shiny::testServer(pam_annotation_app(cfg), {
    session$setInputs(present = "Aus a_X", possible = character(0), other = "", none = FALSE,
                      note = "", reviewer = "me", save = 1)
  })
  r2 <- read_res()
  expect_equal(nrow(r2), 3)                         # a new session resumed at an unannotated segment
  expect_equal(anyDuplicated(r2$segment_id), 0)
})
