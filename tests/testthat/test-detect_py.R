# --- worker count -----------------------------------------------------------------

test_that("unset workers default to half of the physical cores", {
  r <- pam_birdnet_resolve_workers(NULL, physical = 24L, logical = 32L)
  expect_equal(r$workers, 12L)
  expect_match(r$notes, "half of the 24 physical cores")
  expect_equal(pam_birdnet_resolve_workers(NA, physical = 1L, logical = 2L)$workers, 1L)
  expect_equal(pam_birdnet_resolve_workers(NULL, physical = 3L, logical = 6L)$workers, 1L)
})

test_that("a user-chosen worker count is respected, with a note if it uses every core", {
  r <- pam_birdnet_resolve_workers(6, physical = 24L, logical = 32L)
  expect_equal(r$workers, 6L)
  expect_length(r$notes, 0L)
  r <- pam_birdnet_resolve_workers(24, physical = 24L, logical = 32L)
  expect_equal(r$workers, 24L)
  expect_match(r$notes, "uses all 24 physical cores")
})

test_that("workers above the logical core count are reduced; bad values abort", {
  r <- pam_birdnet_resolve_workers(64, physical = 24L, logical = 32L)
  expect_equal(r$workers, 32L)
  expect_match(r$notes, "more than the 32 logical cores")
  expect_error(pam_birdnet_resolve_workers(0), "whole number")
  expect_error(pam_birdnet_resolve_workers(2.5), "whole number")
  expect_error(pam_birdnet_resolve_workers("a"), "whole number")
})

# --- argument building -------------------------------------------------------------

settings_py <- function(...) {
  utils::modifyList(list(
    backend = "birdnet", python = "py", script = "script.py",
    model_file = "m.tflite", labels_file = "l.txt", model_version = "2.4",
    min_confidence = 0.3, overlap_s = 1, use_bandpass = TRUE, bandpass_fmin = 100L,
    bandpass_fmax = 12000L, py_batch_size = 1L, workers = 6L, n_producers = 1L,
    top_k = NULL, sigmoid_sensitivity = 1, device = "CPU"), list(...), keep.null = TRUE)
}

arg_after <- function(args, flag) args[which(args == flag) + 1L]

test_that("script arguments carry the settings", {
  a <- pam_birdnet_py_args(settings_py(), "f.txt", "o.csv", "s.csv")
  expect_equal(a[1], "script.py")
  expect_equal(arg_after(a, "--model"), "m.tflite")
  expect_equal(arg_after(a, "--labels"), "l.txt")
  expect_equal(arg_after(a, "--min-confidence"), "0.3")
  expect_equal(arg_after(a, "--overlap"), "1")
  expect_equal(arg_after(a, "--fmin"), "100")
  expect_equal(arg_after(a, "--fmax"), "12000")
  expect_equal(arg_after(a, "--n-workers"), "6")
  expect_equal(arg_after(a, "--top-k"), "0")                 # NULL = no limit
  expect_equal(arg_after(a, "--files"), "f.txt")
  expect_true("--skip-validity-check" %in% a)
})

test_that("top_k, bandpass off and check mode are handled", {
  expect_equal(arg_after(pam_birdnet_py_args(settings_py(top_k = 5), "f", "o", "s"), "--top-k"), "5")
  a <- pam_birdnet_py_args(settings_py(use_bandpass = FALSE), "f", "o", "s")
  expect_equal(c(arg_after(a, "--fmin"), arg_after(a, "--fmax")), c("0", "15000"))
  a <- pam_birdnet_py_args(settings_py(), check = TRUE)
  expect_true("--check" %in% a)
  expect_false("--files" %in% a)
  expect_false("--skip-validity-check" %in% a)               # the check mode validates fully
})

# --- batch runner ------------------------------------------------------------------

fake_runner <- function(det_lines, status_lines, exit = 0L) {
  function(bin, args, log_file, live = FALSE) {
    writeLines(det_lines, arg_after(args, "--out"))
    writeLines(status_lines, arg_after(args, "--status"))
    exit
  }
}

test_that("a batch result is split per file, with failures and empty files kept", {
  items <- list(list(rel = "G1/a.wav", path = "/x/a.wav"),
                list(rel = "G1/b.wav", path = "/x/b.wav"),
                list(rel = "G1/c.wav", path = "/x/c.wav"))
  det <- c("input,start_time,end_time,species_name,confidence",
           "/x/a.wav,0.000,3.000,Hypothymis azurea_Black-naped Monarch,0.910000",
           "/x/a.wav,3.000,6.000,Ducula nicobarica_Nicobar Imperial-Pigeon,0.420000")
  st <- c("input,ok,message", "/x/a.wav,True,", "/x/b.wav,True,",
          "/x/c.wav,False,audio could not be processed (unreadable or corrupt)")
  local_mocked_bindings(pam_run_command = fake_runner(det, st))
  res <- pam_birdnet_run_batch_py(items, settings_py())
  expect_length(res, 3L)
  expect_equal(vapply(res, `[[`, "", "rel"), c("G1/a.wav", "G1/b.wav", "G1/c.wav"))
  expect_equal(vapply(res, `[[`, TRUE, "ok"), c(TRUE, TRUE, FALSE))
  expect_equal(nrow(res[[1]]$det), 2L)
  expect_equal(res[[1]]$det$scientific_name, c("Hypothymis azurea", "Ducula nicobarica"))
  expect_equal(res[[1]]$det$common_name, c("Black-naped Monarch", "Nicobar Imperial-Pigeon"))
  expect_equal(res[[1]]$det$start_s, c(0, 3))
  expect_equal(res[[1]]$det$confidence, c(0.91, 0.42))
  expect_equal(nrow(res[[2]]$det), 0L)                       # processed, nothing detected
  expect_match(res[[3]]$message, "corrupt")
  expect_equal(attr(res, "api"), "birdnet")
})

test_that("detections for a path that was not requested are ignored", {
  items <- list(list(rel = "a", path = "/x/a.wav"))
  det <- c("input,start_time,end_time,species_name,confidence",
           "/elsewhere/z.wav,0.000,3.000,A b_C d,0.5")
  local_mocked_bindings(pam_run_command = fake_runner(det, c("input,ok,message", "/x/a.wav,True,")))
  res <- pam_birdnet_run_batch_py(items, settings_py())
  expect_equal(nrow(res[[1]]$det), 0L)
})

test_that("a failed script run raises, so the batch stays pending", {
  items <- list(list(rel = "a", path = "/x/a.wav"))
  local_mocked_bindings(pam_run_command = function(bin, args, log_file, live = FALSE) {
    writeLines(c("Traceback", "RuntimeError: model blew up"), log_file)
    2L
  })
  expect_error(pam_birdnet_run_batch_py(items, settings_py()), "batch failed")
  expect_equal(pam_birdnet_run_batch_py(list(), settings_py()), list())
})

real_files_settings <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  py <- file.path(d, "python"); script <- file.path(d, "script.py")
  file.create(py, script)
  settings_py(python = py, script = script)
}

test_that("the model check reads the package version or reports the failure", {
  s <- real_files_settings()
  local_mocked_bindings(pam_run_command = function(bin, args, log_file, live = FALSE) {
    writeLines(c("noise", "PAMCHECK birdnet=0.2.16 python=3.11.18"), log_file); 0L })
  r <- pam_birdnet_py_check(s)
  expect_true(r$ok); expect_equal(r$birdnet_version, "0.2.16")
  local_mocked_bindings(pam_run_command = function(bin, args, log_file, live = FALSE) {
    writeLines(c("ValueError: model has 17 outputs, but species list has 16 species!"), log_file); 2L })
  r <- pam_birdnet_py_check(s)
  expect_false(r$ok); expect_match(r$message, "17 outputs")
})

test_that("the model check reports a missing Python environment or script without running anything", {
  local_mocked_bindings(pam_run_command = function(...) stop("must not be called"))
  s <- real_files_settings()
  r <- pam_birdnet_py_check(utils::modifyList(s, list(python = file.path(tempdir(), "no_python"))))
  expect_false(r$ok)
  expect_match(r$message, "Python environment not found")
  expect_match(r$message, "pam_birdnet_setup")
  r <- pam_birdnet_py_check(utils::modifyList(s, list(script = "")))
  expect_false(r$ok)
  expect_match(r$message, "pam_birdnet_predict.py was not found")
})

# --- settings and config -----------------------------------------------------------

make_cfg_for_settings <- function(root, backend = NULL, extra = list()) {
  model_dir <- file.path(root, "model"); dir.create(model_dir, showWarnings = FALSE)
  file.create(file.path(model_dir, "Cls.tflite"), file.path(model_dir, "Cls_Labels.txt"))
  base <- list(model_dir = model_dir, classifier_name = "Cls", min_confidence = 0.3,
               overlap_s = 0, batch_size = 8, use_bandpass = TRUE, bandpass_fmin = 0,
               bandpass_fmax = 15000, tflite_threads = 1, workers = 4, backend = backend)
  # values in `extra` replace the ones in `base` (c() would keep both and the first would win)
  list(paths = list(project_root = root),
       birdnet = utils::modifyList(base, extra, keep.null = TRUE))
}

test_that("the Python environment path is resolved without needing the environment to exist", {
  root <- withr::local_tempdir()
  s <- pam_detect_settings(make_cfg_for_settings(root, NULL, list(python_env = file.path(root, "env"))))
  expect_equal(s$python, pam_birdnet_python_path(file.path(root, "env")))
  s2 <- pam_detect_settings(make_cfg_for_settings(root))      # default environment
  expect_equal(s2$python, pam_birdnet_python_path(pam_birdnet_env_dir("inference")))
})

test_that("the birdnet backend resolves environment, workers and options", {
  root <- withr::local_tempdir()
  env <- file.path(root, "env"); py <- pam_birdnet_python_path(env)
  dir.create(dirname(py), recursive = TRUE); file.create(py)
  local_mocked_bindings(
    pam_birdnet_py_script = function() "script.py",
    pam_birdnet_resolve_workers = function(requested = NULL, ...) {   # independent of this machine
      list(workers = as.integer(requested), notes = character())
    })
  s <- pam_detect_settings(make_cfg_for_settings(root, "birdnet",
                                                 list(python_env = env, workers = 3, top_k = 5)))
  expect_equal(s$python, py)
  expect_equal(s$workers, 3L)
  expect_equal(s$top_k, 5)
  expect_equal(s$py_batch_size, 1L)
  expect_equal(s$device, "CPU")
  expect_equal(s$model_version, "2.4")
  # no top_k configured -> no limit
  s2 <- pam_detect_settings(make_cfg_for_settings(root, "birdnet", list(python_env = env)))
  expect_null(s2$top_k)
})

test_that("settings reject the removed birdnetR engine and unknown backends", {
  root <- withr::local_tempdir()
  expect_error(pam_detect_settings(make_cfg_for_settings(root, "birdnetR")), "birdnetR engine was removed")
  expect_error(pam_detect_settings(make_cfg_for_settings(root, "magic")), "not supported")
  expect_equal(pam_detect_settings(make_cfg_for_settings(root, "birdnet"))$workers >= 1L, TRUE)
})

test_that("config validation covers the new birdnet options", {
  ok <- list(birdnet = list(backend = "birdnet", top_k = 5, py_batch_size = 1, n_producers = 1,
                            sigmoid_sensitivity = 1, workers = 4))
  expect_silent(pam_config_validate(ok))
  expect_error(pam_config_validate(list(birdnet = list(backend = "x"))), "backend")
  expect_error(pam_config_validate(list(birdnet = list(backend = "birdnetR"))), "birdnetR engine was removed")
  expect_silent(pam_config_validate(list(birdnet = list(backend = "birdnet"))))
  expect_error(pam_config_validate(list(birdnet = list(top_k = 0))), "top_k")
  expect_error(pam_config_validate(list(birdnet = list(top_k = 2.5))), "top_k")
  expect_error(pam_config_validate(list(birdnet = list(py_batch_size = 0))), "py_batch_size")
  expect_error(pam_config_validate(list(birdnet = list(sigmoid_sensitivity = 0))), "sigmoid_sensitivity")
  expect_silent(pam_config_validate(list(birdnet = list(top_k = NULL))))
})

test_that("the shipped config template lists the Python-runner options and no birdnetR ones", {
  tpl <- system.file("extdata", "config_template.yml", package = "pamflow")
  skip_if(!nzchar(tpl))
  b <- yaml::read_yaml(tpl)$birdnet
  expect_false(any(c("backend", "tflite_threads", "batch_size") %in% names(b)))
  expect_null(b$workers)                                     # null = half of the physical cores
  expect_true(all(c("top_k", "py_batch_size", "n_producers", "sigmoid_sensitivity", "device",
                    "python_env") %in% names(b)))
})

# --- pam_detect end to end with the Python call mocked ------------------------------

test_that("pam_detect runs the birdnet backend, writes batches, and resumes", {
  root <- withr::local_tempdir()
  std <- file.path(root, "std", "G_1"); dir.create(std, recursive = TRUE)
  files <- file.path(std, c("a.wav", "b.wav")); file.create(files)
  cfg <- list(paths = list(project_root = root, audio_standardized = file.path(root, "std"),
                           filtered = file.path(root, "flt"), detections = file.path(root, "det"),
                           metadata = file.path(root, "meta"), logs = file.path(root, "logs")),
              birdnet = list(run_id = "r1", input = "standardized", workers = 2, chunk_size = 10))
  master <- data.table::data.table(file_path = files, qc_pass = TRUE)

  local_mocked_bindings(
    pam_detect_settings = function(cfg) settings_py(workers = 2L, worker_notes = "a note"),
    pam_birdnet_py_check = function(s) list(ok = TRUE, birdnet_version = "0.2.16", message = ""),
    pam_birdnet_cleanup = function(...) invisible(data.frame(pid = integer(), killed = logical())))
  det_row <- data.frame(start_time = 0, end_time = 3, species_name = "Hypothymis azurea_Black-naped Monarch",
                        confidence = 0.9)
  calls <- list()
  local_mocked_bindings(pam_birdnet_run_batch_py = function(items, s) {
    calls[[length(calls) + 1L]] <<- vapply(items, function(i) i$rel, "")
    out <- lapply(items, function(i) {
      ok <- !(length(calls) == 1L && grepl("b.wav", i$rel))      # b.wav fails on the first run only
      list(rel = i$rel, ok = ok, message = if (ok) "" else "corrupt", seconds = 1,
           det = if (ok && grepl("a.wav", i$rel)) pam_birdnet_normalise(det_row) else pam_birdnet_normalise(data.frame()))
    })
    out
  })

  res1 <- suppressMessages(pam_detect(cfg, master = master))
  expect_equal(c(res1$n_done, res1$n_failed, res1$n_detections), c(1L, 1L, 1L))
  batch_files <- list.files(file.path(res1$run_dir, "batches"), pattern = "\\.csv$")
  expect_length(batch_files, 1L)
  done <- readLines(file.path(res1$run_dir, "done.txt"))
  expect_equal(done, "G_1/a.wav")
  yml <- list.files(res1$run_dir, pattern = "^run_settings_", full.names = TRUE)
  expect_equal(yaml::read_yaml(yml[1])$backend, "birdnet")

  res2 <- suppressMessages(pam_detect(cfg, master = master))          # resume: only b.wav is pending
  expect_equal(res2$n_pending, 1L)
  expect_equal(calls[[2]], "G_1/b.wav")
  expect_equal(res2$n_failed, 0L)
})

test_that("an incomplete config gives a clear message naming what is missing", {
  full <- list(paths = list(detections = "d", logs = "l", audio_standardized = "a",
                            metadata = "m", filtered = "f"),
               birdnet = list(run_id = "r", chunk_size = 10, input = "standardized"))
  expect_silent(pam_detect_check_cfg(full))

  no_det <- full; no_det$paths$detections <- NULL
  expect_error(pam_detect_check_cfg(no_det), "paths\\$detections")

  no_run <- full; no_run$birdnet$run_id <- NULL
  expect_error(pam_detect_check_cfg(no_run), "birdnet\\$run_id")
  expect_error(pam_detect_check_cfg(no_run), "pam_load_config")

  # metadata only matters when the master table has to be read from disk
  no_meta <- full; no_meta$paths$metadata <- NULL
  expect_error(pam_detect_check_cfg(no_meta), "paths\\$metadata")
  expect_silent(pam_detect_check_cfg(no_meta, need_master = FALSE))

  # filtered folder only matters for input = 'filtered'
  no_filt <- full; no_filt$paths$filtered <- NULL
  expect_silent(pam_detect_check_cfg(no_filt))
  no_filt$birdnet$input <- "filtered"
  expect_error(pam_detect_check_cfg(no_filt), "paths\\$filtered")

  # and pam_detect() uses it before doing anything else
  expect_error(pam_detect(list(paths = list(), birdnet = list())), "incomplete")
})

test_that("pam_detect logs when it stops leftover workers from an interrupted run", {
  root <- withr::local_tempdir()
  std <- file.path(root, "std", "G_1"); dir.create(std, recursive = TRUE)
  f <- file.path(std, "a.wav"); file.create(f)
  cfg <- list(paths = list(project_root = root, audio_standardized = file.path(root, "std"),
                           filtered = file.path(root, "flt"), detections = file.path(root, "det"),
                           metadata = file.path(root, "meta"), logs = file.path(root, "logs")),
              birdnet = list(run_id = "r3", input = "standardized", workers = 2, chunk_size = 10))
  local_mocked_bindings(
    pam_detect_settings = function(cfg) settings_py(workers = 2L),
    pam_birdnet_cleanup = function(...) invisible(data.frame(pid = c(11L, 12L), killed = c(TRUE, TRUE))),
    pam_birdnet_py_check = function(s) list(ok = TRUE, birdnet_version = "0.2.16", message = ""),
    pam_birdnet_run_batch_py = function(items, s) lapply(items, function(i) {
      list(rel = i$rel, ok = TRUE, message = "", seconds = 1, det = pam_birdnet_normalise(data.frame()))
    }))
  suppressMessages(pam_detect(cfg, master = data.table::data.table(file_path = f, qc_pass = TRUE)))
  log_txt <- paste(readLines(file.path(root, "logs", "03_detect.log")), collapse = "\n")
  expect_match(log_txt, "stopped 2 leftover BirdNET worker process")
})

test_that("pam_detect stops early when the Python model check fails", {
  root <- withr::local_tempdir()
  std <- file.path(root, "std", "G_1"); dir.create(std, recursive = TRUE)
  f <- file.path(std, "a.wav"); file.create(f)
  cfg <- list(paths = list(project_root = root, audio_standardized = file.path(root, "std"),
                           filtered = file.path(root, "flt"), detections = file.path(root, "det"),
                           metadata = file.path(root, "meta"), logs = file.path(root, "logs")),
              birdnet = list(run_id = "r2", input = "standardized", workers = 2, chunk_size = 10))
  local_mocked_bindings(
    pam_detect_settings = function(cfg) settings_py(),
    pam_birdnet_py_check = function(s) list(ok = FALSE, birdnet_version = NA_character_, message = "labels mismatch"),
    pam_birdnet_cleanup = function(...) invisible(data.frame(pid = integer(), killed = logical())))
  expect_error(suppressMessages(pam_detect(cfg, master = data.table::data.table(file_path = f, qc_pass = TRUE))),
               "could not load the model")
})
