# test-detect.R
# Tests for Stage 3 pure helpers (no BirdNET, no Python required).
# pam_detect_settings() validates and resolves model paths.

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
      batch_size      = 64L,
      use_bandpass    = TRUE,
      bandpass_fmin   = 0,
      bandpass_fmax   = 15000,
      tflite_threads  = 1L,
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

# ── pam_portable ──────────────────────────────────────────────────────────────

test_that("pam_portable: wrapped function still works with helper injected into its env", {
  helper <- function(x) x * 2
  fn     <- function(x) helper(x) + 1

  # Before wrapping, fn looks up helper in its definition environment
  portable_fn <- pamflow:::pam_portable(fn, helper = helper)
  expect_equal(portable_fn(3), 7)  # 3*2 + 1
})

test_that("pam_portable: environment of wrapped fn is NOT the original env", {
  fn  <- function() NULL
  pfn <- pamflow:::pam_portable(fn)
  expect_false(identical(environment(pfn), environment(fn)))
})

test_that("pam_portable: multiple helpers are all available inside wrapped fn", {
  double <- function(x) x * 2
  triple <- function(x) x * 3
  fn     <- function(x) double(x) + triple(x)

  pfn <- pamflow:::pam_portable(fn, double = double, triple = triple)
  expect_equal(pfn(4), 4 * 2 + 4 * 3)
})
