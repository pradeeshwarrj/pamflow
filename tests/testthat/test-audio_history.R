history_project <- function(env = parent.frame()) {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = env)
  suppressMessages(pam_scan_audio(ex$cfg))
  ex
}

test_that("after a scan every file has one Stage 1 row", {
  ex <- history_project()
  h <- pam_audio_history(ex$cfg)
  expect_s3_class(h, "data.table")
  expect_named(h, c("rel", "file", "stage", "run_id", "status", "detail", "n", "time"))
  expect_equal(nrow(h), 6L)
  expect_true(all(h$stage == "1 scan"))
  expect_true(all(h$status == "pass"))
  expect_true(all(grepl("deployment", h$detail)))
  expect_equal(attr(h, "stages_found"), "1 scan")
})

test_that("a project with no stage outputs gives an empty table and a warning", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  expect_warning(h <- pam_audio_history(ex$cfg), "No stage outputs")
  expect_equal(nrow(h), 0L)
  expect_error(pam_audio_history(list()), "pamflow configuration")
})

test_that("the history follows a file through cleaning, validation, recall and occupancy", {
  ex <- history_project(); cfg <- ex$cfg
  suppressMessages(pam_process_detections(cfg))

  new <- suppressMessages(pam_validation_draw(cfg, strategy = "random", n = 8))
  val_dir <- file.path(cfg$paths$detections, "run01", "validation")
  results <- data.frame(sample_id = new$sample_id,
                        verdict = rep_len(c("correct", "incorrect"), nrow(new)),
                        true_species = NA_character_, note = "", reviewer = "example",
                        reviewed_at = "2026-04-10 12:00:00", stringsAsFactors = FALSE)
  utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)

  seg <- suppressMessages(pam_recall_draw(cfg, n = 12, run_id = NULL))
  truth <- data.frame(segment_id = seg$segment_id[1:6], present = "x", possible = "", other = "",
                      none_audible = FALSE, note = "", reviewer = "example",
                      reviewed_at = "2026-04-10 12:00:00", stringsAsFactors = FALSE)
  utils::write.csv(truth, file.path(cfg$paths$validation, "ground_truth", "recall_annotations.csv"),
                   row.names = FALSE)
  suppressMessages(pam_build_occupancy(cfg))

  h <- pam_audio_history(cfg)
  expect_setequal(attr(h, "stages_found"),
                  c("1 scan", "4 process", "5 validation", "5b recall", "6 occupancy"))

  third <- "G0059/G0059_20260405_183004.wav"
  detail <- h$detail[h$rel == third & h$stage == "4 process"]
  expect_match(detail, "beyond end of recording \\(1\\)")

  w <- pam_audio_history(cfg, wide = TRUE)
  expect_equal(nrow(w), 6L)
  expect_true(all(c("rel", "1 scan", "4 process [run01]", "5 validation [run01]",
                    "5b recall", "6 occupancy [run01]") %in% names(w)))
  expect_equal(w[["4 process [run01]"]][w$rel == "G0110/G0110_20260406_060004.wav"], "removed")
  expect_true(all(w[["6 occupancy [run01]"]] == "included"))
  expect_true(any(w[["5 validation [run01]"]] %in% "reviewed"))
  expect_true(all(w[["5b recall"]] %in% c("drawn", "partly annotated", "annotated")))
})

test_that("a single file can be looked up by name or by path", {
  ex <- history_project(); cfg <- ex$cfg
  suppressMessages(pam_process_detections(cfg))
  by_name <- pam_audio_history(cfg, file = "G0059_20260405_183004.wav")
  by_path <- pam_audio_history(cfg, file = "G0059/G0059_20260405_183004.wav")
  expect_true(all(by_name$rel == "G0059/G0059_20260405_183004.wav"))
  expect_equal(by_name$stage, by_path$stage)
  expect_setequal(by_name$stage, c("1 scan", "4 process"))
  expect_equal(nrow(pam_audio_history(cfg, file = "no_such_file.wav")), 0L)
})

test_that("Stage 0 rows link a standardized file to its raw file and keep set-aside files", {
  ex <- history_project(); cfg <- ex$cfg
  log <- data.frame(
    source_path = c("raw/rec_001.wav", "raw/memo.wav"),
    dest_path = c(ex$files[1], file.path(cfg$paths$audio_isolated, "memos", "memo.wav")),
    category = c("standardizable", "isolated_memo"),
    action = c("TRANSCODED", "ISOLATED_MEMO"), status = c("SUCCESS", "WARN"),
    message = c("Transcoded to flac", "Short audio memo moved"), stringsAsFactors = FALSE)
  utils::write.csv(log, file.path(cfg$paths$audio_standardized, "standardization_log.csv"),
                   row.names = FALSE)
  h <- pam_audio_history(cfg)
  s0 <- h[h$stage == "0 standardize", ]
  expect_equal(nrow(s0), 2L)
  expect_equal(sum(is.na(s0$rel)), 1L)
  expect_equal(s0$status[is.na(s0$rel)], "warning")
  by_raw <- pam_audio_history(cfg, file = "rec_001.wav")
  expect_true(all(by_raw$rel == "G0059/G0059_20260405_183000.wav"))
  expect_true(all(c("0 standardize", "1 scan") %in% by_raw$stage))
  expect_match(by_raw$detail[by_raw$stage == "0 standardize"], "raw/rec_001.wav")
})

test_that("filter and detection results are read, and runs can be chosen", {
  ex <- history_project(); cfg <- ex$cfg
  rels <- file.path(basename(dirname(ex$files)), basename(ex$files))
  utils::write.csv(
    data.frame(rel = rels, ok = c(rep(TRUE, 5), FALSE), verified = c(rep(TRUE, 5), FALSE),
               message = c(rep("", 5), "ffmpeg error"), stringsAsFactors = FALSE),
    file.path(cfg$paths$metadata, "02_filter_results.csv"), row.names = FALSE)
  run_dir <- file.path(cfg$paths$detections, "runA")
  dir.create(run_dir, recursive = TRUE)
  utils::write.csv(
    data.frame(rel = rels, ok = TRUE, n_detections = 1:6, seconds = 1.5, message = "",
               stringsAsFactors = FALSE),
    file.path(run_dir, "file_results.csv"), row.names = FALSE)

  h <- pam_audio_history(cfg)
  f <- h[h$stage == "2 filter", ]
  expect_equal(sum(f$status == "failed"), 1L)
  expect_match(f$detail[f$status == "failed"], "ffmpeg error")
  d <- h[h$stage == "3 detect", ]
  expect_equal(d$n[order(d$rel)], 1:6)
  expect_equal(unique(d$run_id), "runA")
  expect_match(d$detail[1], "1.5 s")

  expect_false("3 detect" %in% pam_audio_history(cfg, run_id = "other")$stage)
  expect_true("3 detect" %in% pam_audio_history(cfg, run_id = "runA")$stage)
})

test_that("write = TRUE saves the long table and nothing is written by default", {
  ex <- history_project(); cfg <- ex$cfg
  path <- file.path(cfg$paths$metadata, "audio_history.csv")
  pam_audio_history(cfg)
  expect_false(file.exists(path))
  h <- suppressMessages(pam_audio_history(cfg, write = TRUE))
  expect_true(file.exists(path))
  back <- data.table::fread(path)
  expect_equal(nrow(back), nrow(h))
  expect_true(all(c("rel", "stage", "status", "detail") %in% names(back)))
})

test_that("flags are joined without empty pieces", {
  expect_equal(pam_history_join(c("a", NA, NA), c("b", "c", NA)), c("a; b", "c", NA))
  expect_equal(pam_history_flag(c(TRUE, FALSE, NA), "x"), c("x", NA, NA))
  expect_equal(pam_history_rel(c("C:/p/audio/G1/a.wav", "C:/p/other/b.wav", NA), "C:/p/audio"),
               c("G1/a.wav", NA, NA))
  expect_equal(pam_history_rel("C:\\p\\audio\\G1\\a.wav", "C:/p/audio/"), "G1/a.wav")
})
