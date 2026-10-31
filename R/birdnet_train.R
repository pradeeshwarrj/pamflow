#' Training parameters and their command-line flags (internal)
#'
#' One entry per `birdnet-train` option pamflow exposes, using the option names
#' of BirdNET-Analyzer 2.4.0. `name` is the R-side name (used in the `params`
#' list), `flag` the exact command-line flag. No defaults are stored: options
#' the user does not set are left to the installed Analyzer, so an unmodified
#' run matches that version's own defaults. Yes/no options are on/off switches
#' in 2.4.0: they are passed when TRUE and omitted when FALSE.
#'
#' @return A named list of parameter specifications.
#' @keywords internal
#' @noRd
pam_train_param_spec <- function() {
  s <- function(name, flag, type, choices = NULL) {
    list(name = name, flag = flag, type = type, choices = choices)
  }
  spec <- list(
    s("epochs", "--epochs", "int"),
    s("val_split", "--val_split", "dbl"),
    s("learning_rate", "--learning_rate", "dbl"),
    s("batch_size", "--batch_size", "int"),
    s("threads", "--threads", "int"),
    s("crop_mode", "--crop_mode", "chr", c("center", "first", "segments", "smart")),
    s("overlap", "--overlap", "dbl"),
    s("fmin", "--fmin", "int"),
    s("fmax", "--fmax", "int"),
    s("audio_speed", "--audio_speed", "dbl"),
    s("hidden_units", "--hidden_units", "int"),
    s("dropout", "--dropout", "dbl"),
    s("focal_loss", "--focal-loss", "lgl"),
    s("focal_loss_gamma", "--focal-loss-gamma", "dbl"),
    s("focal_loss_alpha", "--focal-loss-alpha", "dbl"),
    s("label_smoothing", "--label_smoothing", "lgl"),
    s("mixup", "--mixup", "lgl"),
    s("upsampling_ratio", "--upsampling_ratio", "dbl"),
    s("upsampling_mode", "--upsampling_mode", "chr", c("repeat", "linear", "mean", "smote")),
    s("model_save_mode", "--model_save_mode", "chr", c("replace", "append")),
    s("model_format", "--model_format", "chr", c("tflite", "raven", "both")),
    s("autotune", "--autotune", "lgl"),
    s("autotune_trials", "--autotune_trials", "int"),
    s("autotune_executions_per_trial", "--autotune_executions_per_trial", "int")
  )
  stats::setNames(spec, vapply(spec, `[[`, character(1), "name"))
}

#' Convert one parameter value to command-line arguments (internal)
#'
#' @param spec One entry of `pam_train_param_spec()`.
#' @param value The user's value.
#' @return Character vector (flag followed by its value(s)).
#' @keywords internal
#' @noRd
pam_train_format_param <- function(spec, value) {
  bad <- function(why) {
    rlang::abort(sprintf("Training parameter '%s' %s", spec$name, why))
  }
  switch(
    spec$type,
    lgl = {
      if (!is.logical(value) || length(value) != 1L || is.na(value)) bad("must be TRUE or FALSE")
      if (value) spec$flag else character()   # on/off switch: FALSE = leave it off
    },
    int = {
      if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value != round(value)) {
        bad("must be a single whole number")
      }
      c(spec$flag, as.character(as.integer(value)))
    },
    dbl = {
      if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) {
        bad("must be a single finite number")
      }
      c(spec$flag, format(value, scientific = FALSE, trim = TRUE, digits = 15))
    },
    chr = {
      if (!is.character(value) || !length(value) || anyNA(value)) bad("must be character")
      if (!is.null(spec$choices) && !all(value %in% spec$choices)) {
        bad(sprintf("must be one of: %s", paste(spec$choices, collapse = ", ")))
      }
      if (length(value) > 1L) bad("must be a single value")
      c(spec$flag, value)
    }
  )
}

#' Build the `birdnet-train` command-line arguments (internal)
#'
#' Pure function (no I/O), so it can be tested. Only the parameters the user
#' set are passed; everything else is left to the installed Analyzer. The
#' values the Analyzer actually used are written to its `_Params.csv`.
#'
#' @param data_dir Training folder (one sub-folder per class).
#' @param output Output path prefix for the trained classifier.
#' @param params Named list of parameter values (see `pam_train_param_spec()`).
#'   A NULL value is ignored.
#' @param load_params Path to a previous run's parameters file, or NULL (only
#'   works with Analyzer versions that provide `--load_params`).
#' @param test_data Optional separate test folder.
#' @param cache_mode NULL, "save" or "load" (the Analyzer's `--cache_mode`).
#' @param cache_file Cache file path, used with `cache_mode`.
#' @return Character vector of arguments.
#' @keywords internal
#' @noRd
pam_birdnet_train_args <- function(data_dir, output, params = list(), load_params = NULL,
                                   test_data = NULL, cache_mode = NULL,
                                   cache_file = paste0(output, "_cache.npz")) {
  spec <- pam_train_param_spec()
  if (length(params) && (is.null(names(params)) || any(!nzchar(names(params))))) {
    rlang::abort("`params` must be a named list")
  }
  unknown <- setdiff(names(params), names(spec))
  if (length(unknown)) {
    rlang::abort(c("Unknown training parameter(s):", stats::setNames(unknown, rep("x", length(unknown))),
                   i = paste("Supported:", paste(names(spec), collapse = ", "))))
  }
  if (!is.null(cache_mode) && !(length(cache_mode) == 1L && cache_mode %in% c("save", "load"))) {
    rlang::abort("`cache_mode` must be NULL, \"save\" or \"load\"")
  }
  values <- params[!vapply(params, is.null, logical(1))]

  param_args <- unlist(lapply(names(values), function(nm) {
    pam_train_format_param(spec[[nm]], values[[nm]])
  }), use.names = FALSE)

  c(data_dir, "-o", output,
    if (!is.null(test_data)) c("--test_data", test_data),
    if (!is.null(cache_mode)) c("--cache_mode", cache_mode, "--cache_file", cache_file),
    if (!is.null(load_params)) c("--load_params", load_params),
    param_args)
}

#' Flags used in an argument vector (internal)
#'
#' @param args Character vector from `pam_birdnet_train_args()`.
#' @return Unique flags (tokens starting with `--`).
#' @keywords internal
#' @noRd
pam_birdnet_train_flags <- function(args) {
  unique(args[grepl("^--[A-Za-z]", args)])
}

#' Flags the installed `birdnet-train` does not mention in its help (internal)
#'
#' Guards against the Analyzer changing its options between versions.
#'
#' @param flags Flags used.
#' @param help_text Output of `birdnet-train --help`.
#' @return Character vector of unsupported flags (empty if all are supported).
#' @keywords internal
#' @noRd
pam_birdnet_unsupported_flags <- function(flags, help_text) {
  help_text <- paste(help_text, collapse = "\n")
  # match whole flags only: `--focal-loss` must not match `--focal-loss-gamma`
  supported <- vapply(flags, function(f) {
    grepl(paste0("(^|[^A-Za-z0-9_-])", f, "($|[^A-Za-z0-9_-])"), help_text, perl = TRUE)
  }, logical(1))
  flags[!supported]
}

#' Path of the `birdnet-train` executable in an environment (internal)
#'
#' @param envdir Training environment folder.
#' @return Path (may not exist).
#' @keywords internal
#' @noRd
pam_birdnet_train_bin <- function(envdir) {
  if (.Platform$OS.type == "windows") {
    file.path(envdir, "Scripts", "birdnet-train.exe")
  } else {
    file.path(envdir, "bin", "birdnet-train")
  }
}

#' Text of `birdnet-train --help` (internal)
#'
#' @param bin Path to `birdnet-train`.
#' @return Character vector (empty on failure).
#' @keywords internal
#' @noRd
pam_birdnet_train_help <- function(bin) {
  tryCatch(suppressWarnings(system2(bin, "--help", stdout = TRUE, stderr = TRUE)),
           error = function(e) character())
}

#' Start an external command as a background job (internal)
#'
#' The job runs without blocking R. Its output (stdout and stderr together) is
#' collected with `pam_job_poll()` and written to `log_file`. The command is
#' registered with a supervisor and started so that it and everything it
#' launches can be stopped together (`pam_job_stop()`).
#'
#' @param bin Executable.
#' @param args Arguments (not shell-quoted).
#' @param log_file File that receives the combined output.
#' @return A job: an environment with `p` (the process, NULL if it could not be
#'   started), `closed`, `status` and `log_file`. If the command could not be
#'   started the job is already closed with status 127.
#' @keywords internal
#' @noRd
pam_job_start <- function(bin, args, log_file) {
  job <- new.env(parent = emptyenv())
  job$log_file <- log_file
  job$p <- NULL
  job$log_con <- NULL
  job$closed <- FALSE
  job$status <- NA_integer_
  p <- tryCatch(
    processx::process$new(bin, args, stdout = "|", stderr = "2>&1",
                          env = c("current", PYTHONIOENCODING = "utf-8"),
                          cleanup = TRUE, cleanup_tree = TRUE, supervise = TRUE,
                          encoding = "UTF-8"),
    error = function(e) e)
  if (inherits(p, "error")) {
    writeLines(conditionMessage(p), log_file)
    job$closed <- TRUE
    job$status <- 127L
    return(job)
  }
  job$p <- p
  job$log_con <- file(log_file, open = "wb")
  job
}

#' Write text to a job's log (internal)
#' @keywords internal
#' @noRd
pam_job_write <- function(job, txt) {
  if (length(txt) == 1L && !is.na(txt) && nzchar(txt) && !is.null(job$log_con)) {
    writeBin(charToRaw(enc2utf8(txt)), job$log_con)
  }
  invisible(txt)
}

#' Is the job's process still running? (internal)
#' @keywords internal
#' @noRd
pam_job_alive <- function(job) {
  !isTRUE(job$closed) && !is.null(job$p) && job$p$is_alive()
}

#' Run an expression, but treat a closed output pipe as "nothing to read" (internal)
#'
#' When a process is killed, processx closes its pipes and reading them raises
#' an "invalid connection" error. Only that error is tolerated: anything else,
#' including a time limit or another interruption signalled as an error, must
#' reach the caller, otherwise an aborted run would carry on to the end.
#'
#' @param expr Expression that reads from the process.
#' @param default Value returned when the pipe is closed.
#' @return The value of `expr`, or `default`.
#' @keywords internal
#' @noRd
pam_tolerate_closed_pipe <- function(expr, default) {
  tryCatch(expr, error = function(e) {
    if (grepl("connection", conditionMessage(e), ignore.case = TRUE)) default else stop(e)
  })
}

#' Collect the output a job has produced so far (internal)
#'
#' @param job A job from `pam_job_start()`.
#' @param wait_ms Milliseconds to wait for output (0 = do not wait). R can be
#'   interrupted during the wait.
#' @return The new text (a single string, possibly empty); also written to the log.
#' @keywords internal
#' @noRd
pam_job_poll <- function(job, wait_ms = 0L) {
  if (isTRUE(job$closed) || is.null(job$p)) return("")
  if (wait_ms > 0L) job$p$poll_io(wait_ms)
  # A killed process closes its pipes; treat that as "no more output"
  txt <- pam_tolerate_closed_pipe(job$p$read_output(), "")
  pam_job_write(job, txt)
  txt
}

#' Collect all remaining output of a finished job (internal)
#' @keywords internal
#' @noRd
pam_job_drain <- function(job) {
  if (isTRUE(job$closed) || is.null(job$p) || job$p$is_alive()) return("")
  txt <- pam_tolerate_closed_pipe(job$p$read_all_output(), "")
  pam_job_write(job, txt)
  txt
}

#' Stop a running job and everything it started (internal)
#'
#' Also sweeps up BirdNET worker processes whose parent is gone
#' (`pam_birdnet_cleanup()`).
#' @keywords internal
#' @noRd
pam_job_stop <- function(job) {
  if (pam_job_alive(job)) {
    try(job$p$kill_tree(), silent = TRUE)
    try(pam_birdnet_cleanup(quiet = TRUE), silent = TRUE)
  }
  invisible(job)
}

#' Close a job: collect what is left, close the log, return the exit status (internal)
#' @return Integer exit status (NA if the process was killed).
#' @keywords internal
#' @noRd
pam_job_close <- function(job) {
  if (isTRUE(job$closed)) return(job$status)
  pam_job_drain(job)
  if (!is.null(job$log_con)) {
    try(close(job$log_con), silent = TRUE)
    job$log_con <- NULL
  }
  job$status <- if (is.null(job$p)) {
    127L
  } else {
    pam_tolerate_closed_pipe(as.integer(job$p$get_exit_status()), NA_integer_)
  }
  job$closed <- TRUE
  job$status
}

#' Run an external command and wait for it (internal; replaced by a mock in tests)
#'
#' Waits in a loop that R can interrupt. Output (stdout and stderr together) is
#' always written to `log_file`; with `live` it is also shown on the console. If
#' the call is interrupted (Esc), fails, or R itself exits, the command and every
#' process it started (for example the BirdNET worker processes) are stopped, so
#' nothing keeps running in the background.
#'
#' @param bin Executable.
#' @param args Arguments (not shell-quoted).
#' @param log_file File that receives the combined output.
#' @param live If TRUE, also stream the output to the console.
#' @return Integer exit status (127 if the command could not be started).
#' @keywords internal
#' @noRd
pam_run_command <- function(bin, args, log_file, live = FALSE) {
  job <- pam_job_start(bin, args, log_file)
  if (isTRUE(job$closed)) return(job$status)
  on.exit({ pam_job_stop(job); pam_job_close(job) }, add = TRUE)   # interrupt, error, or normal exit
  while (pam_job_alive(job)) {
    txt <- pam_job_poll(job, 500L)           # waits up to 0.5 s; R can be interrupted here
    if (live && nzchar(txt)) cat(txt)
  }
  rest <- pam_job_drain(job)
  if (live && nzchar(rest)) cat(rest)
  as.integer(pam_job_close(job))
}

#' Read training metrics from a `birdnet-train` log
#'
#' Extracts the per-epoch history and the final summary that the Analyzer
#' prints, so runs can be compared (for example with the Analyzer GUI) without
#' reading the log by hand.
#'
#' @param log_file Path to a training log (`<output>_train.log`).
#' @return A list: `history` (data.frame with `epoch`, `auprc`, `auroc`, `loss`,
#'   `val_auprc`, `val_auroc`, `val_loss`, `learning_rate`), `best` (list with
#'   `auprc`, `auroc`, `loss`, `epoch`, `n_epochs`; NA when not printed),
#'   `n_train`, `n_val`, `n_labels` (NA if not found) and `evaluated_on`
#'   ("validation" or "test").
#' @details The log format is the one printed by BirdNET-Analyzer 2.4.0. If the
#'   trainer prints something else, the fields come back empty or NA rather
#'   than guessed. Terminal progress bars and TensorFlow messages in the log
#'   are ignored.
#' @examples
#' \dontrun{
#' m <- pam_birdnet_train_metrics("E:/models/MyModel_train.log")
#' m$best$auprc
#' }
#' @export
pam_birdnet_train_metrics <- function(log_file) {
  if (!file.exists(log_file)) rlang::abort(sprintf("Log file not found: %s", log_file))
  text <- paste(readLines(log_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  pam_train_parse_metrics(text)
}

#' Read training metrics from the text of a `birdnet-train` log (internal)
#'
#' Works on partial text too (a run still in progress), so the history grows as
#' epochs finish.
#'
#' @param text The log text (a single string).
#' @return The list described in `pam_birdnet_train_metrics()`.
#' @keywords internal
#' @noRd
pam_train_parse_metrics <- function(text) {
  text <- gsub("\r", "\n", text, fixed = TRUE)
  num <- "[0-9][0-9.eE+-]*"

  # per-epoch lines: training and validation metrics together
  pat <- sprintf(paste0("(?<![_A-Za-z])AUPRC: (%s) - AUROC: (%s) - loss: (%s) - ",
                        "val_AUPRC: (%s) - val_AUROC: (%s) - val_loss: (%s)",
                        "(?: - learning_rate: (%s))?"), num, num, num, num, num, num, num)
  hits <- regmatches(text, gregexpr(pat, text, perl = TRUE))[[1L]]
  history <- if (length(hits)) {
    g <- utils::strcapture(pat, hits,
                           data.frame(auprc = numeric(), auroc = numeric(), loss = numeric(),
                                      val_auprc = numeric(), val_auroc = numeric(),
                                      val_loss = numeric(), learning_rate = numeric()),
                           perl = TRUE)
    cbind(epoch = seq_len(nrow(g)), g)
  } else {
    data.frame(epoch = integer(), auprc = numeric(), auroc = numeric(), loss = numeric(),
               val_auprc = numeric(), val_auroc = numeric(), val_loss = numeric(),
               learning_rate = numeric())
  }

  # final summary line
  best_pat <- sprintf(paste0("Best AUPRC: (%s), Best AUROC: (%s), Best Loss: (%s) ",
                             "\\(epoch ([0-9]+)/([0-9]+)\\)"), num, num, num)
  bm <- regmatches(text, regexec(best_pat, text, perl = TRUE))[[1L]]
  best <- if (length(bm) == 6L) {
    list(auprc = as.numeric(bm[2L]), auroc = as.numeric(bm[3L]), loss = as.numeric(bm[4L]),
         epoch = as.integer(bm[5L]), n_epochs = as.integer(bm[6L]))
  } else {
    list(auprc = NA_real_, auroc = NA_real_, loss = NA_real_,
         epoch = NA_integer_, n_epochs = NA_integer_)
  }

  grab <- function(pattern, i = 2L) {
    m <- regmatches(text, regexec(pattern, text, perl = TRUE))[[1L]]
    if (length(m) >= i) as.integer(m[i]) else NA_integer_
  }
  list(history = history, best = best,
       n_train = grab("Training on ([0-9]+) samples"),
       n_val = grab("validating on ([0-9]+) samples"),
       n_labels = grab("Loaded [0-9]+ training samples and ([0-9]+) labels"),
       evaluated_on = if (grepl("Using validation metrics", text, fixed = TRUE)) "validation" else "test")
}

#' Check a training dataset before training
#'
#' Looks at the folder-per-class layout BirdNET-Analyzer expects and reports
#' problems early: missing or empty classes, very small classes, files that
#' are not audio, and a missing non-event class.
#'
#' @param data_dir Training folder with one sub-folder per class.
#' @param min_clips Classes (other than noise classes) with fewer audio files
#'   are flagged. A rule of thumb for your own data, not an Analyzer limit.
#' @param quiet If TRUE, do not print the report.
#' @return Invisibly, a list: `classes` (data.frame with `class`, `n_audio`,
#'   `n_other`, `n_subdirs`, `is_noise`), `issues` (character) and `ok`
#'   (TRUE if there are no issues).
#' @details Audio files are counted by extension (wav, flac, mp3, ogg, m4a);
#'   clip length is not inspected. The Analyzer's documentation recommends
#'   3-second clips and a background class named noise, other, background or
#'   silence.
#' @examples
#' \dontrun{
#' pam_birdnet_train_prepare("E:/training_clips")
#' }
#' @export
pam_birdnet_train_prepare <- function(data_dir, min_clips = 20L, quiet = FALSE) {
  if (!dir.exists(data_dir)) rlang::abort(sprintf("Training folder not found: %s", data_dir))
  classes <- list.dirs(data_dir, recursive = FALSE, full.names = FALSE)
  if (!length(classes)) {
    rlang::abort("No class sub-folders found: put the clips of each class in its own sub-folder.")
  }
  noise_names <- c("noise", "other", "background", "silence")
  audio_re <- "\\.(wav|flac|mp3|ogg|m4a)$"

  rows <- lapply(classes, function(cl) {
    path <- file.path(data_dir, cl)
    entries <- list.files(path, full.names = FALSE, include.dirs = TRUE)
    is_dir <- dir.exists(file.path(path, entries))
    files <- entries[!is_dir]
    is_audio <- grepl(audio_re, files, ignore.case = TRUE)
    data.frame(class = cl, n_audio = sum(is_audio), n_other = sum(!is_audio),
               n_subdirs = sum(is_dir), is_noise = tolower(cl) %in% noise_names,
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)

  issues <- character()
  collapse <- function(x) paste(x, collapse = ", ")
  if (any(out$n_audio == 0L)) {
    issues <- c(issues, sprintf("Classes with no audio files: %s", collapse(out$class[out$n_audio == 0L])))
  }
  low <- out$class[out$n_audio > 0L & out$n_audio < min_clips & !out$is_noise]
  if (length(low)) {
    issues <- c(issues, sprintf("Classes with fewer than %d clips: %s", as.integer(min_clips), collapse(low)))
  }
  if (any(out$n_other > 0L)) {
    issues <- c(issues, sprintf("Non-audio files found in: %s", collapse(out$class[out$n_other > 0L])))
  }
  if (any(out$n_subdirs > 0L)) {
    issues <- c(issues, sprintf("Sub-folders inside class folders (check they are intended): %s",
                                collapse(out$class[out$n_subdirs > 0L])))
  }
  if (!any(out$is_noise)) {
    issues <- c(issues, "No non-event class (noise, other, background or silence); recommended to reduce false positives")
  }
  if (sum(!out$is_noise) < 1L) {
    issues <- c(issues, "No target classes: only noise classes were found")
  }

  res <- list(classes = out, issues = issues, ok = !length(issues))
  if (!quiet) {
    cli::cli_alert_info("{nrow(out)} class folder{?s}, {sum(out$n_audio)} audio file{?s}")
    if (res$ok) cli::cli_alert_success("No problems found") else {
      for (i in issues) cli::cli_alert_warning("{i}")
    }
  }
  invisible(res)
}

#' Train a custom BirdNET classifier from R
#'
#' Runs BirdNET-Analyzer's own `birdnet-train` command inside pamflow's
#' training environment, so the trained model is the same kind of file the
#' Analyzer GUI produces. The training runs in a separate process: an error
#' or crash cannot take down your R session.
#'
#' This is a standalone tool: it is not a stage of the workflow and no workflow
#' function calls it. Use the trained model by pointing the `birdnet:` section of
#' the config at it.
#'
#' @param data_dir Training folder with one sub-folder per class. Use
#'   `pam_birdnet_train_prepare()` first.
#' @param output Output path prefix, e.g. `"E:/models/MyModel"`. The Analyzer
#'   writes `<output>.tflite`, `<output>_Labels.txt`, `<output>_Params.csv`
#'   and `<output>_sample_counts.csv`. pamflow adds `<output>_run.yml` (what
#'   was run) and `<output>_train.log` (everything the trainer printed) and
#'   uses `<output>_cache.npz` only if you set `cache_mode`.
#' @param params Named list of training parameters. Names:
#'   epochs, val_split, learning_rate, batch_size, threads, crop_mode,
#'   overlap, fmin, fmax, audio_speed, hidden_units, dropout, focal_loss,
#'   focal_loss_gamma, focal_loss_alpha, label_smoothing, mixup,
#'   upsampling_ratio, upsampling_mode, model_save_mode, model_format
#'   ("tflite", "raven" or "both"), autotune, autotune_trials,
#'   autotune_executions_per_trial. Yes/no options are on/off switches:
#'   `TRUE` turns them on, `FALSE` leaves them off.
#'   Anything you do not set is left to the installed Analyzer, so a plain
#'   run uses the same defaults as that version's own command line. The values
#'   it actually used are written to `<output>_Params.csv`.
#' @param test_data Optional separate test folder; if NULL the Analyzer holds
#'   out `val_split` of the training data.
#' @param load_params Optional path to an earlier run's parameters file, passed
#'   as `--load_params`. Only Analyzer versions that provide that option accept
#'   it; otherwise pamflow stops with a clear message.
#' @param cache_mode NULL (default), "save" or "load": passed as `--cache_mode`.
#'   Left off by default so a plain run behaves exactly like the Analyzer. With
#'   "load" the features are read from `cache_file` instead of the audio (the
#'   training folder may then be NULL).
#' @param cache_file Cache file for `cache_mode`; defaults to `<output>_cache.npz`. A
#'   relative path is taken relative to the folder of `output`, not the working directory.
#' @param envdir Training environment folder (from `pam_birdnet_setup("training")`).
#' @param live If TRUE, also show the trainer's output on the console while it
#'   runs. The log file is written either way.
#' @param overwrite If FALSE (default), refuse to overwrite an existing model.
#' @param log_dir Optional folder for a log file (`birdnet_train.log`).
#' @return Invisibly, a list: `status` ("ok" or "failed"), `output`, `files`
#'   (named logical: which expected files exist), `elapsed` (difftime),
#'   `log`, `run_record`, `args`, and `metrics` (from
#'   `pam_birdnet_train_metrics()`, NULL if the log could not be read) and
#'   `evaluation` (with a separate `test_data` folder: a list with `overall`,
#'   `classes` and `path` read from `<output>_evaluation.csv`, one row per class
#'   with precision, recall, F1, AUPRC and AUROC; otherwise NULL) and, when a cache
#'   was used, `cache` (what the trainer reported: see `pam_train_cache_notes()`).
#' @details This is a standalone tool, not a pipeline stage: it needs no config file
#'   and nothing in the workflow calls it. Assumptions: BirdNET-Analyzer is installed in the training
#'   environment and provides the `birdnet-train` command. Hyperparameter
#'   autotuning needs the Analyzer's `train` extra
#'   (`pam_birdnet_setup("training", packages = "birdnet-analyzer[train]",
#'   recreate = TRUE)`). Before running, pamflow checks that every option it
#'   passes appears in the installed `birdnet-train --help` and stops with a
#'   clear message if one does not.
#' @examples
#' \dontrun{
#' prep <- pam_birdnet_train_prepare("E:/training_clips")
#' res <- pam_birdnet_train("E:/training_clips", "E:/models/MyModel",
#'                          params = list(epochs = 100, hidden_units = 512))
#' # reproduce an earlier run from its parameters file
#' pam_birdnet_train("E:/training_clips", "E:/models/Rerun",
#'                   load_params = "E:/models/BirdNet_v2_custom_Params.csv")
#' }
#' @references Kahl, S., Wood, C. M., Eibl, M. and Klinck, H. (2021). BirdNET: A deep
#'   learning solution for avian diversity monitoring. *Ecological Informatics*, 61,
#'   101236. \doi{10.1016/j.ecoinf.2021.101236}
#' @export
pam_birdnet_train <- function(data_dir, output, params = list(), test_data = NULL,
                              load_params = NULL, cache_mode = NULL, cache_file = NULL,
                              envdir = pam_birdnet_env_dir("training"),
                              live = FALSE, overwrite = FALSE, log_dir = NULL) {
  plan <- pam_train_plan(data_dir, output, params, test_data, load_params, cache_mode,
                         cache_file, envdir, overwrite)
  pam_log("INFO", sprintf("training started: %s -> %s", plan$data_dir, output),
          "birdnet_train", log_dir)
  t0 <- Sys.time()
  status <- pam_run_command(plan$bin, plan$args, plan$log_file, live = live)
  elapsed <- difftime(Sys.time(), t0, units = "mins")
  pam_train_finish(plan, status, elapsed, log_dir = log_dir)
}

#' Cache file path as the Analyzer writes it (internal)
#'
#' The Analyzer saves the cache with NumPy, which adds `.npz` when the name does
#' not end with it. The same rule is applied here so that Save and Load agree.
#'
#' @param path A cache file path, or NULL.
#' @return The path ending in `.npz` (NULL and empty strings are returned unchanged).
#' @keywords internal
#' @noRd
pam_train_cache_path <- function(path) {
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(path)
  if (grepl("\\.npz$", path, ignore.case = TRUE)) path else paste0(path, ".npz")
}

#' Check everything for a training run and build its command (internal)
#'
#' The "plan" step shared by `pam_birdnet_train()` and the training app: it
#' validates the inputs, builds the `birdnet-train` arguments and makes sure the
#' installed Analyzer supports every option, but starts nothing.
#'
#' @inheritParams pam_birdnet_train
#' @return A plan: a list with `bin`, `args`, `log_file`, `output`, `model_file`,
#'   `data_dir`, `test_data`, `load_params`, `cache_mode`, `cache_file`, `params`.
#' @keywords internal
#' @noRd
pam_train_plan <- function(data_dir, output, params = list(), test_data = NULL,
                           load_params = NULL, cache_mode = NULL, cache_file = NULL,
                           envdir = pam_birdnet_env_dir("training"), overwrite = FALSE) {
  if (is.null(cache_file)) {
    cache_file <- paste0(output, "_cache.npz")
  } else if (!fs::is_absolute_path(cache_file)) {
    # the trainer runs in R's working directory; keep a relative name next to the model instead
    cache_file <- file.path(dirname(output), cache_file)
  }
  cache_file <- pam_train_cache_path(cache_file)
  loading_cache <- identical(cache_mode, "load")
  if (loading_cache) {
    if (!file.exists(cache_file)) rlang::abort(sprintf("Cache file not found: %s", cache_file))
    # features come from the cache; the trainer still needs a positional input
    input <- if (!is.null(data_dir) && dir.exists(data_dir)) data_dir else cache_file
  } else {
    if (is.null(data_dir) || !dir.exists(data_dir)) {
      rlang::abort(sprintf("Training folder not found: %s", paste(data_dir, collapse = "")))
    }
    input <- data_dir
  }
  if (!is.null(test_data) && !dir.exists(test_data)) {
    rlang::abort(sprintf("Test folder not found: %s", test_data))
  }
  if (!is.null(load_params) && !file.exists(load_params)) {
    rlang::abort(sprintf("Parameters file not found: %s", load_params))
  }
  bin <- pam_birdnet_train_bin(envdir)
  if (!file.exists(bin)) {
    rlang::abort(c(sprintf("birdnet-train not found at %s", bin),
                   i = "Run pam_birdnet_setup('training') and then pam_birdnet_doctor()."))
  }
  model_file <- paste0(output, ".tflite")
  if (file.exists(model_file) && !overwrite) {
    rlang::abort(c(sprintf("A model already exists at %s", model_file),
                   i = "Choose another `output`, or set overwrite = TRUE."))
  }
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)

  args <- pam_birdnet_train_args(input, output, params, load_params, test_data,
                                 cache_mode, cache_file)

  unsupported <- pam_birdnet_unsupported_flags(pam_birdnet_train_flags(args),
                                               pam_birdnet_train_help(bin))
  if (length(unsupported)) {
    rlang::abort(c("The installed BirdNET-Analyzer does not list these options:",
                   stats::setNames(unsupported, rep("x", length(unsupported))),
                   i = "Check `birdnet-train --help` in the training environment (version change, or the 'train' extra for autotune)."))
  }
  list(bin = bin, args = args, log_file = paste0(output, "_train.log"), output = output,
       model_file = model_file, data_dir = data_dir, test_data = test_data,
       load_params = load_params, cache_mode = cache_mode, cache_file = cache_file,
       params = params)
}

#' Read the test-set evaluation written by `birdnet-train` (internal)
#'
#' When a separate test folder is given, the Analyzer writes
#' `<output>_evaluation.csv`: one row of macro averages and one row per class,
#' with precision, recall and F1 at the default threshold (0.5) and at a
#' per-class threshold that maximises F1, plus AUPRC, AUROC, the confusion
#' counts at that threshold and the number of test clips. The Analyzer writes the
#' file in the computer's default text encoding; if it is not valid UTF-8 it is
#' read as Windows-1252, so species names with accents survive.
#'
#' @param output Output path without extension (as given to `pam_birdnet_train()`).
#' @param newer_than Optional time; an evaluation file older than this belongs to an
#'   earlier run and is ignored.
#' @return NULL when there is no evaluation file or it cannot be read; otherwise
#'   a list with `overall` (one-row data frame of macro averages), `classes`
#'   (one row per class) and `path`. Columns: `class`, `precision_default`,
#'   `recall_default`, `f1_default`, `precision_opt`, `recall_opt`, `f1_opt`,
#'   `auprc`, `auroc`, `threshold`, `tp`, `fp`, `tn`, `fn`, `n_test`, `pct`.
#' @keywords internal
#' @noRd
pam_train_read_evaluation <- function(output, newer_than = NULL) {
  path <- paste0(output, "_evaluation.csv")
  if (!file.exists(path)) return(NULL)
  if (!is.null(newer_than) && file.mtime(path) < newer_than) return(NULL)   # left over from an earlier run
  raw <- tryCatch(readBin(path, "raw", n = file.size(path)), error = function(e) NULL)
  if (is.null(raw) || !length(raw)) return(NULL)
  txt <- rawToChar(raw)
  Encoding(txt) <- "UTF-8"
  if (!validUTF8(txt)) {
    Encoding(txt) <- "unknown"
    txt <- iconv(txt, from = "windows-1252", to = "UTF-8", sub = "?")
  }
  txt <- sub("^\ufeff", "", txt)      # drop a byte-order mark if present
  lines <- strsplit(txt, "\r?\n")[[1L]]
  lines <- lines[nzchar(lines)]
  if (length(lines) < 2L) return(NULL)
  df <- tryCatch(utils::read.csv(text = lines, check.names = FALSE, stringsAsFactors = FALSE,
                                 colClasses = "character"),
                 error = function(e) NULL)
  if (is.null(df) || !nrow(df) || !"Class" %in% names(df)) return(NULL)
  map <- c("Class" = "class",
           "Precision (0.5)" = "precision_default", "Recall (0.5)" = "recall_default",
           "F1 Score (0.5)" = "f1_default", "Precision (opt)" = "precision_opt",
           "Recall (opt)" = "recall_opt", "F1 Score (opt)" = "f1_opt",
           "AUPRC" = "auprc", "AUROC" = "auroc", "Optimal Threshold" = "threshold",
           "True Positives" = "tp", "False Positives" = "fp", "True Negatives" = "tn",
           "False Negatives" = "fn", "Samples" = "n_test", "Percentage (%)" = "pct")
  out <- data.frame(class = df[["Class"]], stringsAsFactors = FALSE)
  for (header in setdiff(names(map), "Class")) {
    out[[map[[header]]]] <- if (header %in% names(df)) suppressWarnings(as.numeric(df[[header]])) else NA_real_
  }
  is_overall <- startsWith(out$class, "OVERALL")
  list(overall = if (any(is_overall)) out[which(is_overall)[1L], , drop = FALSE] else NULL,
       classes = out[!is_overall, , drop = FALSE], path = path)
}

#' Read what the trainer said about the cache (internal)
#'
#' With `cache_mode = "load"` the Analyzer takes the clips, the frequency range,
#' the speed and the cropping from the cache file. If those differ from the
#' current settings it only prints a warning and goes on with the cache's values;
#' if the cache file is missing it quietly reads the training folder instead.
#'
#' @param text The training log as one string.
#' @return A list: `used` (TRUE if the features were loaded from the cache),
#'   `mismatch` (TRUE if the Analyzer warned that the cache settings differ),
#'   `cache_settings` (the lines it printed about the cache, trimmed) and
#'   `missing` (TRUE if it did not find the cache file).
#' @keywords internal
#' @noRd
pam_train_cache_notes <- function(text) {
  text <- paste(text, collapse = "\n")
  txt <- gsub("\r", "\n", pam_train_strip_ansi(text), fixed = TRUE)
  lines <- trimws(strsplit(txt, "\n", fixed = TRUE)[[1L]])
  list(used = any(grepl("...loading from cache:", lines, fixed = TRUE)),
       mismatch = any(grepl("Cache preprocessing parameters don't match", lines, fixed = TRUE)),
       cache_settings = lines[grepl("^Cache: ", lines)],
       missing = any(grepl("...cache file not found:", lines, fixed = TRUE)))
}

#' Wrap up a training run: check the files, read the metrics, write the record (internal)
#'
#' The "finish" step shared by `pam_birdnet_train()` and the training app.
#'
#' @param plan A plan from `pam_train_plan()`.
#' @param status Exit status of the trainer.
#' @param elapsed Elapsed time (a difftime in minutes).
#' @param log_dir Optional folder for a log file.
#' @param quiet If TRUE, print nothing to the console (the app shows the result itself).
#' @return The result list documented in `pam_birdnet_train()`.
#' @keywords internal
#' @noRd
pam_train_finish <- function(plan, status, elapsed, log_dir = NULL, quiet = FALSE) {
  stage <- "birdnet_train"
  output <- plan$output; params <- plan$params; log_file <- plan$log_file
  model_file <- plan$model_file

  expected <- c(model = ".tflite", labels = "_Labels.txt", params = "_Params.csv",
                counts = "_sample_counts.csv")
  files <- vapply(expected, function(suffix) file.exists(paste0(output, suffix)), logical(1))
  fmt <- if (is.null(params$model_format)) "tflite" else params$model_format
  ok <- identical(as.integer(status), 0L) && (!(fmt %in% c("tflite", "both")) || files[["model"]])

  metrics <- tryCatch(pam_birdnet_train_metrics(log_file), error = function(e) NULL)
  # also present when the test clips came from a cache; ignore a file left by an earlier run
  evaluation <- pam_train_read_evaluation(output, newer_than = Sys.time() - elapsed - 60)
  log_text <- if (file.exists(log_file)) paste(readLines(log_file, warn = FALSE), collapse = "\n") else ""
  cache <- if (is.null(plan$cache_mode)) NULL else pam_train_cache_notes(log_text)

  run_record <- paste0(output, "_run.yml")
  yaml::write_yaml(list(
    finished = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    elapsed_min = round(as.numeric(elapsed, units = "mins"), 2), exit_status = status,
    data_dir = plan$data_dir, output = output, test_data = plan$test_data,
    load_params = plan$load_params, cache_mode = plan$cache_mode, params = params,
    command = paste(c(shQuote(plan$bin), plan$args), collapse = " "),
    files_present = as.list(files),
    best = if (is.null(metrics)) NULL else metrics$best,
    effective = if (is.null(metrics)) NULL else list(
      n_epochs = metrics$best$n_epochs, n_train = metrics$n_train, n_val = metrics$n_val,
      n_labels = metrics$n_labels, evaluated_on = metrics$evaluated_on),
    test = if (is.null(evaluation$overall)) NULL else as.list(evaluation$overall[
      , c("auprc", "auroc", "precision_opt", "recall_opt", "f1_opt")])), run_record)

  if (ok) {
    pam_log("INFO", sprintf("training finished in %.1f min", as.numeric(elapsed, units = "mins")),
            stage, log_dir, echo = !quiet)
    if (!quiet) {
      cli::cli_alert_success("Model written to {model_file}")
      if (!is.null(metrics) && !is.na(metrics$best$auprc)) {
        cli::cli_alert_info(paste0("Best validation AUPRC {round(metrics$best$auprc, 3)}, ",
                                   "AUROC {round(metrics$best$auroc, 3)} (epoch ",
                                   "{metrics$best$epoch}/{metrics$best$n_epochs})"))
      }
    }
  } else {
    pam_log("ERROR", sprintf("training failed (exit status %s); see %s", status, log_file),
            stage, log_dir, echo = !quiet)
    if (!quiet && file.exists(log_file)) {
      tail_lines <- utils::tail(readLines(log_file, warn = FALSE), 15L)
      cli::cli_alert_danger("Training failed. Last lines of {log_file}:")
      cat(tail_lines, sep = "\n")
    }
  }
  invisible(list(status = if (ok) "ok" else "failed", output = output, files = files,
                 elapsed = elapsed, log = log_file, run_record = run_record, args = plan$args,
                 metrics = metrics, evaluation = evaluation, cache = cache))
}

#' Train the same classifier several times and summarize the metrics
#'
#' Each run uses a different random validation split and initialization, so a
#' single score can be lucky or unlucky. Repeating the run shows how much the
#' metrics vary, which is the yardstick for comparing settings, or pamflow
#' against the Analyzer GUI, fairly.
#'
#' This is a standalone tool: it is not a stage of the workflow and no workflow
#' function calls it. Use the trained model by pointing the `birdnet:` section of
#' the config at it.
#'
#' @param data_dir Training folder (see `pam_birdnet_train()`).
#' @param output Output path prefix; run `k` is written to
#'   `<output>_run<kk>` (two digits).
#' @param n Number of runs.
#' @param params Named list of training parameters (see `pam_birdnet_train()`).
#' @param ... Further arguments passed to `pam_birdnet_train()` (for example
#'   `test_data`, `envdir`, `live`, `overwrite`).
#' @return A list: `runs` (data.frame with `run`, `status`, `auprc`, `auroc`,
#'   `loss`, `best_epoch`, `elapsed_min`, `output`) and `summary` (data.frame
#'   with `metric`, `n`, `mean`, `sd`, `min`, `max` over the successful runs).
#' @details A failed run is recorded and does not stop the others. With a
#'   fixed `test_data` folder every run is scored on the same clips, so the
#'   spread then reflects training randomness only.
#' @examples
#' \dontrun{
#' rep5 <- pam_birdnet_train_repeat("E:/clips", "E:/models/Check", n = 5)
#' rep5$summary
#' }
#' @export
pam_birdnet_train_repeat <- function(data_dir, output, n = 5L, params = list(), ...) {
  n <- as.integer(n)
  if (length(n) != 1L || is.na(n) || n < 1L) rlang::abort("`n` must be a positive whole number")
  rows <- lapply(seq_len(n), function(k) {
    out_k <- sprintf("%s_run%02d", output, k)
    cli::cli_alert_info("Run {k} of {n}")
    res <- tryCatch(pam_birdnet_train(data_dir, out_k, params = params, ...),
                    error = function(e) {
                      cli::cli_alert_danger("Run {k} failed: {conditionMessage(e)}")
                      NULL
                    })
    b <- if (is.null(res) || is.null(res$metrics)) NULL else res$metrics$best
    data.frame(run = k,
               status = if (is.null(res)) "error" else res$status,
               auprc = if (is.null(b)) NA_real_ else b$auprc,
               auroc = if (is.null(b)) NA_real_ else b$auroc,
               loss = if (is.null(b)) NA_real_ else b$loss,
               best_epoch = if (is.null(b)) NA_integer_ else b$epoch,
               elapsed_min = if (is.null(res)) NA_real_ else round(as.numeric(res$elapsed, units = "mins"), 2),
               output = out_k, stringsAsFactors = FALSE)
  })
  runs <- do.call(rbind, rows)
  ok <- runs[runs$status == "ok" & !is.na(runs$auprc), , drop = FALSE]
  summary <- do.call(rbind, lapply(c("auprc", "auroc", "loss"), function(m) {
    x <- ok[[m]]
    data.frame(metric = m, n = length(x),
               mean = if (length(x)) mean(x) else NA_real_,
               sd = if (length(x) > 1L) stats::sd(x) else NA_real_,
               min = if (length(x)) min(x) else NA_real_,
               max = if (length(x)) max(x) else NA_real_, stringsAsFactors = FALSE)
  }))
  list(runs = runs, summary = summary)
}
