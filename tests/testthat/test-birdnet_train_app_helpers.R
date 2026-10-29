# --- reading the trainer's output ------------------------------------------------------

test_that("terminal colour codes are removed", {
  expect_equal(pam_train_strip_ansi("\033[1m 1/21\033[0m \033[37m-\033[0m"), " 1/21 -")
  expect_equal(pam_train_strip_ansi("plain"), "plain")
})

test_that("log lines drop noise, colours and per-step lines, and keep the last state of each bar", {
  lines <- pam_train_log_lines(raw_log_fixture())
  expect_false(any(grepl("oneDNN|InitializeLog|I0000|TensorSpec|absl|Endpoint", lines)))
  expect_false(any(grepl("\033", lines, fixed = TRUE)))
  expect_equal(sum(grepl("Downloading model", lines)), 1L)
  expect_true(any(grepl("Downloading model: 100%", lines, fixed = TRUE)))
  expect_equal(sum(grepl("loading 'Aethopyga", lines)), 1L)
  expect_true(any(grepl("Swainson's Thrush': 100%", lines, fixed = TRUE)))
  expect_true(any(grepl("^Epoch 1/3$", lines)))
  expect_false(any(grepl("^1/2 .*step - AUPRC: 0.0412", lines)))             # step line without val_ dropped
  expect_true(any(grepl("val_AUPRC: 0.0612", lines, fixed = TRUE)))          # epoch summary line kept
  expect_true(any(grepl("Best AUPRC", lines, fixed = TRUE)))
})

test_that("log lines keep only the newest lines and cope with empty input", {
  expect_equal(pam_train_log_lines(NA_character_), character())
  expect_equal(pam_train_log_lines(""), character())
  expect_length(pam_train_log_lines(raw_log_fixture(), max_lines = 3L), 3L)
  expect_match(utils::tail(pam_train_log_lines(raw_log_fixture()), 1L), "Best AUPRC")
})

test_that("progress starts empty", {
  p <- pam_train_progress("")
  expect_equal(p$phase, "starting")
  expect_equal(p$fraction, 0)
  expect_false(p$done)
})

test_that("progress follows the download, the clip loading and the epochs", {
  p <- pam_train_progress(raw_log_fixture("download"), n_classes = 2L)
  expect_equal(p$phase, "downloading")
  expect_equal(p$download_pct, 50)

  p <- pam_train_progress(raw_log_fixture("loading"), n_classes = 2L)
  expect_equal(p$phase, "loading")
  expect_equal(p$classes_done, 1L)                     # a repeated 100% line counts once; the second class is at 50%
  expect_equal(p$fraction, 0.45 * 1 / 2)

  p <- pam_train_progress(raw_log_fixture("training"), n_classes = 2L)
  expect_equal(p$phase, "training")
  expect_equal(p$classes_done, 2L)                     # a class name with an apostrophe is counted
  expect_equal(c(p$epoch, p$n_epochs), c(2L, 3L))
  expect_equal(p$fraction, 0.5 + 0.45 * 2 / 3)
  expect_false(p$done)
})

test_that("progress knows when training is done and when it stopped early", {
  p <- pam_train_progress(raw_log_fixture("end"), n_classes = 2L)
  expect_equal(p$phase, "done")
  expect_true(p$done)
  expect_equal(p$fraction, 1)
  expect_false(p$stopped_early)

  early <- paste0(raw_log_fixture("training"), "...Done. Best AUPRC: 0.5, Best AUROC: 0.6, Best Loss: 3.0 (epoch 2/3)\n")
  expect_true(pam_train_progress(early, n_classes = 2L)$stopped_early)
})

test_that("progress without a class count still advances", {
  p <- pam_train_progress(raw_log_fixture("loading"))
  expect_equal(p$phase, "loading")
  expect_equal(p$fraction, 0.1)
})

test_that("metrics can be read from partial text while a run is in progress", {
  m <- pam_train_parse_metrics(raw_log_fixture("training"))
  expect_equal(nrow(m$history), 1L)
  expect_equal(m$history$val_auprc, 0.0612)
  expect_true(is.na(m$best$auprc))
  m <- pam_train_parse_metrics(raw_log_fixture("end"))
  expect_equal(nrow(m$history), 3L)
  expect_equal(m$best$auprc, 0.07)
  expect_equal(c(m$n_train, m$n_val, m$n_labels), c(33L, 8L, 2L))
})

# --- form values -> options --------------------------------------------------------------

test_that("the defaults match the Analyzer 2.4.0 settings", {
  d <- pam_train_defaults()
  expect_equal(d$epochs, 50L)
  expect_equal(d$batch_size, 32L)
  expect_equal(d$learning_rate, 0.0001)
  expect_equal(d$val_split, 0.2)
  expect_equal(c(d$fmin, d$fmax), c(0L, 15000L))
  expect_equal(c(d$crop_mode, d$ups_mode, d$save_mode, d$out_format), c("center", "repeat", "replace", "tflite"))
})

test_that("valid form values give no errors", {
  expect_equal(pam_train_validate_inputs(form_values()), character())
})

test_that("each invalid value gives its own message key", {
  v <- function(...) pam_train_validate_inputs(form_values(...))
  expect_true("err_no_data" %in% v(train_dir = ""))
  expect_true("err_no_data" %in% v(train_dir = file.path(tempdir(), "nope_dir")))
  expect_true("err_test_dir" %in% v(test_dir = file.path(tempdir(), "nope_dir")))
  expect_true("err_no_output" %in% v(out_dir = ""))
  expect_true("err_name" %in% v(clf_name = ""))
  expect_true("err_name" %in% v(clf_name = "a/b"))
  expect_true("err_epochs" %in% v(epochs = 0))
  expect_true("err_epochs" %in% v(epochs = 2.5))
  expect_true("err_epochs" %in% v(epochs = NA_real_))
  expect_true("err_batch" %in% v(batch_size = 0))
  expect_true("err_lr" %in% v(learning_rate = 0))
  expect_true("err_hidden" %in% v(hidden_units = -1))
  expect_true("err_dropout" %in% v(dropout = 0.95))
  expect_true("err_val_split" %in% v(val_split = 1))
  expect_true("err_freq" %in% v(fmin = 5000, fmax = 4000))
  expect_true("err_freq" %in% v(fmax = 20000))
  expect_true("err_speed" %in% v(audio_speed = 0))
  expect_true("err_ups_ratio" %in% v(ups_ratio = 1.5))
  expect_true("err_runs" %in% v(n_runs = 0))
  expect_true("err_threads" %in% v(threads = 0))
})

test_that("conditional settings are only checked when they apply", {
  v <- function(...) pam_train_validate_inputs(form_values(...))
  expect_false("err_overlap" %in% v(crop_mode = "center", crop_overlap = 9))
  expect_true("err_overlap" %in% v(crop_mode = "segments", crop_overlap = 9))
  expect_false("err_focal" %in% v(focal = FALSE, f_gamma = -5))
  expect_true("err_focal" %in% v(focal = TRUE, f_gamma = -5))
  expect_false("err_autotune" %in% v(autotune = FALSE, at_trials = 0))
  expect_true("err_autotune" %in% v(autotune = TRUE, at_trials = 0))
})

test_that("a cache in load mode needs the cache file and not the training folder", {
  cache <- withr::local_tempfile(fileext = ".npz"); file.create(cache)
  expect_equal(pam_train_validate_inputs(form_values(train_dir = "", cache_mode = "load", cache_file = cache)),
               character())
  expect_true("err_cache_file" %in% pam_train_validate_inputs(
    form_values(train_dir = "", cache_mode = "load", cache_file = file.path(tempdir(), "no.npz"))))
})

test_that("form values become training options, passing only what applies", {
  o <- pam_train_params_from_inputs(form_values(train_dir = "E:/clips"))
  expect_equal(o$data_dir, "E:/clips")
  expect_null(o$test_data); expect_null(o$cache_mode); expect_null(o$cache_file)
  p <- o$params
  expect_equal(p$epochs, 50L)
  expect_equal(p$learning_rate, 0.0001)
  expect_equal(p$crop_mode, "center")
  expect_equal(c(p$model_format, p$model_save_mode, p$upsampling_mode), c("tflite", "replace", "repeat"))
  expect_false(p$focal_loss); expect_false(p$mixup); expect_false(p$autotune)
  expect_null(p$overlap); expect_null(p$focal_loss_gamma); expect_null(p$autotune_trials); expect_null(p$threads)

  p <- pam_train_params_from_inputs(form_values(crop_mode = "segments", crop_overlap = 1.5, focal = TRUE,
                                                f_gamma = 3, f_alpha = 0.4, autotune = TRUE, at_trials = 20,
                                                at_exec = 2, threads = 6, ups_mode = "smote",
                                                mixup = TRUE, label_smoothing = TRUE))$params
  expect_equal(p$overlap, 1.5)
  expect_equal(c(p$focal_loss_gamma, p$focal_loss_alpha), c(3, 0.4))
  expect_equal(c(p$autotune_trials, p$autotune_executions_per_trial), c(20L, 2L))
  expect_equal(p$threads, 6L)
  expect_equal(p$upsampling_mode, "smote")
  expect_true(p$mixup); expect_true(p$label_smoothing)
})

test_that("test folder and cache settings are passed on", {
  o <- pam_train_params_from_inputs(form_values(test_dir = "E:/test", cache_mode = "save", cache_file = "E:/c.npz"))
  expect_equal(o$test_data, "E:/test")
  expect_equal(o$cache_mode, "save")
  expect_equal(o$cache_file, "E:/c.npz")
  o <- pam_train_params_from_inputs(form_values(train_dir = "", cache_mode = "load", cache_file = "E:/c.npz"))
  expect_null(o$data_dir)
})

test_that("the options from the form always build a valid command", {
  # every option name the form produces must be one pam_birdnet_train_args() knows
  all_on <- pam_train_params_from_inputs(form_values(
    crop_mode = "smart", crop_overlap = 1, focal = TRUE, autotune = TRUE, threads = 4,
    mixup = TRUE, label_smoothing = TRUE, ups_mode = "linear", ups_ratio = 0.5,
    out_format = "both", save_mode = "append"))$params
  args <- pam_birdnet_train_args("data", "out/M", all_on)
  flags <- pam_birdnet_train_flags(args)
  expect_true(all(c("--epochs", "--focal-loss", "--mixup", "--autotune", "--model_format") %in% flags))
  expect_false(any(grepl("^--no-", flags)))
  plain <- pam_birdnet_train_args("data", "out/M", pam_train_params_from_inputs(form_values())$params)
  expect_false(any(c("--focal-loss", "--mixup", "--autotune", "--overlap") %in% plain))
})

test_that("run names are numbered only when there are several", {
  expect_equal(pam_train_run_names("out/M", 1), "out/M")
  expect_equal(pam_train_run_names("out/M", 3), c("out/M_run01", "out/M_run02", "out/M_run03"))
})

# --- results -------------------------------------------------------------------------------

test_that("the config snippet points at the trained model", {
  s <- pam_train_config_snippet("E:/models/My Model")
  expect_match(s, "birdnet:", fixed = TRUE)
  expect_match(s, "model_dir: \"E:/models\"", fixed = TRUE)
  expect_match(s, "classifier_name: \"My Model\"", fixed = TRUE)
  expect_equal(yaml::yaml.load(s)$birdnet$classifier_name, "My Model")
})

test_that("earlier runs are listed newest first with their scores and settings", {
  d <- withr::local_tempdir()
  write_run(d, "A", "2026-10-29 10:00:00", hidden = 0L)
  write_run(d, "B", "2026-10-29 12:00:00", hidden = 512L)
  write_run(d, "C", "2026-10-29 11:00:00", exit_status = 1L, best = FALSE)
  writeLines("not: [valid", file.path(d, "broken_run.yml"))
  tbl <- pam_train_runs_table(d)
  expect_equal(tbl$run, c("B", "C", "A"))
  expect_equal(tbl$status, c("ok", "failed", "ok"))
  expect_equal(tbl$hidden_units[tbl$run == "B"], 512L)
  expect_equal(tbl$epochs[tbl$run == "A"], 100L)
  expect_equal(tbl$auprc[tbl$run == "A"], 0.9)
  expect_true(is.na(tbl$auprc[tbl$run == "C"]))
  expect_equal(tbl$n_val[1], 171L)
})

test_that("no runs give an empty table with the same columns", {
  empty_dir <- withr::local_tempdir()
  a <- pam_train_runs_table(empty_dir)
  b <- pam_train_runs_table(file.path(tempdir(), "nope_dir"))
  expect_equal(nrow(a), 0L); expect_equal(nrow(b), 0L)
  expect_equal(names(a), names(b))
  expect_true(all(c("run", "auprc", "auroc", "status") %in% names(a)))
  expect_equal(nrow(pam_train_runs_table(NA_character_)), 0L)
})

test_that("the plots build, with and without data", {
  skip_if_not_installed("ggplot2")
  expect_s3_class(pam_train_plot_history(NULL), "ggplot")
  hist <- pam_train_parse_metrics(raw_log_fixture("end"))$history
  p <- pam_train_plot_history(hist, list(title = "T", x = "E", y = "S", auprc = "PR", auroc = "ROC"))
  expect_s3_class(p, "ggplot")
  expect_silent(ggplot2::ggplot_build(p))
  expect_equal(p$labels$title, "T")

  d <- withr::local_tempdir()
  write_run(d, "A", "2026-10-29 10:00:00"); write_run(d, "B", "2026-10-29 12:00:00")
  pr <- pam_train_plot_runs(pam_train_runs_table(d))
  expect_s3_class(pr, "ggplot")
  expect_silent(ggplot2::ggplot_build(pr))
  expect_s3_class(pam_train_plot_runs(pam_train_runs_table(withr::local_tempdir())), "ggplot")
})

# --- translations ------------------------------------------------------------------------------

test_that("English texts load and fill in values", {
  tr <- pam_i18n("en")
  expect_equal(tr("btn_start"), "Start training")
  expect_equal(tr("run_of", 2L, 5L), "Run 2 of 5")
  expect_match(tr("res_best", "0.900", "0.950", 10L, 50L), "AUPRC 0.900, AUROC 0.950 \\(epoch 10 of 50\\)")
  expect_equal(tr("no_such_key_xyz"), "no_such_key_xyz")                 # a gap is visible
})

test_that("an unknown language falls back to English", {
  expect_equal(pam_i18n("zz")("btn_start"), "Start training")
})

test_that("a translation only needs the texts it changes", {
  tmp <- withr::local_tempdir()
  file.copy(file.path(pam_i18n_dir(), "en.yml"), file.path(tmp, "en.yml"))
  writeLines(c("btn_start: \"Entrenar\"", "run_of: \"Ejecucion %d de %d\""), file.path(tmp, "xx.yml"), useBytes = TRUE)
  local_mocked_bindings(pam_i18n_dir = function() tmp)
  expect_setequal(pam_i18n_languages(), c("en", "xx"))
  tr <- pam_i18n("xx")
  expect_equal(tr("btn_start"), "Entrenar")
  expect_equal(tr("run_of", 1L, 2L), "Ejecucion 1 de 2")
  expect_equal(tr("btn_stop"), "Stop")                                  # not translated -> English
  withr::local_options(pamflow.lang = "xx")
  expect_equal(pam_i18n_default_lang(), "xx")
  expect_equal(pam_i18n()("btn_start"), "Entrenar")
})

test_that("the default language is English unless the environment names another available one", {
  withr::local_options(pamflow.lang = NULL)
  withr::local_envvar(PAMFLOW_LANG = "", LANGUAGE = "", LANG = "zz_ZZ.UTF-8")
  expect_equal(pam_i18n_default_lang(c("en", "es")), "en")
  withr::local_envvar(LANG = "es_ES.UTF-8")
  expect_equal(pam_i18n_default_lang(c("en", "es")), "es")
})

test_that("every text the app asks for exists in the English file", {
  src_dir <- testthat::test_path("..", "..", "R")
  files <- file.path(src_dir, c("birdnet_train_app.R", "birdnet_train_app_helpers.R"))
  skip_if_not(all(file.exists(files)), "R sources are not available (installed package)")
  txt <- paste(unlist(lapply(files, readLines, warn = FALSE)), collapse = "\n")
  grab <- function(pattern) {
    m <- regmatches(txt, gregexpr(pattern, txt, perl = TRUE))[[1L]]
    sub(pattern, "\\1", m, perl = TRUE)
  }
  input_ids <- c("cache_mode", "cache_file", "crop_mode", "crop_overlap",
                 "ups_mode", "ups_ratio", "save_mode")
  used <- unique(c(grab("\\btr\\(\"([a-z_0-9]+)\""),
                   grab("help_text\\(\"([a-z_0-9]+)\""),
                   grab("add\\(\"(err_[a-z_]+)\"\\)"),
                   grab("\"((?:fmt|cache|crop|ups|save)_[a-z]+)\""),
                   grab("\"((?:lbl|desc|help|sec|tab)_[a-z_0-9]+)\"")))
  used <- setdiff(used, input_ids)   # Shiny input ids, not translation keys
  have <- names(yaml::read_yaml(file.path(pam_i18n_dir(), "en.yml"), fileEncoding = "UTF-8"))
  expect_true(length(used) > 100L)
  expect_equal(setdiff(used, have), character())
})

# ---- test-set results table ----------------------------------------------------------------

fake_evaluation <- function() {
  cls <- data.frame(class = c("a", "b"), precision_default = c(0.5, 1), recall_default = c(0.4, 0.5),
                    f1_default = c(0.44, 0.67), precision_opt = c(0.6, 0.8), recall_opt = c(0.7, 0.9),
                    f1_opt = c(0.64, 0.85), auprc = c(0.71, 0.9), auroc = c(0.82, 0.95),
                    threshold = c(0.35, 0.25), tp = c(7, 9), fp = c(5, 2), tn = c(40, 38), fn = c(3, 1),
                    n_test = c(10, 10), pct = c(20, 20), stringsAsFactors = FALSE)
  list(overall = data.frame(class = "OVERALL (Macro-avg)", precision_default = 0.75, recall_default = 0.45,
                            f1_default = 0.55, precision_opt = 0.7, recall_opt = 0.8, f1_opt = 0.75,
                            auprc = 0.8, auroc = 0.89, threshold = NA_real_, tp = NA_real_, fp = NA_real_,
                            tn = NA_real_, fn = NA_real_, n_test = NA_real_, pct = NA_real_),
       classes = cls, path = "x")
}

test_that("the result table has an overall row first and picks the chosen threshold", {
  opt <- pam_train_eval_table(fake_evaluation(), "opt")
  expect_equal(nrow(opt), 3L)
  expect_equal(opt[[1]][1], "All classes (macro average)")
  expect_equal(opt$Precision[2], "0.600")
  expect_equal(opt$Threshold[2:3], c("0.35", "0.25"))
  def <- pam_train_eval_table(fake_evaluation(), "default")
  expect_equal(def$Precision[2], "0.500")
  expect_equal(def$Threshold[2], "0.50")
  expect_equal(def$AUPRC[2], "0.710")                 # threshold-free scores do not change
})

test_that("labels are translated and a missing evaluation gives NULL", {
  tbl <- pam_train_eval_table(fake_evaluation(), labels = list(class = "Clase", precision = "Precision x"))
  expect_true(all(c("Clase", "Precision x") %in% names(tbl)))
  expect_null(pam_train_eval_table(NULL))
  expect_null(pam_train_eval_counts(NULL))
})

test_that("confusion counts are shown as whole numbers", {
  cnt <- pam_train_eval_counts(fake_evaluation())
  expect_equal(names(cnt), c("Class", "TP", "FP", "FN", "TN"))
  expect_equal(cnt$TP, c("7", "9"))
  expect_equal(cnt$FN, c("3", "1"))
})

test_that("loading from a cache is shown as its own phase", {
  txt <- paste("Loading training data...", "\t...loading from cache: C:/x/c.npz", sep = "\n")
  p <- pam_train_progress(txt)
  expect_equal(p$phase, "cache")
  expect_gt(p$fraction, 0)
  expect_equal(pam_train_progress(paste(txt, "Building model...", sep = "\n"))$phase, "building")
})

test_that("a cache file may be given without .npz when loading", {
  cache <- file.path(withr::local_tempdir(), "clips")
  file.create(paste0(cache, ".npz"))
  x <- form_values(cache_mode = "load", cache_file = cache)
  expect_false("err_cache_file" %in% pam_train_validate_inputs(x))
  x$cache_file <- file.path(dirname(cache), "other")
  expect_true("err_cache_file" %in% pam_train_validate_inputs(x))
})

test_that("every translated text is a single string, even if YAML would read it as a number", {
  tr <- pam_i18n("en")
  keys <- names(yaml::read_yaml(file.path(pam_i18n_dir(), "en.yml"), fileEncoding = "UTF-8"))
  vals <- lapply(keys, tr)
  expect_true(all(vapply(vals, is.character, logical(1))))
  expect_true(all(lengths(vals) == 1L))
  expect_equal(tr("thr_default"), "0.5")
})

test_that("a language file with a bare number is read as text", {
  dir <- withr::local_tempdir()
  writeLines(c("app_title: Test", "thr_default: 0.5"), file.path(dir, "en.yml"))
  local_mocked_bindings(pam_i18n_dir = function() dir)
  expect_identical(pam_i18n("en")("thr_default"), "0.5")
})
