# helper: make a fake class folder with n files
make_class <- function(root, cls, n, ext = ".wav") {
  d <- file.path(root, cls)
  dir.create(d, recursive = TRUE)
  for (i in seq_len(n)) file.create(file.path(d, paste0(cls, "_", i, ext)))
  invisible(d)
}

test_that("a plain run passes only the paths and leaves defaults to the Analyzer", {
  a <- pam_birdnet_train_args("data", "out/Model")
  expect_equal(a, c("data", "-o", "out/Model"))
  expect_length(pam_birdnet_train_flags(a), 0L)
})

test_that("user parameters become flags; on/off switches have no negative form", {
  a <- pam_birdnet_train_args("d", "o", params = list(epochs = 100L, focal_loss = TRUE,
                                                     mixup = FALSE, hidden_units = 512,
                                                     threads = 12, learning_rate = 1e-4))
  expect_equal(a[which(a == "--epochs") + 1L], "100")
  expect_equal(a[which(a == "--hidden_units") + 1L], "512")
  expect_equal(a[which(a == "--threads") + 1L], "12")
  expect_equal(a[which(a == "--learning_rate") + 1L], "0.0001")
  expect_true("--focal-loss" %in% a)
  expect_false(any(grepl("mixup", a)))                  # FALSE = leave it off
  expect_false(any(grepl("^--no-", a)))
})

test_that("NULL in params is ignored", {
  a <- pam_birdnet_train_args("d", "o", params = list(epochs = NULL))
  expect_false("--epochs" %in% a)
})

test_that("model format, test data and cache options are passed", {
  a <- pam_birdnet_train_args("d", "o", params = list(model_format = "both"),
                              test_data = "t", cache_mode = "save", cache_file = "c.npz")
  expect_equal(a[which(a == "--model_format") + 1L], "both")
  expect_equal(a[which(a == "--test_data") + 1L], "t")
  expect_equal(a[which(a == "--cache_mode") + 1L], "save")
  expect_equal(a[which(a == "--cache_file") + 1L], "c.npz")
  expect_false("--cache_mode" %in% pam_birdnet_train_args("d", "o"))
})

test_that("load_params is passed through when given", {
  a <- pam_birdnet_train_args("d", "o", load_params = "p.csv")
  expect_equal(a[which(a == "--load_params") + 1L], "p.csv")
})

test_that("invalid parameters are rejected with clear errors", {
  expect_error(pam_birdnet_train_args("d", "o", params = list(epochz = 5)), "Unknown training parameter")
  expect_error(pam_birdnet_train_args("d", "o", params = list(model_formats = "tflite")), "Unknown training parameter")
  expect_error(pam_birdnet_train_args("d", "o", params = list(epochs = 2.5)), "whole number")
  expect_error(pam_birdnet_train_args("d", "o", params = list(epochs = "a")), "whole number")
  expect_error(pam_birdnet_train_args("d", "o", params = list(crop_mode = "left")), "one of")
  expect_error(pam_birdnet_train_args("d", "o", params = list(model_format = "onnx")), "one of")
  expect_error(pam_birdnet_train_args("d", "o", params = list(mixup = "yes")), "TRUE or FALSE")
  expect_error(pam_birdnet_train_args("d", "o", params = list(learning_rate = Inf)), "finite")
  expect_error(pam_birdnet_train_args("d", "o", params = list(crop_mode = c("center", "first"))), "single value")
  expect_error(pam_birdnet_train_args("d", "o", params = list(5)), "named list")
  expect_error(pam_birdnet_train_args("d", "o", cache_mode = "reuse"), "cache_mode")
})

test_that("every option pamflow can emit is a flag the 2.4.0 parser defines", {
  # the exact flags documented for BirdNET-Analyzer 2.4.0
  v240 <- c("--epochs", "--val_split", "--learning_rate", "--batch_size", "--threads",
            "--crop_mode", "--overlap", "--fmin", "--fmax", "--audio_speed", "--hidden_units",
            "--dropout", "--focal-loss", "--focal-loss-gamma", "--focal-loss-alpha",
            "--label_smoothing", "--mixup", "--upsampling_ratio", "--upsampling_mode",
            "--model_save_mode", "--model_format", "--autotune", "--autotune_trials",
            "--autotune_executions_per_trial")
  flags <- vapply(pam_train_param_spec(), `[[`, character(1), "flag")
  expect_setequal(unname(flags), v240)
})

test_that("unsupported flags are detected from help text", {
  flags <- c("--epochs", "--mixup", "--model_format")
  expect_length(pam_birdnet_unsupported_flags(flags, "--epochs --mixup --model_format"), 0L)
  expect_equal(pam_birdnet_unsupported_flags(flags, "--epochs --model_format"), "--mixup")
  expect_equal(pam_birdnet_unsupported_flags(flags, character()), flags)
})

test_that("flag matching is on whole flags, not prefixes", {
  help_text <- "usage: birdnet-train [--focal-loss-gamma G] [--epochs EPOCHS]"
  expect_equal(pam_birdnet_unsupported_flags("--focal-loss", help_text), "--focal-loss")
  expect_length(pam_birdnet_unsupported_flags(c("--focal-loss-gamma", "--epochs"), help_text), 0L)
  expect_length(pam_birdnet_unsupported_flags("--mixup", "  --mixup  Whether to use mixup"), 0L)
})

test_that("prepare summarises classes and reports problems", {
  root <- withr::local_tempdir()
  make_class(root, "species_a", 25)
  make_class(root, "species_b", 5)
  make_class(root, "noise", 30)
  dir.create(file.path(root, "empty_class"))
  file.create(file.path(root, "species_a", "notes.txt"))
  res <- pam_birdnet_train_prepare(root, min_clips = 20L, quiet = TRUE)
  expect_false(res$ok)
  cl <- res$classes
  expect_equal(cl$n_audio[cl$class == "species_a"], 25L)
  expect_equal(cl$n_other[cl$class == "species_a"], 1L)
  expect_true(cl$is_noise[cl$class == "noise"])
  expect_true(any(grepl("no audio files: empty_class", res$issues)))
  expect_true(any(grepl("fewer than 20 clips: species_b", res$issues)))
  expect_true(any(grepl("Non-audio files found in: species_a", res$issues)))
  expect_false(any(grepl("non-event class", res$issues)))
})

test_that("prepare flags a missing noise class and passes a clean dataset", {
  root <- withr::local_tempdir()
  make_class(root, "a", 30); make_class(root, "b", 30)
  res <- pam_birdnet_train_prepare(root, quiet = TRUE)
  expect_true(any(grepl("non-event class", res$issues)))
  make_class(root, "background", 30)
  expect_true(pam_birdnet_train_prepare(root, quiet = TRUE)$ok)
})

test_that("prepare errors on a missing folder or no class folders", {
  expect_error(pam_birdnet_train_prepare(file.path(tempdir(), "nope")), "not found")
  root <- withr::local_tempdir()
  expect_error(pam_birdnet_train_prepare(root), "No class sub-folders")
})

# --- pam_birdnet_train with the command runner mocked ------------------------

fake_env <- function() {
  envdir <- withr::local_tempdir(.local_envir = parent.frame())
  bin <- pam_birdnet_train_bin(envdir)
  dir.create(dirname(bin), recursive = TRUE)
  file.create(bin)
  envdir
}

test_that("train aborts clearly when the environment or inputs are missing", {
  data <- withr::local_tempdir()
  expect_error(pam_birdnet_train(file.path(tempdir(), "nope"), "o"), "Training folder not found")
  expect_error(pam_birdnet_train(data, file.path(data, "m"), envdir = file.path(tempdir(), "noenv")),
               "birdnet-train not found")
  env <- fake_env()
  expect_error(pam_birdnet_train(data, file.path(data, "m"), envdir = env,
                                 load_params = file.path(data, "missing.csv")),
               "Parameters file not found")
})

test_that("train succeeds, writes a run record, and refuses to overwrite", {
  data <- withr::local_tempdir(); env <- fake_env()
  out <- file.path(withr::local_tempdir(), "models", "M")
  local_mocked_bindings(
    pam_birdnet_train_help = function(bin) "--epochs",
    pam_run_command = function(bin, args, log_file, live = FALSE) {
      for (suffix in c(".tflite", "_Labels.txt", "_Params.csv", "_sample_counts.csv")) {
        file.create(paste0(out, suffix))
      }
      0L
    })
  res <- suppressMessages(pam_birdnet_train(data, out, params = list(epochs = 5L), envdir = env))
  expect_equal(res$status, "ok")
  expect_true(all(res$files))
  expect_true(file.exists(paste0(out, "_run.yml")))
  rec <- yaml::read_yaml(paste0(out, "_run.yml"))
  expect_equal(rec$exit_status, 0L)
  expect_equal(rec$params$epochs, 5L)
  expect_error(pam_birdnet_train(data, out, envdir = env), "already exists")
  expect_equal(suppressMessages(pam_birdnet_train(data, out, envdir = env, overwrite = TRUE))$status, "ok")
})

test_that("train reports failure without erroring when the trainer fails", {
  data <- withr::local_tempdir(); env <- fake_env()
  out <- file.path(withr::local_tempdir(), "M")
  local_mocked_bindings(
    pam_birdnet_train_help = function(bin) "--epochs",
    pam_run_command = function(bin, args, log_file, live = FALSE) {
      writeLines(c("loading", "Traceback: boom"), log_file)
      1L
    })
  res <- suppressMessages(capture.output(r <- pam_birdnet_train(data, out, envdir = env)))
  expect_equal(r$status, "failed")
  expect_false(r$files[["model"]])
})

test_that("train stops when the installed Analyzer lacks a requested option", {
  data <- withr::local_tempdir(); env <- fake_env()
  out <- file.path(withr::local_tempdir(), "M")
  local_mocked_bindings(pam_birdnet_train_help = function(bin) "--epochs")
  expect_error(pam_birdnet_train(data, out, params = list(mixup = TRUE), envdir = env),
               "does not list these options")
})


# --- metrics reader (fixture follows the format printed by BirdNET-Analyzer 2.4.0) ---

fixture_log <- function() {
  c("WARNING: All log messages before absl::InitializeLog() is called are written to STDERR",
    "I0000 00:00:1793255241.085878    3212 port.cc:153] oneDNN custom operations are on.",
    "...Done. Loaded 829 training samples and 17 labels.",
    "Building model...",
    "Training model...",
    "Training on 658 samples, validating on 171 samples.",
    "Epoch 1/3",
    "1/21 \u2501\u2501\u2501 10s 544ms/step - AUPRC: 0.0560 - AUROC: 0.5468 - loss: 13.7393",
    "21/21 \u2501\u2501\u2501 1s 11ms/step - AUPRC: 0.0558 - AUROC: 0.5563 - loss: 11.1226 - val_AUPRC: 0.0527 - val_AUROC: 0.5486 - val_loss: 8.8303 - learning_rate: 1.0000e-04",
    "Epoch 2/3",
    "1/21 \u2501\u2501\u2501 0s 16ms/step - AUPRC: 0.0563 - AUROC: 0.5752 - loss: 8.7548",
    "21/21 \u2501\u2501\u2501 0s 4ms/step - AUPRC: 0.0574 - AUROC: 0.5614 - loss: 7.3537 - val_AUPRC: 0.0562 - val_AUROC: 0.5663 - val_loss: 6.0975 - learning_rate: 1.0000e-04",
    "Epoch 3/3",
    "21/21 \u2501\u2501\u2501 0s 3ms/step - AUPRC: 0.0645 - AUROC: 0.5858 - loss: 5.3451 - val_AUPRC: 0.0611 - val_AUROC: 0.5939 - val_loss: 4.7322 - learning_rate: 9.7286e-05",
    "Restoring model weights from the end of the best epoch: 3.",
    "No separate test data provided for evaluation. Using validation metrics.",
    "...Done. Best AUPRC: 0.0611, Best AUROC: 0.5939, Best Loss: 4.7322 (epoch 3/3)")
}

test_that("metrics are read from a training log", {
  f <- withr::local_tempfile(fileext = ".log")
  writeLines(fixture_log(), f)
  m <- pam_birdnet_train_metrics(f)
  expect_equal(nrow(m$history), 3L)
  expect_equal(m$history$epoch, 1:3)
  expect_equal(m$history$val_auprc, c(0.0527, 0.0562, 0.0611))
  expect_equal(m$history$val_auroc, c(0.5486, 0.5663, 0.5939))
  expect_equal(m$history$auprc, c(0.0558, 0.0574, 0.0645))   # last batch line, not the first
  expect_equal(m$history$loss[1], 11.1226)
  expect_equal(m$history$learning_rate[3], 9.7286e-05)
  expect_equal(m$best$auprc, 0.0611)
  expect_equal(m$best$auroc, 0.5939)
  expect_equal(m$best$loss, 4.7322)
  expect_equal(c(m$best$epoch, m$best$n_epochs), c(3L, 3L))
  expect_equal(c(m$n_train, m$n_val, m$n_labels), c(658L, 171L, 17L))
  expect_equal(m$evaluated_on, "validation")
})

test_that("progress bars joined by carriage returns do not break parsing", {
  f <- withr::local_tempfile(fileext = ".log")
  txt <- paste(fixture_log(), collapse = "\r")
  writeBin(charToRaw(enc2utf8(txt)), f)
  m <- pam_birdnet_train_metrics(f)
  expect_equal(nrow(m$history), 3L)
  expect_equal(m$best$auprc, 0.0611)
})

test_that("an unrecognised log gives empty results, not guesses", {
  f <- withr::local_tempfile(fileext = ".log")
  writeLines(c("something else", "entirely"), f)
  m <- pam_birdnet_train_metrics(f)
  expect_equal(nrow(m$history), 0L)
  expect_true(is.na(m$best$auprc))
  expect_true(is.na(m$n_train))
  expect_error(pam_birdnet_train_metrics(file.path(tempdir(), "none.log")), "not found")
})

test_that("train returns the parsed metrics from its log", {
  data <- withr::local_tempdir(); env <- fake_env()
  out <- file.path(withr::local_tempdir(), "M")
  local_mocked_bindings(
    pam_birdnet_train_help = function(bin) "--epochs",
    pam_run_command = function(bin, args, log_file, live = FALSE) {
      writeLines(fixture_log(), log_file)
      file.create(paste0(out, ".tflite"))
      0L
    })
  res <- suppressMessages(pam_birdnet_train(data, out, params = list(epochs = 3L), envdir = env))
  expect_equal(res$status, "ok")
  expect_equal(res$metrics$best$auprc, 0.0611)
  rec <- yaml::read_yaml(paste0(out, "_run.yml"))
  expect_equal(rec$best$auroc, 0.5939)
  expect_equal(rec$effective$n_train, 658L)       # epochs and split are not in _Params.csv
  expect_equal(rec$effective$n_val, 171L)
  expect_equal(rec$effective$n_epochs, 3L)
})

test_that("the command runner captures output and exit status in a log", {
  local_child_tmp()
  skip_if_not_installed("processx")
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  skip_if_not(file.exists(rscript))
  log <- withr::local_tempfile(fileext = ".log")
  status <- pam_run_command(rscript, c("-e", "cat('hello from child\\n'); message('and stderr'); quit(status = 3)"), log)
  expect_equal(status, 3L)
  out <- readLines(log, warn = FALSE)
  expect_true(any(grepl("hello from child", out)))
  expect_true(any(grepl("and stderr", out)))
  expect_equal(pam_run_command(file.path(tempdir(), "no_such_program"), character(), log), 127L)
})

test_that("the command runner can show output live and still writes the log", {
  local_child_tmp()
  skip_if_not_installed("processx")
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  skip_if_not(file.exists(rscript))
  log <- withr::local_tempfile(fileext = ".log")
  shown <- capture.output(
    status <- pam_run_command(rscript, c("-e", "cat('live line\\n')"), log, live = TRUE))
  expect_equal(status, 0L)
  expect_true(any(grepl("live line", shown)))
  expect_true(any(grepl("live line", readLines(log, warn = FALSE))))
})

test_that("an aborted run stops the child process instead of leaving it running", {
  local_child_tmp()
  skip_on_cran()
  skip_if_not_installed("processx"); skip_if_not_installed("ps")
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  skip_if_not(file.exists(rscript))
  log <- withr::local_tempfile(fileext = ".log")
  setTimeLimit(elapsed = 12, transient = TRUE)               # aborts the call like an interrupt would
  res <- try(pam_run_command(rscript, c("-e", "cat('PID', Sys.getpid(), '\\n'); flush(stdout()); Sys.sleep(120)"), log),
             silent = TRUE)
  setTimeLimit(elapsed = Inf)
  expect_s3_class(res, "try-error")
  pid <- suppressWarnings(as.integer(sub(".*PID ([0-9]+).*", "\\1", paste(readLines(log, warn = FALSE), collapse = " "))))
  skip_if(is.na(pid), "the child did not report its process id before the abort")
  Sys.sleep(1)
  still_running <- tryCatch(ps::ps_is_running(ps::ps_handle(pid)), error = function(e) FALSE)
  expect_false(isTRUE(still_running))
})


test_that("repeat runs are summarised and a failed run does not stop the others", {
  calls <- 0L
  local_mocked_bindings(pam_birdnet_train = function(data_dir, output, params = list(), ...) {
    calls <<- calls + 1L
    if (calls == 2L) rlang::abort("boom")
    list(status = "ok", elapsed = as.difftime(2, units = "mins"),
         metrics = list(best = list(auprc = 0.8 + 0.01 * calls, auroc = 0.95 + 0.01 * calls,
                                    loss = 1.5, epoch = 50L, n_epochs = 50L)))
  })
  res <- suppressMessages(pam_birdnet_train_repeat("d", "out/M", n = 3L))
  expect_equal(res$runs$status, c("ok", "error", "ok"))
  expect_equal(res$runs$output, c("out/M_run01", "out/M_run02", "out/M_run03"))
  expect_true(is.na(res$runs$auprc[2]))
  s <- res$summary
  expect_equal(s$metric, c("auprc", "auroc", "loss"))
  expect_equal(s$n, c(2L, 2L, 2L))
  expect_equal(s$mean[s$metric == "auprc"], mean(c(0.81, 0.83)))
  expect_equal(s$sd[s$metric == "auprc"], stats::sd(c(0.81, 0.83)))
  expect_equal(s$min[s$metric == "auroc"], 0.96)
})

test_that("a single successful run gives no standard deviation, and n is validated", {
  local_mocked_bindings(pam_birdnet_train = function(data_dir, output, params = list(), ...) {
    list(status = "ok", elapsed = as.difftime(1, units = "mins"),
         metrics = list(best = list(auprc = 0.7, auroc = 0.9, loss = 2, epoch = 10L, n_epochs = 10L)))
  })
  res <- suppressMessages(pam_birdnet_train_repeat("d", "o", n = 1L))
  expect_true(is.na(res$summary$sd[1]))
  expect_error(pam_birdnet_train_repeat("d", "o", n = 0L), "positive whole number")
})

# ---- test-set evaluation ------------------------------------------------------------------

evaluation_csv_lines <- function() {
  c(paste0("Class,Precision (0.5),Recall (0.5),F1 Score (0.5),Precision (opt),Recall (opt),",
           "F1 Score (opt),AUPRC,AUROC,Optimal Threshold,True Positives,False Positives,",
           "True Negatives,False Negatives,Samples,Percentage (%)"),
    "OVERALL (Macro-avg),0.5000,0.4000,0.4400,0.6000,0.7000,0.6400,0.7100,0.8200,,,,,,,",
    "Aethopyga siparaja_Crimson Sunbird,0.5000,0.4000,0.4400,0.6000,0.7000,0.6400,0.7100,0.8200,0.35,7,5,40,3,10,20.00",
    "Colibri_Colibr\u00ed,1.0000,0.5000,0.6700,0.8000,0.9000,0.8500,0.9000,0.9500,0.25,9,2,38,1,10,20.00")
}

test_that("the evaluation file is read into overall and per-class tables", {
  out <- file.path(withr::local_tempdir(), "M")
  writeLines(evaluation_csv_lines(), paste0(out, "_evaluation.csv"), useBytes = FALSE)
  ev <- pam_train_read_evaluation(out)
  expect_equal(nrow(ev$classes), 2L)
  expect_equal(ev$overall$auprc, 0.71)
  expect_equal(ev$classes$class[1], "Aethopyga siparaja_Crimson Sunbird")
  expect_equal(ev$classes$tp[1], 7)
  expect_equal(ev$classes$threshold[2], 0.25)
  expect_true(is.na(ev$overall$threshold))
})

test_that("an evaluation file in the Windows encoding keeps accented names", {
  out <- file.path(withr::local_tempdir(), "M")
  con <- file(paste0(out, "_evaluation.csv"), "wb")
  writeBin(charToRaw(iconv(paste(evaluation_csv_lines(), collapse = "\r\n"),
                           from = "UTF-8", to = "windows-1252")), con)
  close(con)
  ev <- pam_train_read_evaluation(out)
  expect_equal(ev$classes$class[2], "Colibri_Colibr\u00ed")
})

test_that("a missing or unreadable evaluation file gives NULL", {
  out <- file.path(withr::local_tempdir(), "M")
  expect_null(pam_train_read_evaluation(out))
  writeLines("not,a,table", paste0(out, "_evaluation.csv"))
  expect_null(pam_train_read_evaluation(out))
})

test_that("train returns the test evaluation written during the run", {
  data <- withr::local_tempdir(); test <- withr::local_tempdir(); env <- fake_env()
  run <- function(out, test_data, write_csv = TRUE) {
    local_mocked_bindings(
      pam_birdnet_train_help = function(bin) "--epochs --test_data",
      pam_run_command = function(bin, args, log_file, live = FALSE) {
        file.create(paste0(out, ".tflite"))
        if (write_csv) writeLines(evaluation_csv_lines(), paste0(out, "_evaluation.csv"))
        0L
      })
    suppressMessages(pam_birdnet_train(data, out, test_data = test_data, envdir = env))
  }
  out1 <- file.path(withr::local_tempdir(), "A")
  with_test <- run(out1, test)
  expect_equal(nrow(with_test$evaluation$classes), 2L)
  rec <- yaml::read_yaml(paste0(out1, "_run.yml"))
  expect_equal(rec$test$auroc, 0.82)
  out2 <- file.path(withr::local_tempdir(), "B")
  expect_null(run(out2, NULL, write_csv = FALSE)$evaluation)
})

test_that("an evaluation file left by an earlier run is ignored", {
  data <- withr::local_tempdir(); env <- fake_env()
  out <- file.path(withr::local_tempdir(), "M")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  old <- paste0(out, "_evaluation.csv")
  writeLines(evaluation_csv_lines(), old)
  Sys.setFileTime(old, Sys.time() - 3600)
  local_mocked_bindings(
    pam_birdnet_train_help = function(bin) "--epochs",
    pam_run_command = function(bin, args, log_file, live = FALSE) {
      file.create(paste0(out, ".tflite")); 0L
    })
  res <- suppressMessages(pam_birdnet_train(data, out, envdir = env, overwrite = TRUE))
  expect_null(res$evaluation)
})

# ---- cache ---------------------------------------------------------------------------------

test_that("cache paths always end in .npz, as NumPy writes them", {
  expect_equal(pam_train_cache_path("a/cache"), "a/cache.npz")
  expect_equal(pam_train_cache_path("a/cache.npz"), "a/cache.npz")
  expect_equal(pam_train_cache_path("a/cache.NPZ"), "a/cache.NPZ")
  expect_null(pam_train_cache_path(NULL))
  expect_equal(pam_train_cache_path(""), "")
})

test_that("a cache given without the extension is found and passed with it", {
  env <- fake_env()
  dir_out <- withr::local_tempdir()
  cache <- file.path(dir_out, "clips")
  file.create(paste0(cache, ".npz"))
  local_mocked_bindings(pam_birdnet_train_help = function(bin) "--cache_mode --cache_file")
  plan <- pam_train_plan(NULL, file.path(dir_out, "M"), cache_mode = "load", cache_file = cache, envdir = env)
  expect_equal(plan$cache_file, paste0(cache, ".npz"))
  expect_true(paste0(cache, ".npz") %in% plan$args)
  expect_error(pam_train_plan(NULL, file.path(dir_out, "M"), cache_mode = "load",
                              cache_file = file.path(dir_out, "none"), envdir = env), "not found")
})

test_that("the trainer's cache messages are recognised", {
  log <- c("Loading training data...", "\t...loading from cache: C:/x/c.npz",
           "\t...WARNING: Cache preprocessing parameters don't match current settings!",
           "\t   Cache: fmin=0.0, fmax=15000.0, speed=1.0",
           "\t   Cache: crop_mode=center, overlap=0.0",
           "\t   Current: fmin=0.0, fmax=8000.0, speed=1.0")
  n <- pam_train_cache_notes(log)
  expect_true(n$used)
  expect_true(n$mismatch)
  expect_false(n$missing)
  expect_equal(n$cache_settings, c("Cache: fmin=0.0, fmax=15000.0, speed=1.0",
                                   "Cache: crop_mode=center, overlap=0.0"))
  fallback <- pam_train_cache_notes("\t...cache file not found: C:/x/c.npz\nLoading")
  expect_true(fallback$missing)
  expect_false(fallback$used)
  expect_false(pam_train_cache_notes("Loading training data...")$mismatch)
})

test_that("train reports the cache notes from its log", {
  data <- withr::local_tempdir(); env <- fake_env()
  out <- file.path(withr::local_tempdir(), "M")
  cache <- file.path(withr::local_tempdir(), "c.npz"); file.create(cache)
  local_mocked_bindings(
    pam_birdnet_train_help = function(bin) "--cache_mode --cache_file",
    pam_run_command = function(bin, args, log_file, live = FALSE) {
      writeLines(c("\t...loading from cache: x",
                   "\t...WARNING: Cache preprocessing parameters don't match current settings!"), log_file)
      file.create(paste0(out, ".tflite")); 0L
    })
  res <- suppressMessages(pam_birdnet_train(data, out, cache_mode = "load", cache_file = cache, envdir = env))
  expect_true(res$cache$used)
  expect_true(res$cache$mismatch)
})

test_that("a plain cache file name is placed next to the model, not in the working directory", {
  env <- fake_env()
  dir_out <- withr::local_tempdir()
  local_mocked_bindings(pam_birdnet_train_help = function(bin) "--cache_mode --cache_file")
  plan <- pam_train_plan(withr::local_tempdir(), file.path(dir_out, "M"), cache_mode = "save",
                         cache_file = "clips", envdir = env)
  same_path <- function(a, b) identical(normalizePath(a, winslash = "/", mustWork = FALSE),
                                        normalizePath(b, winslash = "/", mustWork = FALSE))
  expected <- file.path(dir_out, "clips.npz")
  expect_true(same_path(plan$cache_file, expected))
  expect_true(same_path(plan$args[which(plan$args == "--cache_file") + 1L], expected))
  absolute <- file.path(withr::local_tempdir(), "abs.npz")
  plan2 <- pam_train_plan(withr::local_tempdir(), file.path(dir_out, "M2"), cache_mode = "save",
                          cache_file = absolute, envdir = env)
  expect_true(same_path(plan2$cache_file, absolute))
})
