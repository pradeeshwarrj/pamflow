quiet_notifications <- function(.env = parent.frame()) {
  testthat::local_mocked_bindings(showNotification = function(...) invisible(NULL),
                                  .package = "shiny", .env = .env)
}

fake_result <- function(plan, status = "ok") {
  best <- "...Done. Best AUPRC: 0.8, Best AUROC: 0.9, Best Loss: 1.0 (epoch 3/3)\n"
  list(status = status, output = plan$output,
       files = c(model = TRUE, labels = TRUE, params = TRUE, counts = TRUE),
       elapsed = as.difftime(1, units = "mins"), log = plan$log_file, run_record = "",
       args = plan$args, metrics = pam_train_parse_metrics(best))
}

fake_plan <- function(data_dir, output, ...) {
  list(bin = "b", args = "x", log_file = paste0(output, "_train.log"), output = output,
       model_file = paste0(output, ".tflite"), data_dir = data_dir, params = list())
}

test_that("the app object builds with and without the training environment", {
  expect_s3_class(pam_train_app(envdir = file.path(tempdir(), "no_env")), "shiny.appobj")
  env <- fake_train_env()
  expect_s3_class(pam_train_app(envdir = env, data_dir = "x", output_dir = "y", lang = "en"), "shiny.appobj")
  cfg <- list(paths = list(project_root = "/p"), birdnet = list(model_dir = "models"))
  expect_s3_class(pam_train_app(cfg = cfg, envdir = env), "shiny.appobj")
})

test_that("an invalid form does not start a training", {
  quiet_notifications()
  env <- fake_train_env()
  local_mocked_bindings(pam_job_start = function(...) stop("must not start"))
  shiny::testServer(pam_train_app(envdir = env), {
    set_form(session, train_dir = "", out_dir = "")
    session$setInputs(start = 1)
    expect_equal(rv$state, "idle")
    expect_null(rv$job)
  })
})

test_that("a plan that fails stops the start and reports it", {
  quiet_notifications()
  env <- fake_train_env(); tdata <- make_class_dir(); tout <- withr::local_tempdir()
  local_mocked_bindings(
    pam_train_plan = function(...) stop("A model already exists"),
    pam_job_start = function(...) stop("must not start"))
  shiny::testServer(pam_train_app(envdir = env), {
    set_form(session, train_dir = tdata, out_dir = tout)
    session$setInputs(start = 1)
    expect_equal(rv$state, "idle")
    expect_length(rv$queue, 0L)
  })
})

test_that("the app starts a training, follows it and shows the result", {
  quiet_notifications()
  env <- fake_train_env(); tdata <- make_class_dir(); tout <- withr::local_tempdir()
  alive <- c(TRUE, TRUE, FALSE); polls <- 0L
  fake_job <- new.env()
  local_mocked_bindings(
    pam_train_plan = fake_plan,
    pam_job_start = function(...) fake_job,
    pam_job_poll = function(job, ...) { polls <<- polls + 1L; if (polls == 1L) raw_log_fixture("training") else "" },
    pam_job_alive = function(job) { v <- alive[1L]; if (length(alive) > 1L) alive <<- alive[-1L]; v },
    pam_job_drain = function(job) "...Done. Best AUPRC: 0.8, Best AUROC: 0.9, Best Loss: 1.0 (epoch 3/3)\n",
    pam_job_close = function(job) 0L,
    pam_train_finish = function(plan, status, elapsed, ...) fake_result(plan))
  shiny::testServer(pam_train_app(envdir = env), {
    set_form(session, train_dir = tdata, out_dir = tout)
    session$setInputs(start = 1)
    expect_equal(rv$state, "running")
    expect_equal(rv$k, 1L)
    for (i in 1:6) session$elapse(600)
    expect_equal(rv$state, "idle")
    expect_equal(rv$last$status, "ok")
    expect_length(rv$results, 1L)
    expect_match(rv$text, "Epoch 1/3")
    expect_match(output$log, "Epoch 1/3")
    expect_equal(basename(rv$last$output), "CustomClassifier")
  })
})

test_that("several runs are queued and run one after the other", {
  quiet_notifications()
  env <- fake_train_env(); tdata <- make_class_dir(); tout <- withr::local_tempdir()
  planned <- character(); fake_job <- new.env()
  local_mocked_bindings(
    pam_train_plan = function(data_dir, output, ...) { planned <<- c(planned, basename(output)); fake_plan(data_dir, output) },
    pam_job_start = function(...) fake_job,
    pam_job_poll = function(job, ...) "",
    pam_job_alive = function(job) FALSE,
    pam_job_drain = function(job) "",
    pam_job_close = function(job) 0L,
    pam_train_finish = function(plan, status, elapsed, ...) fake_result(plan))
  shiny::testServer(pam_train_app(envdir = env), {
    set_form(session, train_dir = tdata, out_dir = tout, n_runs = 2)
    session$setInputs(start = 1)
    for (i in 1:6) session$elapse(600)
    expect_equal(planned, c("CustomClassifier_run01", "CustomClassifier_run02"))
    expect_length(rv$results, 2L)
    expect_equal(rv$state, "idle")
    expect_length(rv$queue, 0L)
  })
})

test_that("a failed run stops the queue", {
  quiet_notifications()
  env <- fake_train_env(); tdata <- make_class_dir(); tout <- withr::local_tempdir()
  planned <- character(); fake_job <- new.env()
  local_mocked_bindings(
    pam_train_plan = function(data_dir, output, ...) { planned <<- c(planned, basename(output)); fake_plan(data_dir, output) },
    pam_job_start = function(...) fake_job,
    pam_job_poll = function(job, ...) "",
    pam_job_alive = function(job) FALSE,
    pam_job_drain = function(job) "",
    pam_job_close = function(job) 1L,
    pam_train_finish = function(plan, status, elapsed, ...) fake_result(plan, status = "failed"))
  shiny::testServer(pam_train_app(envdir = env), {
    set_form(session, train_dir = tdata, out_dir = tout, n_runs = 3)
    session$setInputs(start = 1)
    for (i in 1:6) session$elapse(600)
    expect_equal(planned, "CustomClassifier_run01")             # the other two never start
    expect_equal(rv$last$status, "failed")
    expect_equal(rv$state, "idle")
  })
})

test_that("Stop ends the job and the queue", {
  quiet_notifications()
  env <- fake_train_env(); tdata <- make_class_dir(); tout <- withr::local_tempdir()
  running <- TRUE; stopped <- FALSE; fake_job <- new.env()
  local_mocked_bindings(
    pam_train_plan = fake_plan,
    pam_job_start = function(...) fake_job,
    pam_job_poll = function(job, ...) "",
    pam_job_alive = function(job) running,
    pam_job_stop = function(job) { stopped <<- TRUE; running <<- FALSE; invisible(job) },
    pam_job_drain = function(job) "",
    pam_job_close = function(job) 1L,
    pam_train_finish = function(plan, status, elapsed, ...) fake_result(plan, status = "failed"))
  shiny::testServer(pam_train_app(envdir = env), {
    set_form(session, train_dir = tdata, out_dir = tout, n_runs = 3)
    session$setInputs(start = 1)
    expect_equal(rv$state, "running")
    session$setInputs(stop = 1)
    expect_true(stopped)
    expect_equal(rv$state, "stopping")
    expect_length(rv$queue, 0L)
    for (i in 1:4) session$elapse(600)
    expect_equal(rv$state, "idle")
    expect_true(rv$stopped)
    expect_length(rv$results, 1L)
  })
})

test_that("checking the data lists the classes and any problems", {
  quiet_notifications()
  env <- fake_train_env(); tdata <- make_class_dir()
  shiny::testServer(pam_train_app(envdir = env), {
    session$setInputs(train_dir = tdata)
    session$setInputs(check_data = 1)
    x <- classes()
    expect_false(is.null(x))
    expect_equal(sort(x$classes$class), c("noise", "species_a", "species_b"))
    expect_equal(n_classes(), 3L)
    session$setInputs(train_dir = file.path(tempdir(), "no_such_folder"))
    session$setInputs(check_data = 2)
    expect_null(classes())
  })
})
