test_that("the example project has the documented files and a valid config", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  expect_named(ex, c("root", "config", "cfg", "audio_dir", "files", "deployments", "detections"))
  expect_true(file.exists(ex$detections))
  expect_length(ex$files, 6L)
  expect_true(all(file.exists(ex$files)))
  expect_true(file.exists(ex$config))
  expect_true(file.exists(ex$deployments))
  expect_s3_class(ex$cfg, "pam_config")
  expect_equal(ex$cfg$birdnet$run_id, "run01")
  expect_equal(sort(unique(basename(dirname(ex$files)))), c("G0059", "G0110"))
})

test_that("the default folder is temporary and an existing non-empty folder is refused", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  expect_true(startsWith(normalizePath(ex$root, winslash = "/"),
                         normalizePath(tempdir(), winslash = "/")))
  expect_error(pam_example_project(ex$root), "not empty")
  expect_error(pam_example_project(NA_character_), "single folder path")
  expect_error(pam_example_project(c("a", "b")), "single folder path")
  empty <- withr::local_tempdir()
  expect_no_error(pam_example_project(empty))
})

test_that("the example audio is readable and as documented", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  info <- pam_audio_info(ex$files)
  expect_true(all(info$readable))
  expect_true(all(info$sample_rate == 8000L))
  expect_true(all(info$channels == 1L))
  expect_equal(info$duration_s, rep(2, 6))
})

test_that("a scan of the example project finds every file inside its deployment and no problems", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  expect_equal(nrow(res$master), 6L)
  expect_true(all(res$master$valid_name))
  expect_true(all(res$master$in_deployment))
  expect_true(all(res$master$qc_pass))
  expect_equal(res$summary$overall$n_files, 6L)
  expect_equal(res$summary$overall$n_grids, 2L)
  expect_equal(nrow(pam_check_deployments(res$deployments)), 0L)
  expect_equal(sort(res$deployments$grid), c("G0059", "G0110"))
})

test_that("the help-page examples for the audio, parsing and checkpoint helpers give the documented results", {
  expect_equal(pam_audio_exts(), c("wav", "flac"))
  expect_equal(grepl(pam_audio_pattern(), c("a.wav", "b.FLAC", "c.mp3")), c(TRUE, TRUE, FALSE))
  expect_equal(pam_is_flac(c("a.flac", "b.wav")), c(TRUE, FALSE))
  expect_equal(pam_extract_grid("G0059_20260405_183000.wav"), "G0059")
  expect_equal(pam_extract_grid("recording.wav"), "unassigned")
  expect_equal(pam_parse_datetime("G0059_20260405_183000.wav"), "20260405_183000")
  expect_equal(pam_parse_datetime("SM4_260405183000.wav"), "20260405_183000")

  ckpt <- withr::local_tempfile(fileext = ".txt")
  ids <- c("a.wav", "b.wav", "c.wav")
  expect_length(pam_pending_batches(ids, ckpt, batch_size = 2), 2L)
  pam_checkpoint_add("a.wav", ckpt)
  expect_equal(unname(unlist(pam_pending_batches(ids, ckpt, batch_size = 2))), c("b.wav", "c.wav"))
})

test_that("pam_run_stage example: a failing stage returns a failed status", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  res <- suppressMessages(pam_run_stage("demo", function(cfg, x) x * 2, ex$cfg, x = 21))
  expect_equal(res$status, "ok")
  expect_equal(res$result, 42)
  bad <- suppressMessages(pam_run_stage("demo_fail", function(cfg) stop("boom"), ex$cfg))
  expect_equal(bad$status, "failed")
})

test_that("pam_config_validate example: an out-of-range confidence is rejected", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  bad <- ex$cfg
  bad$birdnet$min_confidence <- 2
  expect_error(pam_config_validate(bad), "min_confidence")
})

# ---- detection stages, validation, recall and occupancy on the example project ----------

scan_example <- function() {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = parent.frame())
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  list(ex = ex, res = res)
}

test_that("assembling the example detections drops the one duplicate row", {
  s <- scan_example()
  raw <- utils::read.csv(s$ex$detections)
  det <- suppressMessages(pam_assemble_detections(s$ex$cfg))
  expect_equal(nrow(raw), 20L)
  expect_equal(nrow(det), 19L)
  expect_true(all(det$in_deployment))
})

test_that("cleaning the example detections removes the window past the end and the low-confidence rows", {
  s <- scan_example()
  out <- suppressMessages(pam_process_detections(s$ex$cfg))
  expect_equal(nrow(out$clean), 10L)
  expect_equal(nrow(out$removed), 4L)
  expect_setequal(out$removed$reason, c("beyond end of recording", "below confidence threshold"))
  expect_equal(max(out$clean$n_windows), 2L)          # overlapping parakeet windows merge
  expect_true(file.exists(file.path(s$ex$cfg$paths$detections, "run01", "processed",
                                    "detections_clean.csv")))
})

test_that("the validation examples work end to end", {
  s <- scan_example(); cfg <- s$ex$cfg
  pool <- suppressMessages(pam_validation_pool(cfg))
  expect_equal(nrow(pool), 12L)
  bands <- unlist(cfg$validation$bands)
  smp <- pam_validation_sample(pool, "stratified", bands = bands, n_per_cell = 1)
  expect_true(all(table(smp$scientific_name, smp$band) <= 1L))
  new <- suppressMessages(pam_validation_draw(cfg, strategy = "random", n = 8))
  expect_equal(nrow(new), 8L)
  val_dir <- file.path(cfg$paths$detections, "run01", "validation")
  results <- data.frame(sample_id = new$sample_id,
                        verdict = rep_len(c("correct", "correct", "incorrect"), nrow(new)),
                        true_species = NA_character_, note = "", reviewer = "example",
                        reviewed_at = format(Sys.time()), stringsAsFactors = FALSE)
  utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)
  val <- pam_validation_import(cfg)
  expect_equal(nrow(val), 8L)
  metrics <- pam_validation_metrics(val, pool, bands = bands)
  expect_true(all(c("cells", "thresholds") %in% names(metrics)))
  expect_equal(sum(metrics$cells$n_reviewed), 8L)
})

test_that("the recall examples work end to end", {
  s <- scan_example(); cfg <- s$ex$cfg
  master <- s$res$master
  master$rel <- file.path(master$grid, master$file_name)
  master$recording_start <- master$start_time
  frame <- pam_recall_frame(master, segment_s = 1)
  expect_equal(nrow(frame), 12L)
  expect_equal(nrow(pam_recall_sample(frame, n = 3, seed = 1)), 3L)
  segments <- suppressMessages(pam_recall_draw(cfg, n = 12, run_id = NULL))
  expect_equal(nrow(segments), 12L)
  events <- suppressMessages(pam_validation_pool(cfg))
  truth <- data.table::data.table(segment_id = segments$segment_id,
                                  present = "Psittacula longicauda_Long-tailed Parakeet",
                                  possible = NA_character_)
  m <- as.data.frame(pam_recall_metrics(truth, segments, events, thresholds = c(0.3, 0.5)))
  all_rows <- m[m$scientific_name == "ALL", ]
  expect_equal(nrow(all_rows), 2L)
  expect_true(all(all_rows$n_present == 12L))
})

test_that("occupancy histories are built from the cleaned example detections", {
  s <- scan_example(); cfg <- s$ex$cfg
  suppressMessages(pam_process_detections(cfg))
  occ <- suppressMessages(pam_build_occupancy(cfg))
  expect_setequal(names(occ$histories),
                  c("Psittacula longicauda_Long-tailed Parakeet",
                    "Ducula nicobarica_Nicobar Imperial-Pigeon",
                    "Gracula religiosa_Common Hill Myna"))
  expect_equal(unique(occ$summary$n_sites), 2L)
  expect_equal(unique(occ$summary$n_occasions), 2L)
  parakeet <- occ$histories[["Psittacula longicauda_Long-tailed Parakeet"]]
  expect_equal(sort(parakeet$site_id), c("G0059", "G0110"))
})

# ---- batch C: raw inspection, reports, and the FFmpeg-based examples -----------------------

test_that("inspecting the example audio and a standardize dry run need no extra software", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  insp <- suppressMessages(pam_inspect_raw(ex$audio_dir, min_duration_s = 1))
  expect_equal(nrow(insp), 6L)
  expect_true(all(insp$category == "standardizable"))
  demo <- withr::local_tempdir()
  plan <- suppressMessages(pam_standardize(
    ex$cfg, raw_dir = ex$audio_dir, standardized_dir = file.path(demo, "standardized"),
    isolated_dir = file.path(demo, "isolated"), dry_run = TRUE,
    target_format = "wav", min_duration_s = 1))
  expect_equal(nrow(plan), 6L)
  expect_true(all(plan$action == "PLANNED_COPY_COMPLIANT"))
  expect_false(dir.exists(file.path(demo, "standardized")))     # a dry run writes nothing
})

test_that("the validation and recall reports run on the example project", {
  s <- scan_example(); cfg <- s$ex$cfg
  suppressMessages(pam_process_detections(cfg))
  new <- suppressMessages(pam_validation_draw(cfg, strategy = "random", n = 8))
  val_dir <- file.path(cfg$paths$detections, "run01", "validation")
  results <- data.frame(sample_id = new$sample_id,
                        verdict = rep_len(c("correct", "correct", "incorrect"), nrow(new)),
                        true_species = NA_character_, note = "", reviewer = "example",
                        reviewed_at = format(Sys.time()), stringsAsFactors = FALSE)
  utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)
  metrics <- suppressMessages(pam_validation_report(cfg))
  expect_true(file.exists(file.path(val_dir, "precision_by_cell.csv")))
  expect_true(file.exists(file.path(val_dir, "precision_by_threshold.csv")))
  expect_equal(sum(metrics$cells$n_reviewed), 8L)

  segments <- suppressMessages(pam_recall_draw(cfg, n = 12, run_id = NULL))
  gt_dir <- file.path(cfg$paths$validation, "ground_truth")
  truth <- data.frame(segment_id = segments$segment_id,
                      present = "Psittacula longicauda_Long-tailed Parakeet",
                      possible = "", other = "", none_audible = FALSE, note = "",
                      reviewer = "example", reviewed_at = format(Sys.time()),
                      stringsAsFactors = FALSE)
  utils::write.csv(truth, file.path(gt_dir, "recall_annotations.csv"), row.names = FALSE)
  rep <- suppressMessages(pam_recall_report(cfg))
  expect_equal(rep$n_segments, 12L)
  expect_true(file.exists(file.path(val_dir, "recall_by_species_threshold.csv")))
})

test_that("the FFmpeg-based examples work when FFmpeg is installed", {
  skip_if(!nzchar(Sys.which("ffmpeg")), "FFmpeg is not installed")
  s <- scan_example(); cfg <- s$ex$cfg
  expect_true(nzchar(pam_check_ffmpeg("ffmpeg", pam_highpass_filter_string(250, 8))))
  item <- list(input = s$ex$files[1], output = withr::local_tempfile(fileext = ".wav"), bits = 16)
  expect_true(pam_filter_one(item, pam_highpass_filter_string(250, 8))$ok)
  out <- suppressMessages(pam_filter_audio(cfg))
  expect_equal(out$n_ok, 6L)
  expect_equal(out$n_failed, 0L)
  new <- suppressMessages(pam_validation_draw(cfg, strategy = "random", n = 3))
  exp <- suppressMessages(pam_validation_export(cfg))
  expect_equal(exp$n_ok, 3L)
  seg <- suppressMessages(pam_recall_draw(cfg, n = 3, run_id = NULL))
  gt <- suppressMessages(pam_recall_export(cfg))
  expect_equal(gt$n_ok, 3L)
})
