# test-detect.R
# Tests for Stage 3 helpers and the pam_detect() orchestration. No BirdNET and no
# Python are needed: the batch runner and the model check are replaced by fakes.
# (The batch runner itself is covered in test-detect_py.R.)

# ── helpers ──────────────────────────────────────────────────────────────────

# Create stub classifier files in a temp dir and return the dir path.
# Uses tempfile() + dir.create() so the directory outlives this helper call.
# withr::local_tempdir() as a default argument would be scoped to make_model_dir's
# own frame and deleted before pam_detect_settings() is ever called.
make_model_dir <- function(name = "MyBird") {
  dir <- tempfile(pattern = "pamflow_test_model_")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("", file.path(dir, paste0(name, ".tflite")))
  writeLines("", file.path(dir, paste0(name, "_Labels.txt")))
  dir
}

# Build a minimal birdnet cfg section pointing at stub files.
make_detect_cfg <- function(model_dir, classifier_name = "MyBird") {
  list(
    paths = list(project_root = model_dir),
    birdnet = list(
      model_dir       = model_dir,
      classifier_name = classifier_name,
      labels_file     = NULL,
      min_confidence  = 0.5,
      overlap_s       = 0,
      use_bandpass    = TRUE,
      bandpass_fmin   = 0,
      bandpass_fmax   = 15000,
      run_id          = "run01",
      workers         = 1L,
      input           = "filtered"
    )
  )
}

# ── pam_detect_settings ───────────────────────────────────────────────────────

test_that("pam_detect_settings: valid config resolves model paths", {
  d   <- make_model_dir()
  cfg <- make_detect_cfg(d, "MyBird")

  s <- pamflow:::pam_detect_settings(cfg)

  expect_type(s, "list")
  expect_true(file.exists(s$model_file))
  expect_true(file.exists(s$labels_file))
  expect_equal(s$classifier_name, "MyBird")
  expect_equal(s$min_confidence, 0.5)
})

test_that("pam_detect_settings: accepts name with .tflite extension", {
  d   <- make_model_dir(name = "MyBird")
  cfg <- make_detect_cfg(d, "MyBird.tflite")   # extension supplied

  s <- pamflow:::pam_detect_settings(cfg)

  expect_equal(s$classifier_name, "MyBird")   # extension stripped
  expect_true(file.exists(s$model_file))
})

test_that("pam_detect_settings: missing model_dir aborts", {
  cfg <- make_detect_cfg("/nonexistent/path_XYZ")
  expect_error(pamflow:::pam_detect_settings(cfg),
               "Custom classifier folder not found")
})

test_that("pam_detect_settings: missing .tflite file aborts", {
  d   <- withr::local_tempdir()
  # Only create the labels file, not the model
  writeLines("", file.path(d, "MyBird_Labels.txt"))
  cfg <- make_detect_cfg(d, "MyBird")

  expect_error(pamflow:::pam_detect_settings(cfg),
               "Custom classifier files not found")
})

test_that("pam_detect_settings: missing labels file aborts", {
  d   <- withr::local_tempdir()
  # Only create the model, not the labels
  writeLines("", file.path(d, "MyBird.tflite"))
  cfg <- make_detect_cfg(d, "MyBird")

  expect_error(pamflow:::pam_detect_settings(cfg),
               "Custom classifier files not found")
})

# ── pam_checkpoint_read / pam_checkpoint_add / pam_pending_batches ───────────
# (checkpoint.R is tested in test-checkpoint.R; add edge-case coverage here)

test_that("pam_checkpoint_read: nonexistent file returns empty character", {
  expect_equal(pam_checkpoint_read(tempfile()), character())
})

test_that("pam_pending_batches: no pending returns empty list", {
  ck  <- tempfile()
  ids <- c("a", "b", "c")
  pam_checkpoint_add(ids, ck)
  b <- pam_pending_batches(ids, ck, batch_size = 2L)
  expect_equal(length(b), 0L)
})

test_that("pam_pending_batches: batch_size controls split", {
  ck  <- tempfile()
  ids <- letters[1:10]
  pam_checkpoint_add(ids[1:4], ck)   # first 4 done
  b <- pam_pending_batches(ids, ck, batch_size = 3L)
  # 6 remaining, batch_size 3 → 2 batches
  expect_length(b, 2L)
  expect_equal(length(b[[1]]), 3L)
  expect_equal(length(b[[2]]), 3L)
})
# ── pam_birdnet_normalise ─────────────────────────────────────────────────────

test_that("pam_birdnet_normalise: handles legacy column layout", {
  legacy <- data.frame(
    start         = 0,
    end           = 3,
    scientific_name = "Turdus merula",
    common_name   = "Common Blackbird",
    confidence    = 0.92,
    stringsAsFactors = FALSE
  )
  out <- pamflow:::pam_birdnet_normalise(legacy)
  expect_equal(out$start_s, 0)
  expect_equal(out$end_s, 3)
  expect_equal(out$scientific_name, "Turdus merula")
  expect_equal(out$common_name, "Common Blackbird")
  expect_equal(out$confidence, 0.92)
})

test_that("pam_birdnet_normalise: handles new column layout (species_name as Sci_Common)", {
  # birdnetR new format: "Scientific Name_Common Name"
  # Spaces allowed inside the scientific name; single underscore is the separator.
  modern <- data.frame(
    start_time   = 0,
    end_time     = 3,
    species_name = "Turdus merula_Common Blackbird",
    confidence   = 0.92,
    stringsAsFactors = FALSE
  )
  out <- pamflow:::pam_birdnet_normalise(modern)
  expect_equal(out$start_s, 0)
  expect_equal(out$end_s, 3)
  expect_equal(out$scientific_name, "Turdus merula")
  expect_equal(out$common_name, "Common Blackbird")
  expect_equal(out$confidence, 0.92)
})

test_that("pam_birdnet_normalise: species_name with no underscore sets common_name to NA", {
  df <- data.frame(
    start_time   = 0,
    end_time     = 3,
    species_name = "Unknown",
    confidence   = 0.5,
    stringsAsFactors = FALSE
  )
  out <- pamflow:::pam_birdnet_normalise(df)
  expect_equal(out$scientific_name, "Unknown")
  expect_true(is.na(out$common_name))
})

test_that("pam_birdnet_normalise: empty data frame returns typed empty frame", {
  emp <- data.frame(start = numeric(), end = numeric(),
                    scientific_name = character(), common_name = character(),
                    confidence = numeric())
  out <- pamflow:::pam_birdnet_normalise(emp)
  expect_equal(nrow(out), 0L)
  expect_named(out, c("start_s", "end_s", "scientific_name", "common_name", "confidence"))
  expect_type(out$start_s, "double")
  expect_type(out$scientific_name, "character")
})

test_that("pam_birdnet_normalise: unrecognised columns throw an error", {
  bad <- data.frame(a = 1, b = 2, c = "x", stringsAsFactors = FALSE)
  expect_error(pamflow:::pam_birdnet_normalise(bad), "Unrecognised")
})

# ── pam_assemble_detections ───────────────────────────────────────────────────

test_that("pam_assemble_detections: aborts when no batch files exist", {
  det_dir <- withr::local_tempdir()
  run_id  <- "run01"
  # Create the run dir but NOT the batches sub-dir, so no batch files exist
  dir.create(file.path(det_dir, run_id), recursive = TRUE)

  cfg <- list(
    filenames = list(timezone = "UTC"),
    paths = list(
      detections         = det_dir,
      metadata           = withr::local_tempdir(),
      audio_standardized = withr::local_tempdir(),
      logs               = withr::local_tempdir()
    ),
    birdnet = list(run_id = run_id)
  )

  expect_error(
    pamflow:::pam_assemble_detections(cfg, run_id),
    "No detection batch files"
  )
})

test_that("pam_assemble_detections: returns detection table and writes detections.csv", {
  # ---- directory layout ----
  audio_std <- withr::local_tempdir()
  meta_dir  <- withr::local_tempdir()
  det_dir   <- withr::local_tempdir()
  log_dir   <- withr::local_tempdir()
  run_id    <- "run01"
  batch_dir <- file.path(det_dir, run_id, "batches")
  dir.create(batch_dir, recursive = TRUE)

  # ---- rel path that fs::path_rel(file_path, start = audio_std) will produce ----
  rel_path       <- file.path("GRID1", "SITE1", "recording.wav")
  full_audio_path <- file.path(audio_std, rel_path)

  # ---- batch CSV: columns expected by pam_assemble_detections ----
  data.table::fwrite(
    data.table::data.table(
      rel             = rel_path,
      start_s         = c(0.0, 5.0),
      end_s           = c(3.0, 8.0),
      scientific_name = c("Turdus merula", "Parus major"),
      common_name     = c("Common Blackbird", "Great Tit"),
      confidence      = c(0.92, 0.78)
    ),
    file.path(batch_dir, "batch_001.csv")
  )

  # ---- audio_master.csv: columns selected inside pam_assemble_detections ----
  data.table::fwrite(
    data.table::data.table(
      file_path     = full_audio_path,
      grid          = "GRID1",
      recorder      = "SM4",
      deployment_id = "D01",
      start_time    = "2024-01-01T06:00:00Z",
      in_deployment = TRUE
    ),
    file.path(meta_dir, "audio_master.csv")
  )

  cfg <- list(
    filenames = list(timezone = "UTC"),
    paths = list(
      detections         = det_dir,
      metadata           = meta_dir,
      audio_standardized = audio_std,
      logs               = log_dir
    ),
    birdnet = list(run_id = run_id)
  )

  result <- pamflow:::pam_assemble_detections(cfg, run_id)

  # ---- shape ----
  expect_s3_class(result, "data.table")
  expect_equal(nrow(result), 2L)

  # ---- required columns ----
  expect_true(all(c("filename", "species", "scientific_name", "common_name",
                    "confidence", "start_time", "end_time",
                    "site", "grid", "recorder", "deployment_id",
                    "in_deployment", "recording_date",
                    "recording_start", "detection_datetime", "rel") %in% names(result)))

  # ---- values ----
  expect_equal(result$scientific_name[1], "Turdus merula")
  expect_equal(result$grid[1], "GRID1")
  expect_equal(result$recorder[1], "SM4")

  # ---- detections.csv written to run dir ----
  expect_true(file.exists(file.path(det_dir, run_id, "detections.csv")))
})

test_that("pam_assemble_detections: removes duplicate rows across batch files", {
  audio_std <- withr::local_tempdir()
  meta_dir  <- withr::local_tempdir()
  det_dir   <- withr::local_tempdir()
  log_dir   <- withr::local_tempdir()
  run_id    <- "run01"
  batch_dir <- file.path(det_dir, run_id, "batches")
  dir.create(batch_dir, recursive = TRUE)

  rel_path        <- file.path("GRID1", "SITE1", "recording.wav")
  full_audio_path <- file.path(audio_std, rel_path)

  # Identical row in two separate batch files → should be de-duplicated to 1
  dup_row <- data.table::data.table(
    rel             = rel_path,
    start_s         = 0.0,
    end_s           = 3.0,
    scientific_name = "Turdus merula",
    common_name     = "Common Blackbird",
    confidence      = 0.92
  )
  data.table::fwrite(dup_row, file.path(batch_dir, "batch_001.csv"))
  data.table::fwrite(dup_row, file.path(batch_dir, "batch_002.csv"))

  data.table::fwrite(
    data.table::data.table(
      file_path     = full_audio_path,
      grid          = "GRID1",
      recorder      = "SM4",
      deployment_id = "D01",
      start_time    = "2024-01-01T06:00:00Z",
      in_deployment = TRUE
    ),
    file.path(meta_dir, "audio_master.csv")
  )

  cfg <- list(
    filenames = list(timezone = "UTC"),
    paths = list(
      detections         = det_dir,
      metadata           = meta_dir,
      audio_standardized = audio_std,
      logs               = log_dir
    ),
    birdnet = list(run_id = run_id)
  )

  result <- pamflow:::pam_assemble_detections(cfg, run_id)

  # Two identical rows across two batch files → de-duplicated to 1
  expect_equal(nrow(result), 1L)
})

# ── pam_detect_settings: extra path handling ─────────────────────────────────

test_that("pam_detect_settings: relative model_dir is resolved against project_root", {
  d <- make_model_dir()
  cfg <- make_detect_cfg(d)
  cfg$paths$project_root <- dirname(d)
  cfg$birdnet$model_dir <- basename(d)
  s <- pamflow:::pam_detect_settings(cfg)
  expect_equal(normalizePath(s$model_dir), normalizePath(d))
})

test_that("pam_detect_settings: explicit relative labels_file is resolved and checked", {
  d <- make_model_dir()
  cfg <- make_detect_cfg(d)
  writeLines("Aus bus_A", file.path(d, "custom_labels.txt"))
  cfg$birdnet$labels_file <- "custom_labels.txt"
  cfg$paths$project_root <- d
  s <- pamflow:::pam_detect_settings(cfg)
  expect_equal(basename(s$labels_file), "custom_labels.txt")

  cfg$birdnet$labels_file <- file.path(d, "missing_labels.txt")
  expect_error(pamflow:::pam_detect_settings(cfg), "Custom classifier files not found")
})

test_that("pam_detect_settings: the removed birdnetR engine is rejected with a clear message", {
  cfg <- make_detect_cfg(make_model_dir())
  cfg$birdnet$backend <- "birdnetR"
  expect_error(pamflow:::pam_detect_settings(cfg), "birdnetR engine was removed")
  cfg$birdnet$backend <- "birdnet"
  expect_equal(pamflow:::pam_detect_settings(cfg)$workers, 1L)
})

test_that("pam_detect_settings: NULL model_dir aborts", {
  cfg <- make_detect_cfg("x")
  cfg$birdnet$model_dir <- NULL
  expect_error(pamflow:::pam_detect_settings(cfg), "Custom classifier folder not found")
})

# ── pam_birdnet_normalise: extra layouts ──────────────────────────────────────

test_that("pam_birdnet_normalise: 'label' column is used when species_name is absent", {
  df <- data.frame(start = 1, end = 4, label = "Aus bus_Common A", confidence = 0.6,
                   stringsAsFactors = FALSE)
  out <- pamflow:::pam_birdnet_normalise(df)
  expect_equal(out$scientific_name, "Aus bus")
  expect_equal(out$common_name, "Common A")
})

test_that("pam_birdnet_normalise: scientific_name without common_name is unrecognised", {
  df <- data.frame(start = 1, end = 4, scientific_name = "Aus bus", confidence = 0.6,
                   stringsAsFactors = FALSE)
  expect_error(pamflow:::pam_birdnet_normalise(df), "Unrecognised")
})

# ── pam_detect orchestration (worker stubbed) ─────────────────────────────────

# Stand-in for pam_birdnet_run_batch_py().
fake_detect_worker <- function(items, s) {
  empty <- data.frame(start_s = numeric(), end_s = numeric(), scientific_name = character(),
                      common_name = character(), confidence = numeric(),
                      stringsAsFactors = FALSE)
  if (length(items) && isTRUE(getOption("pamtest.explode"))) stop("worker crashed")
  out <- lapply(items, function(it) {
    if (grepl("bad", it$rel)) {
      return(list(rel = it$rel, ok = FALSE, message = "decode failed", seconds = 0.1, det = empty))
    }
    det <- if (grepl("quiet", it$rel)) empty else {
      data.frame(start_s = c(0, 3), end_s = c(3, 6), scientific_name = "Aus bus",
                 common_name = "A", confidence = c(0.9, 0.8), stringsAsFactors = FALSE)
    }
    list(rel = it$rel, ok = TRUE, message = "", seconds = 0.2, det = det)
  })
  out
}

mk_detect_project <- function(rels = c("G1/a.wav", "G1/b.wav", "G1/quiet.wav", "G1/bad.wav"),
                              input = "standardized", chunk_size = 2L, workers = 1L,
                              on_disk = rels) {
  root <- tempfile("pamdet_"); dir.create(root)
  cfg <- make_detect_cfg(make_model_dir())
  cfg$paths <- c(cfg$paths, list(
    logs = file.path(root, "logs"), detections = file.path(root, "det"),
    metadata = file.path(root, "meta"), audio_standardized = file.path(root, "std"),
    filtered = file.path(root, "filt")))
  cfg$birdnet$input <- input
  cfg$birdnet$chunk_size <- chunk_size
  cfg$birdnet$workers <- workers
  in_dir <- if (identical(input, "filtered")) cfg$paths$filtered else cfg$paths$audio_standardized
  for (r in on_disk) {
    dir.create(dirname(file.path(in_dir, r)), recursive = TRUE, showWarnings = FALSE)
    file.create(file.path(in_dir, r))
  }
  list(cfg = cfg, root = root,
       master = data.table::data.table(file_path = file.path(cfg$paths$audio_standardized, rels),
                                       qc_pass = TRUE))
}

skip_if_no_detect_deps <- function() {
  skip_if_not_installed("yaml")
}

# Replace the Python batch runner and the model check, so no Python is needed.
local_fake_worker <- function(.env = parent.frame()) {
  testthat::local_mocked_bindings(
    pam_birdnet_run_batch_py = fake_detect_worker,
    pam_birdnet_py_check = function(s) list(ok = TRUE, birdnet_version = "test", message = ""),
    pam_birdnet_cleanup = function(...) invisible(data.frame(pid = integer(), killed = logical())),
    .package = "pamflow", .env = .env)
}

test_that("pam_detect: processes files, writes batches, checkpoint, results and settings", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project()
  res <- suppressMessages(pam_detect(p$cfg, master = p$master))
  expect_equal(res$n_pending, 4L)
  expect_equal(res$n_done, 3L)
  expect_equal(res$n_failed, 1L)
  expect_equal(res$n_detections, 4L)
  expect_length(list.files(file.path(res$run_dir, "batches"), pattern = "^batch_.*csv$"), 1L)
  expect_setequal(readLines(file.path(res$run_dir, "done.txt")),
                  c("G1/a.wav", "G1/b.wav", "G1/quiet.wav"))
  fr <- data.table::fread(file.path(res$run_dir, "file_results.csv"))
  expect_equal(nrow(fr), 4L)
  expect_equal(fr[rel == "G1/bad.wav", message], "decode failed")
  expect_length(list.files(res$run_dir, pattern = "^run_settings_.*yml$"), 1L)
})

test_that("pam_detect: rerun resumes with only the failed file; force starts over", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project()
  suppressMessages(pam_detect(p$cfg, master = p$master))
  res2 <- suppressMessages(pam_detect(p$cfg, master = p$master))
  expect_equal(res2$n_pending, 1L)
  expect_equal(res2$n_failed, 1L)
  res3 <- suppressMessages(pam_detect(p$cfg, master = p$master, force = TRUE))
  expect_equal(res3$n_pending, 4L)
})

test_that("pam_detect: nothing pending returns zeros without running the worker", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project(rels = c("G1/a.wav", "G1/b.wav"))
  suppressMessages(pam_detect(p$cfg, master = p$master))
  res <- suppressMessages(pam_detect(p$cfg, master = p$master))
  expect_equal(res$n_pending, 0L)
  expect_equal(res$n_detections, 0L)
})

test_that("pam_detect: QC-failed and missing files are skipped", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project(rels = c("G1/a.wav", "G1/b.wav", "G1/ghost.wav"),
                         on_disk = c("G1/a.wav", "G1/b.wav"))
  p$master[2, qc_pass := FALSE]
  res <- suppressMessages(pam_detect(p$cfg, master = p$master))
  expect_equal(res$n_pending, 1L)                    # only a.wav: b failed QC, ghost not on disk
  log_txt <- paste(readLines(file.path(p$cfg$paths$logs, "03_detect.log")), collapse = "\n")
  expect_match(log_txt, "not found")
})

test_that("pam_detect: sample_n draws a reproducible pilot subset", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project(rels = c("G1/a.wav", "G1/b.wav", "G1/c.wav", "G1/d.wav"))
  res <- suppressMessages(pam_detect(p$cfg, master = p$master, sample_n = 2, seed = 7))
  expect_equal(res$n_pending, 2L)
  done1 <- sort(readLines(file.path(res$run_dir, "done.txt")))
  res2 <- suppressMessages(pam_detect(p$cfg, master = p$master, sample_n = 2, seed = 7, force = TRUE))
  expect_equal(sort(readLines(file.path(res2$run_dir, "done.txt"))), done1)
})

test_that("pam_detect: input = 'filtered' reads from the filtered folder", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project(rels = c("G1/a.wav", "G1/b.wav"), input = "filtered")
  res <- suppressMessages(pam_detect(p$cfg, master = p$master))
  expect_equal(res$n_done, 2L)
})

test_that("pam_detect: master is read from audio_master.csv when not supplied", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project(rels = c("G1/a.wav"))
  expect_error(suppressMessages(pam_detect(p$cfg)), "audio_master.csv not found")
  dir.create(p$cfg$paths$metadata, recursive = TRUE)
  data.table::fwrite(p$master, file.path(p$cfg$paths$metadata, "audio_master.csv"))
  res <- suppressMessages(pam_detect(p$cfg))
  expect_equal(res$n_done, 1L)
})

test_that("pam_detect: a crashing batch is logged, files stay pending, run continues", {
  skip_if_no_detect_deps(); local_fake_worker()
  p <- mk_detect_project()
  withr::local_options(pamtest.explode = TRUE)
  res <- suppressMessages(pam_detect(p$cfg, master = p$master))
  expect_equal(res$n_done, 0L)
  expect_false(file.exists(file.path(res$run_dir, "done.txt")))
  log_txt <- paste(readLines(file.path(p$cfg$paths$logs, "03_detect.log")), collapse = "\n")
  expect_match(log_txt, "failed: worker crashed")
  withr::local_options(pamtest.explode = NULL)
  res2 <- suppressMessages(pam_detect(p$cfg, master = p$master))
  expect_equal(res2$n_done, 3L)
})

# ── pam_assemble_detections: extra branches ──────────────────────────────────

mk_assemble_project <- function(batch, master_start = "2024-01-01T06:00:00Z", tz = "Asia/Kolkata") {
  audio_std <- tempfile("std_"); meta_dir <- tempfile("meta_"); det_dir <- tempfile("det_")
  dir.create(audio_std); dir.create(meta_dir); dir.create(file.path(det_dir, "run01", "batches"),
                                                          recursive = TRUE)
  data.table::fwrite(batch, file.path(det_dir, "run01", "batches", "batch_001.csv"))
  data.table::fwrite(
    data.table::data.table(file_path = file.path(audio_std, "G1", "rec.wav"), grid = "G1",
                           recorder = "SM4", deployment_id = "D01",
                           start_time = master_start, in_deployment = TRUE),
    file.path(meta_dir, "audio_master.csv"))
  list(filenames = list(timezone = tz),
       paths = list(detections = det_dir, metadata = meta_dir, audio_standardized = audio_std,
                    logs = tempfile("logs_")),
       birdnet = list(run_id = "run01"))
}

test_that("pam_assemble_detections: times are converted to the project timezone", {
  cfg <- mk_assemble_project(data.table::data.table(
    rel = "G1/rec.wav", start_s = c(5, 1), end_s = c(8, 4),
    scientific_name = "Aus bus", common_name = "A", confidence = c(0.9, 0.8)))
  res <- pamflow:::pam_assemble_detections(cfg, "run01")
  expect_equal(format(res$recording_start[1], "%H:%M:%S"), "11:30:00")
  expect_equal(res$start_time, c(1, 5))                           # ordered by start time
  expect_equal(format(res$detection_datetime[2], "%H:%M:%S"), "11:30:05")
  expect_equal(res$recording_date[1], as.Date("2024-01-01"))
  txt <- readLines(file.path(cfg$paths$detections, "run01", "detections.csv"))
  expect_true(any(grepl("11:30:05.0", txt, fixed = TRUE)))
})

test_that("pam_assemble_detections: missing common name leaves the scientific name as species", {
  cfg <- mk_assemble_project(data.table::data.table(
    rel = "G1/rec.wav", start_s = 0, end_s = 3, scientific_name = "Aus bus",
    common_name = NA_character_, confidence = 0.9))
  res <- pamflow:::pam_assemble_detections(cfg, "run01")
  expect_equal(res$species, "Aus bus")
})

test_that("pam_assemble_detections: detections for files absent from the master are kept with NA metadata", {
  cfg <- mk_assemble_project(data.table::data.table(
    rel = c("G1/rec.wav", "other/ghost.wav"), start_s = 0, end_s = 3,
    scientific_name = "Aus bus", common_name = "A", confidence = 0.9))
  res <- pamflow:::pam_assemble_detections(cfg, "run01")
  expect_equal(nrow(res), 2L)
  expect_true(is.na(res[rel == "other/ghost.wav", grid]))
  expect_equal(res[rel == "G1/rec.wav", grid], "G1")
})

test_that("pam_assemble_detections: POSIXct-style master start_time is also accepted", {
  cfg <- mk_assemble_project(data.table::data.table(
    rel = "G1/rec.wav", start_s = 0, end_s = 3, scientific_name = "Aus bus",
    common_name = "A", confidence = 0.9), master_start = "2024-01-01T06:00:00Z", tz = "UTC")
  res <- pamflow:::pam_assemble_detections(cfg, "run01")
  expect_equal(format(res$recording_start, "%H:%M"), "06:00")
})
