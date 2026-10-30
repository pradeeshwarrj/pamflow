# --- background jobs (real child processes, started with Rscript) -------------------------

skip_no_rscript <- function() {
  skip_if_not_installed("processx")
  skip_if_not(file.exists(rscript_path()), "Rscript not found")
}

test_that("a job can be followed while it runs and closed when it ends", {
  skip_no_rscript()
  local_child_tmp()
  log <- withr::local_tempfile(fileext = ".log")
  job <- pam_job_start(rscript_path(),
                       c("-e", "cat('first\\n'); flush(stdout()); Sys.sleep(1); cat('second\\n')"), log)
  withr::defer(pam_job_stop(job))
  expect_false(job$closed)
  seen <- ""
  finished <- wait_until(function() {
    seen <<- paste0(seen, pam_job_poll(job, 100L))
    !pam_job_alive(job)
  })
  expect_true(finished)
  seen <- paste0(seen, pam_job_drain(job))
  expect_equal(pam_job_close(job), 0L)
  expect_true(job$closed)
  expect_match(seen, "first")
  expect_match(seen, "second")
  logged <- paste(readLines(log, warn = FALSE), collapse = "\n")
  expect_match(logged, "first")
  expect_match(logged, "second")
  expect_equal(pam_job_poll(job), "")                 # a closed job gives no more output
  expect_equal(pam_job_close(job), 0L)                # closing twice is harmless
})

test_that("a job that cannot be started is closed at once with status 127", {
  log <- withr::local_tempfile(fileext = ".log")
  job <- pam_job_start(file.path(tempdir(), "no_such_program"), character(), log)
  expect_true(job$closed)
  expect_equal(job$status, 127L)
  expect_false(pam_job_alive(job))
  expect_equal(pam_job_poll(job), "")
  expect_equal(pam_job_close(job), 127L)
  expect_true(file.exists(log))
})

test_that("stopping a job ends its process", {
  skip_no_rscript()
  local_child_tmp()
  local_mocked_bindings(pam_birdnet_cleanup = function(...) invisible(NULL))
  log <- withr::local_tempfile(fileext = ".log")
  job <- pam_job_start(rscript_path(), c("-e", "Sys.sleep(120)"), log)
  withr::defer(pam_job_stop(job))
  expect_true(pam_job_alive(job))
  pam_job_stop(job)
  expect_true(wait_until(function() !pam_job_alive(job), timeout = 15))
  expect_false(identical(pam_job_close(job), 0L))
})

test_that("only a closed-pipe error is tolerated when reading a job's output", {
  fake_job <- function(read) {
    job <- new.env()
    job$closed <- FALSE
    job$log_con <- NULL
    job$p <- list(read_output = read, read_all_output = read)
    job
  }
  closed <- fake_job(function() stop("Invalid (uninitialized or closed?) connection object"))
  expect_equal(pam_job_poll(closed), "")
  limit <- fake_job(function() stop("reached elapsed time limit"))
  expect_error(pam_job_poll(limit), "elapsed time limit")      # an abort must not be swallowed
  expect_equal(pam_tolerate_closed_pipe(stop("closed connection"), "x"), "x")
  expect_error(pam_tolerate_closed_pipe(stop("something else"), "x"), "something else")
  expect_equal(pam_tolerate_closed_pipe("fine", "x"), "fine")
})

# --- plan: checks before anything starts -----------------------------------------------------

test_that("a plan checks the inputs and builds the command", {
  env <- fake_train_env()
  data <- withr::local_tempdir()
  out <- file.path(withr::local_tempdir(), "M")
  local_mocked_bindings(pam_birdnet_train_help = function(bin) "--epochs")
  plan <- pam_train_plan(data, out, params = list(epochs = 5L), envdir = env)
  expect_equal(plan$args[1], data)
  expect_true("--epochs" %in% plan$args)
  expect_equal(plan$log_file, paste0(out, "_train.log"))
  expect_equal(plan$model_file, paste0(out, ".tflite"))

  expect_error(pam_train_plan(file.path(tempdir(), "nope"), out, envdir = env), "Training folder not found")
  expect_error(pam_train_plan(NULL, out, envdir = env), "Training folder not found")
  expect_error(pam_train_plan(data, out, test_data = file.path(tempdir(), "nope"), envdir = env),
               "Test folder not found")
  expect_error(pam_train_plan(data, out, envdir = file.path(tempdir(), "no_env")), "birdnet-train not found")
  file.create(plan$model_file)
  expect_error(pam_train_plan(data, out, envdir = env), "already exists")
  expect_no_error(pam_train_plan(data, out, envdir = env, overwrite = TRUE))
})

test_that("a plan refuses options the installed Analyzer does not list", {
  env <- fake_train_env()
  data <- withr::local_tempdir()
  local_mocked_bindings(pam_birdnet_train_help = function(bin) "--epochs")
  expect_error(pam_train_plan(data, file.path(withr::local_tempdir(), "M"),
                              params = list(mixup = TRUE), envdir = env), "does not list these options")
})

test_that("a cache in load mode needs the cache file, and the training folder is then optional", {
  env <- fake_train_env()
  cache <- withr::local_tempfile(fileext = ".npz"); file.create(cache)
  out <- file.path(withr::local_tempdir(), "M")
  local_mocked_bindings(pam_birdnet_train_help = function(bin) "--cache_mode --cache_file")
  plan <- pam_train_plan(NULL, out, cache_mode = "load", cache_file = cache, envdir = env)
  expect_equal(plan$args[1], cache)                      # the trainer still needs a positional input
  expect_true(all(c("--cache_mode", "load", "--cache_file", cache) %in% plan$args))
  expect_error(pam_train_plan(NULL, out, cache_mode = "load",
                              cache_file = file.path(tempdir(), "missing.npz"), envdir = env),
               "Cache file not found")
  data <- withr::local_tempdir()
  plan2 <- pam_train_plan(data, file.path(withr::local_tempdir(), "M2"), cache_mode = "load",
                          cache_file = cache, envdir = env)
  expect_equal(plan2$args[1], data)
  # saving defaults to a cache next to the model
  plan3 <- pam_train_plan(data, out, cache_mode = "save", envdir = env)
  expect_equal(plan3$args[which(plan3$args == "--cache_file") + 1L], paste0(out, "_cache.npz"))
})

# --- finish: wrap up a run -----------------------------------------------------------------------

test_that("finishing a run checks the files, reads the metrics and writes the record", {
  out <- file.path(withr::local_tempdir(), "M")
  plan <- list(bin = "b", args = c("d", "-o", out), log_file = paste0(out, "_train.log"), output = out,
               model_file = paste0(out, ".tflite"), data_dir = "d", test_data = NULL,
               load_params = NULL, cache_mode = NULL, params = list(epochs = 3L))
  writeLines(c("Training on 33 samples, validating on 8 samples.", "Epoch 1/3",
               "...Done. Best AUPRC: 0.5, Best AUROC: 0.6, Best Loss: 3.0 (epoch 3/3)"), plan$log_file)
  file.create(paste0(out, c(".tflite", "_Labels.txt", "_Params.csv", "_sample_counts.csv")))
  elapsed <- as.difftime(2, units = "mins")

  expect_silent(res <- pam_train_finish(plan, 0L, elapsed, quiet = TRUE))
  expect_equal(res$status, "ok")
  expect_true(all(res$files))
  expect_equal(res$metrics$best$auprc, 0.5)
  rec <- yaml::read_yaml(paste0(out, "_run.yml"))
  expect_equal(rec$exit_status, 0L)
  expect_equal(rec$params$epochs, 3L)
  expect_equal(rec$effective$n_train, 33L)
  expect_equal(rec$elapsed_min, 2)

  expect_silent(res_bad <- pam_train_finish(plan, 1L, elapsed, quiet = TRUE))     # non-zero exit
  expect_equal(res_bad$status, "failed")
  unlink(paste0(out, ".tflite"))
  expect_silent(res_nomodel <- pam_train_finish(plan, 0L, elapsed, quiet = TRUE)) # exit 0 but no model
  expect_equal(res_nomodel$status, "failed")
  expect_false(res_nomodel$files[["model"]])
})
