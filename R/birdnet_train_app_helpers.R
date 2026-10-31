# Helpers for the training app (pam_train_app). Everything here is a plain
# function with no Shiny dependency, so it can be tested without a browser.

# ---- defaults -----------------------------------------------------------------

#' Default values shown in the training app (internal)
#'
#' These are the BirdNET-Analyzer 2.4.0 defaults, the same ones the Analyzer GUI
#' starts with. The app passes the values it shows explicitly, so a run is
#' reproducible from its `_run.yml`.
#'
#' @return A named list.
#' @keywords internal
#' @noRd
pam_train_defaults <- function() {
  list(epochs = 50L, batch_size = 32L, learning_rate = 0.0001, hidden_units = 0L,
       dropout = 0, val_split = 0.2, crop_mode = "center", crop_overlap = 0,
       fmin = 0L, fmax = 15000L, audio_speed = 1, ups_mode = "repeat", ups_ratio = 0,
       focal_gamma = 2, focal_alpha = 0.25, at_trials = 50L, at_exec = 1L,
       save_mode = "replace", out_format = "tflite", clf_name = "CustomClassifier")
}

# ---- translations ---------------------------------------------------------------

#' Folder with the translation files (internal)
#' @keywords internal
#' @noRd
pam_i18n_dir <- function() system.file("i18n", package = "pamflow")

#' Languages the app is available in (internal)
#'
#' One file `inst/i18n/<code>.yml` per language. `en.yml` is complete; another
#' language only needs the keys it translates, the rest fall back to English.
#' @return Character vector of language codes.
#' @keywords internal
#' @noRd
pam_i18n_languages <- function() {
  dir <- pam_i18n_dir()
  if (!nzchar(dir)) return("en")
  sub("\\.yml$", "", list.files(dir, pattern = "\\.yml$"))
}

#' Pick the app language from the environment (internal)
#'
#' Looks at `options(pamflow.lang)`, the `PAMFLOW_LANG` variable, and then the
#' `LANGUAGE` / `LANG` variables, and falls back to English.
#' @param langs Available language codes.
#' @return A language code.
#' @keywords internal
#' @noRd
pam_i18n_default_lang <- function(langs = pam_i18n_languages()) {
  cand <- c(getOption("pamflow.lang"), Sys.getenv("PAMFLOW_LANG"),
            substr(Sys.getenv("LANGUAGE"), 1L, 2L), substr(Sys.getenv("LANG"), 1L, 2L))
  cand <- tolower(cand[!is.na(cand) & nzchar(cand)])
  hit <- cand[cand %in% langs]
  if (length(hit)) hit[1L] else "en"
}

#' Build the translation function for a language (internal)
#'
#' @param lang Language code, or NULL to choose from the environment.
#' @return A function `tr(key, ...)` returning the text for `key`; extra
#'   arguments are filled into the text with `sprintf()`. A missing key returns
#'   the key itself, so a gap is visible rather than blank.
#' @keywords internal
#' @noRd
pam_i18n <- function(lang = NULL) {
  langs <- pam_i18n_languages()
  if (is.null(lang)) lang <- pam_i18n_default_lang(langs)
  if (!lang %in% langs) lang <- "en"
  dir <- pam_i18n_dir()
  read <- function(code) {
    f <- file.path(dir, paste0(code, ".yml"))
    if (!nzchar(dir) || !file.exists(f)) return(list())
    # YAML reads a bare 0.5 or yes as a number or logical; the app only wants text
    lapply(yaml::read_yaml(f, fileEncoding = "UTF-8"), as.character)
  }
  strings <- read("en")
  if (!identical(lang, "en")) strings <- utils::modifyList(strings, read(lang))
  function(key, ...) {
    txt <- strings[[key]]
    if (is.null(txt)) return(key)
    if (...length()) sprintf(txt, ...) else txt
  }
}

# ---- reading the trainer's output ---------------------------------------------------

#' Remove terminal colour codes from text (internal)
#' @param x Character vector.
#' @return Character vector without ANSI escape sequences.
#' @keywords internal
#' @noRd
pam_train_strip_ansi <- function(x) gsub("\033\\[[0-9;?]*[A-Za-z]", "", x, perl = TRUE)

#' Turn the raw trainer output into readable log lines (internal)
#'
#' Drops TensorFlow start-up noise, removes colour codes, keeps only the latest
#' state of each progress bar, and drops the per-step lines Keras prints inside
#' an epoch (the line with the validation scores is kept).
#'
#' @param text The raw output (one string).
#' @param max_lines Keep at most this many of the newest lines.
#' @return Character vector of lines.
#' @keywords internal
#' @noRd
pam_train_log_lines <- function(text, max_lines = 200L) {
  if (length(text) != 1L || is.na(text) || !nzchar(text)) return(character())
  parts <- trimws(unlist(strsplit(pam_train_strip_ansi(text), "[\r\n]+")))
  parts <- parts[nzchar(parts)]
  noise <- paste0("(oneDNN|absl|TensorSpec|InitializeLog|^I0000|^W0000|XNNPACK|tf\\.resource|",
                  "dtype=tf|^Output Type|^Captures|^\\* Endpoint|Saved artifact|tensorflow/core|",
                  "^WARNING: All log messages)")
  parts <- parts[!grepl(noise, parts)]
  # per-step lines inside an epoch, unless they carry the validation scores
  parts <- parts[!(grepl("^[0-9]+/[0-9]+\\s.*step\\s+-", parts) & !grepl("val_", parts))]
  if (!length(parts)) return(character())
  # keep only the last state of each progress bar
  is_bar <- grepl("[0-9]+%\\|", parts)
  desc <- ifelse(is_bar, trimws(sub("\\s*[0-9]+%\\|.*$", "", parts)), NA_character_)
  n <- length(parts)
  next_same <- c(is_bar[-1L] & !is.na(desc[-1L]) & desc[-1L] == desc[-n], FALSE)
  parts <- parts[!(is_bar & next_same)]
  utils::tail(parts, max_lines)
}

#' Work out where a training run is from its output (internal)
#'
#' @param text The raw output so far (one string).
#' @param n_classes Number of class folders, used to show progress while the
#'   clips are loaded (NA if unknown).
#' @return A list: `phase` ("starting", "downloading", "loading", "cache", "building",
#'   "training", "saving" or "done"), `epoch`, `n_epochs`, `classes_done`,
#'   `n_classes`, `download_pct`, `fraction` (0 to 1, overall), `done` and
#'   `stopped_early`.
#' @keywords internal
#' @noRd
pam_train_progress <- function(text, n_classes = NA_integer_) {
  out <- list(phase = "starting", epoch = NA_integer_, n_epochs = NA_integer_,
              classes_done = 0L, n_classes = as.integer(n_classes), download_pct = NA_real_,
              fraction = 0, done = FALSE, stopped_early = FALSE)
  if (length(text) != 1L || is.na(text) || !nzchar(text)) return(out)
  txt <- gsub("\r", "\n", pam_train_strip_ansi(text), fixed = TRUE)
  has <- function(p) grepl(p, txt, fixed = TRUE)
  last_match <- function(pattern) {
    m <- regmatches(txt, gregexpr(pattern, txt, perl = TRUE))[[1L]]
    if (length(m)) m[length(m)] else NA_character_
  }

  dl <- last_match("Downloading model:\\s*[0-9]+%")
  if (!is.na(dl)) out$download_pct <- as.numeric(sub(".*?([0-9]+)%$", "\\1", dl, perl = TRUE))
  # class names can contain apostrophes (Swainson's Thrush), so match up to the closing "':"
  # tqdm can print the final 100% line more than once, so count distinct class names
  done_lines <- regmatches(txt, gregexpr("loading '.*?':\\s*100%", txt, perl = TRUE))[[1L]]
  out$classes_done <- length(unique(sub("^loading '(.*)':\\s*100%$", "\\1", done_lines, perl = TRUE)))
  ep <- last_match("Epoch [0-9]+/[0-9]+")
  if (!is.na(ep)) {
    nums <- as.integer(strsplit(sub("^Epoch ", "", ep), "/", fixed = TRUE)[[1L]])
    out$epoch <- nums[1L]; out$n_epochs <- nums[2L]
  }

  out$done <- grepl("Best AUPRC:", txt, fixed = TRUE)
  out$phase <- if (out$done) "done"
  else if (has("Saving model")) "saving"
  else if (has("Training model")) "training"
  else if (has("Building model")) "building"
  else if (has("...loading from cache:")) "cache"
  else if (has("Loading training data")) "loading"
  else if (!is.na(out$download_pct)) "downloading"
  else "starting"

  out$fraction <- switch(out$phase,
    starting = 0, downloading = 0,
    loading = if (!is.na(out$n_classes) && out$n_classes > 0L) {
      0.45 * min(1, out$classes_done / out$n_classes)
    } else 0.1,
    cache = 0.3,
    building = 0.5,
    training = if (!is.na(out$epoch) && !is.na(out$n_epochs) && out$n_epochs > 0L) {
      0.5 + 0.45 * out$epoch / out$n_epochs
    } else 0.5,
    saving = 0.97, done = 1)
  out$stopped_early <- out$done && !is.na(out$epoch) && !is.na(out$n_epochs) &&
    out$epoch < out$n_epochs
  out
}

# ---- form values -> training options -----------------------------------------------

#' Check the values entered in the training form (internal)
#'
#' @param x Named list of form values (see `pam_train_params_from_inputs()`).
#' @return Character vector of message keys (empty if everything is fine); the
#'   app translates each key.
#' @keywords internal
#' @noRd
pam_train_validate_inputs <- function(x) {
  errs <- character()
  add <- function(key) errs <<- c(errs, key)
  txt <- function(v) if (is.null(v) || length(v) != 1L || is.na(v)) "" else trimws(as.character(v))
  num <- function(v) if (is.null(v) || length(v) != 1L || !is.numeric(v) || is.na(v)) NA_real_ else v
  cache_mode <- if (nzchar(txt(x$cache_mode))) txt(x$cache_mode) else "none"

  if (identical(cache_mode, "load")) {
    if (!nzchar(txt(x$cache_file)) || !file.exists(pam_train_cache_path(txt(x$cache_file)))) add("err_cache_file")
  } else if (!nzchar(txt(x$train_dir)) || !dir.exists(txt(x$train_dir))) {
    add("err_no_data")
  }
  if (nzchar(txt(x$test_dir)) && !dir.exists(txt(x$test_dir))) add("err_test_dir")
  if (!nzchar(txt(x$out_dir))) add("err_no_output")
  name <- txt(x$clf_name)
  if (!nzchar(name) || grepl("[/\\\\:*?\"<>|]", name)) add("err_name")

  epochs <- num(x$epochs); batch <- num(x$batch_size); lr <- num(x$learning_rate)
  if (is.na(epochs) || epochs < 1 || epochs != round(epochs)) add("err_epochs")
  if (is.na(batch) || batch < 1 || batch != round(batch)) add("err_batch")
  if (is.na(lr) || lr <= 0) add("err_lr")
  hidden <- num(x$hidden_units)
  if (is.na(hidden) || hidden < 0 || hidden != round(hidden)) add("err_hidden")
  drop <- num(x$dropout)
  if (is.na(drop) || drop < 0 || drop > 0.9) add("err_dropout")
  vs <- num(x$val_split)
  if (is.na(vs) || vs <= 0 || vs >= 1) add("err_val_split")
  fmin <- num(x$fmin); fmax <- num(x$fmax)
  if (is.na(fmin) || is.na(fmax) || fmin < 0 || fmax > 15000 || fmin >= fmax) add("err_freq")
  speed <- num(x$audio_speed)
  if (is.na(speed) || speed <= 0) add("err_speed")
  if (txt(x$crop_mode) %in% c("segments", "smart")) {
    ov <- num(x$crop_overlap)
    if (is.na(ov) || ov < 0 || ov > 2.9) add("err_overlap")
  }
  ur <- num(x$ups_ratio)
  if (is.na(ur) || ur < 0 || ur > 1) add("err_ups_ratio")
  if (isTRUE(x$focal)) {
    g <- num(x$f_gamma); a <- num(x$f_alpha)
    if (is.na(g) || g < 0 || is.na(a) || a <= 0 || a >= 1) add("err_focal")
  }
  if (isTRUE(x$autotune)) {
    tr_n <- num(x$at_trials); ex <- num(x$at_exec)
    if (is.na(tr_n) || tr_n < 1 || is.na(ex) || ex < 1) add("err_autotune")
  }
  runs <- num(x$n_runs)
  if (is.na(runs) || runs < 1 || runs != round(runs)) add("err_runs")
  th <- x$threads
  if (!is.null(th) && length(th) == 1L && !is.na(th) && (!is.numeric(th) || th < 1)) add("err_threads")
  unique(errs)
}

#' Turn the training form values into the options of `pam_train_plan()` (internal)
#'
#' Every value shown in the form is passed explicitly (so what you see is what
#' runs), except options that do not apply: the overlap unless the crop mode
#' uses it, the focal-loss settings unless focal loss is on, the autotune
#' settings unless autotune is on, and the thread count unless one is entered.
#'
#' @param x Named list of form values: `train_dir`, `test_dir`, `out_dir`,
#'   `clf_name`, `out_format`, `cache_mode`, `cache_file`, `fmin`, `fmax`,
#'   `audio_speed`, `crop_mode`, `crop_overlap`, `autotune`, `at_trials`,
#'   `at_exec`, `epochs`, `batch_size`, `learning_rate`, `hidden_units`,
#'   `dropout`, `val_split`, `label_smoothing`, `ups_mode`, `ups_ratio`,
#'   `mixup`, `focal`, `f_gamma`, `f_alpha`, `save_mode`, `threads`.
#' @return A list: `data_dir`, `test_data`, `cache_mode`, `cache_file`, `params`.
#' @keywords internal
#' @noRd
pam_train_params_from_inputs <- function(x) {
  txt <- function(v) if (is.null(v) || length(v) != 1L || is.na(v)) "" else trimws(as.character(v))
  int <- function(v) as.integer(round(v))
  p <- list(
    epochs = int(x$epochs), batch_size = int(x$batch_size),
    learning_rate = as.numeric(x$learning_rate), hidden_units = int(x$hidden_units),
    dropout = as.numeric(x$dropout), val_split = as.numeric(x$val_split),
    crop_mode = txt(x$crop_mode), fmin = int(x$fmin), fmax = int(x$fmax),
    audio_speed = as.numeric(x$audio_speed),
    label_smoothing = isTRUE(x$label_smoothing), mixup = isTRUE(x$mixup),
    upsampling_mode = tolower(txt(x$ups_mode)), upsampling_ratio = as.numeric(x$ups_ratio),
    model_save_mode = txt(x$save_mode), model_format = txt(x$out_format),
    focal_loss = isTRUE(x$focal))
  if (txt(x$crop_mode) %in% c("segments", "smart")) p$overlap <- as.numeric(x$crop_overlap)
  if (isTRUE(x$focal)) {
    p$focal_loss_gamma <- as.numeric(x$f_gamma)
    p$focal_loss_alpha <- as.numeric(x$f_alpha)
  }
  p$autotune <- isTRUE(x$autotune)
  if (isTRUE(x$autotune)) {
    p$autotune_trials <- int(x$at_trials)
    p$autotune_executions_per_trial <- int(x$at_exec)
  }
  th <- x$threads
  if (!is.null(th) && length(th) == 1L && !is.na(th)) p$threads <- int(th)

  cache_mode <- if (nzchar(txt(x$cache_mode)) && !identical(txt(x$cache_mode), "none")) txt(x$cache_mode) else NULL
  list(data_dir = if (nzchar(txt(x$train_dir))) txt(x$train_dir) else NULL,
       test_data = if (nzchar(txt(x$test_dir))) txt(x$test_dir) else NULL,
       cache_mode = cache_mode,
       cache_file = if (nzchar(txt(x$cache_file))) txt(x$cache_file) else NULL,
       params = p)
}

#' Output names for a series of runs (internal)
#'
#' @param base Output path prefix.
#' @param n Number of runs.
#' @return `base` for one run, otherwise `<base>_run01`, `<base>_run02`, ...
#' @keywords internal
#' @noRd
pam_train_run_names <- function(base, n) {
  n <- as.integer(n)
  if (n <= 1L) base else sprintf("%s_run%02d", base, seq_len(n))
}

# ---- results ---------------------------------------------------------------------------

#' The `birdnet:` config lines that use a trained model (internal)
#'
#' @param output Output path prefix of the trained model.
#' @return A single string (YAML text).
#' @keywords internal
#' @noRd
pam_train_config_snippet <- function(output) {
  full <- normalizePath(output, winslash = "/", mustWork = FALSE)
  paste0("birdnet:\n",
         "  model_dir: \"", dirname(full), "\"\n",
         "  classifier_name: \"", basename(full), "\"\n")
}

#' Table of earlier training runs found in a folder (internal)
#'
#' Reads the `<name>_run.yml` record that every run writes.
#'
#' @param dir Folder to look in.
#' @return A data.frame (newest first) with `run`, `finished`, `minutes`,
#'   `status`, `epochs`, `n_train`, `n_val`, `auprc`, `auroc`, `loss`,
#'   `hidden_units`, `dropout`, `learning_rate`, `batch_size`; zero rows if none.
#' @keywords internal
#' @noRd
pam_train_runs_table <- function(dir) {
  cols <- c("run", "finished", "minutes", "status", "epochs", "n_train", "n_val",
            "auprc", "auroc", "loss", "hidden_units", "dropout", "learning_rate", "batch_size")
  empty <- stats::setNames(data.frame(matrix(ncol = length(cols), nrow = 0L)), cols)
  if (length(dir) != 1L || is.na(dir) || !nzchar(dir) || !dir.exists(dir)) return(empty)
  files <- list.files(dir, pattern = "_run\\.yml$", full.names = TRUE)
  if (!length(files)) return(empty)
  pick <- function(x, default = NA) if (is.null(x) || length(x) != 1L) default else x
  rows <- lapply(files, function(f) {
    y <- tryCatch(yaml::read_yaml(f), error = function(e) NULL)
    if (is.null(y)) return(NULL)
    pr <- if (is.list(y$params)) y$params else list()
    ok <- identical(as.integer(pick(y$exit_status, 1L)), 0L) &&
      isTRUE(as.logical(pick(y$files_present$model, TRUE)))
    data.frame(run = sub("_run\\.yml$", "", basename(f)),
               finished = as.character(pick(y$finished, NA_character_)),
               minutes = as.numeric(pick(y$elapsed_min, NA_real_)),
               status = if (ok) "ok" else "failed",
               epochs = as.integer(pick(y$effective$n_epochs, pick(pr$epochs, NA_integer_))),
               n_train = as.integer(pick(y$effective$n_train, NA_integer_)),
               n_val = as.integer(pick(y$effective$n_val, NA_integer_)),
               auprc = as.numeric(pick(y$best$auprc, NA_real_)),
               auroc = as.numeric(pick(y$best$auroc, NA_real_)),
               loss = as.numeric(pick(y$best$loss, NA_real_)),
               hidden_units = as.integer(pick(pr$hidden_units, NA_integer_)),
               dropout = as.numeric(pick(pr$dropout, NA_real_)),
               learning_rate = as.numeric(pick(pr$learning_rate, NA_real_)),
               batch_size = as.integer(pick(pr$batch_size, NA_integer_)),
               stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(empty)
  out <- do.call(rbind, rows)
  out[order(out$finished, decreasing = TRUE), , drop = FALSE]
}

#' Learning-curve plot: validation AUPRC and AUROC by epoch (internal)
#'
#' Like the plot in the Analyzer GUI. Color-blind-safe colors, and the two
#' lines also differ in line type.
#'
#' @param history The `history` data.frame from `pam_train_parse_metrics()`.
#' @param labels Named list of texts: `title`, `x`, `y`, `auprc`, `auroc`, `waiting`.
#' @return A ggplot object.
#' @importFrom rlang .data
#' @keywords internal
#' @noRd
pam_train_plot_history <- function(history, labels = list(), dark = FALSE) {
  lab <- utils::modifyList(list(title = "Validation metrics by epoch", x = "Epoch", y = "Score",
                                auprc = "AUPRC", auroc = "AUROC",
                                waiting = "Waiting for the first epoch..."), labels)
  if (is.null(history) || !nrow(history)) {
    return(ggplot2::ggplot() +
             ggplot2::annotate("text", x = 0, y = 0, label = lab$waiting, size = 5, colour = if (dark) "#a3acb9" else "#5f6670") +
             ggplot2::theme_void())
  }
  df <- rbind(data.frame(epoch = history$epoch, value = history$val_auprc, metric = lab$auprc),
              data.frame(epoch = history$epoch, value = history$val_auroc, metric = lab$auroc))
  cols <- stats::setNames(pam_train_plot_colours(dark), c(lab$auprc, lab$auroc))
  lts <- stats::setNames(c("solid", "longdash"), c(lab$auprc, lab$auroc))
  ggplot2::ggplot(df, ggplot2::aes(x = .data$epoch, y = .data$value,
                                   colour = .data$metric, linetype = .data$metric)) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::scale_colour_manual(values = cols) +
    ggplot2::scale_linetype_manual(values = lts) +
    ggplot2::coord_cartesian(ylim = c(0, 1)) +
    ggplot2::labs(title = lab$title, x = lab$x, y = lab$y, colour = NULL, linetype = NULL) +
    pam_train_plot_theme(dark = dark)
}

#' Dot plot comparing training runs (internal)
#'
#' @param tbl A table from `pam_train_runs_table()`.
#' @param labels Named list of texts: `title`, `x`, `y`, `auprc`, `auroc`, `empty`.
#' @return A ggplot object.
#' @importFrom rlang .data
#' @keywords internal
#' @noRd
pam_train_plot_runs <- function(tbl, labels = list(), dark = FALSE) {
  lab <- utils::modifyList(list(title = "Runs compared", x = "Run", y = "Score",
                                auprc = "AUPRC", auroc = "AUROC", empty = "No runs yet"), labels)
  tbl <- if (is.null(tbl)) NULL else tbl[!is.na(tbl$auprc), , drop = FALSE]
  if (is.null(tbl) || !nrow(tbl)) {
    return(ggplot2::ggplot() +
             ggplot2::annotate("text", x = 0, y = 0, label = lab$empty, size = 5, colour = if (dark) "#a3acb9" else "#5f6670") +
             ggplot2::theme_void())
  }
  tbl <- tbl[order(tbl$finished), , drop = FALSE]
  run <- factor(tbl$run, levels = tbl$run)
  df <- rbind(data.frame(run = run, value = tbl$auprc, metric = lab$auprc),
              data.frame(run = run, value = tbl$auroc, metric = lab$auroc))
  df <- df[!is.na(df$value), , drop = FALSE]
  cols <- stats::setNames(pam_train_plot_colours(dark), c(lab$auprc, lab$auroc))
  shapes <- stats::setNames(c(16, 17), c(lab$auprc, lab$auroc))
  ggplot2::ggplot(df, ggplot2::aes(x = .data$value, y = .data$run,
                                   colour = .data$metric, shape = .data$metric)) +
    ggplot2::geom_point(size = 3) +
    ggplot2::scale_colour_manual(values = cols) +
    ggplot2::scale_shape_manual(values = shapes) +
    ggplot2::coord_cartesian(xlim = c(0, 1)) +
    ggplot2::labs(title = lab$title, x = lab$y, y = lab$x, colour = NULL, shape = NULL) +
    pam_train_plot_theme(dark = dark)
}

# ---- look and feel ---------------------------------------------------------------------

#' Stylesheet of the pamflow apps (internal)
#'
#' A quiet, minimal look: system fonts, a white page, hairline dividers, one
#' accent colour and no shadows. Plain CSS on top of Shiny's own Bootstrap, so it
#' adds no package dependency. Colours keep a contrast ratio of at least 4.5:1.
#'
#' @return A single string of CSS.
#' @keywords internal
#' @noRd
pam_train_css <- function() {
  paste(
    ":root { --ink:#1f2328; --muted:#5b6370; --line:#e3e7ee; --accent:#8fb4e3; --accent-ink:#35568a;",
    "  --card:#f3f6fc; --page:#fbfcfe; --field:#ffffff; --on-accent:#1f2328; --logo-bg:transparent;",
    "  --ok:#2f7a52; --warn:#9a5a12; --bad:#b2453f; --odd:#7b4fa8; }",
    "[data-theme='dark'] { --ink:#e6e9ee; --muted:#a3acb9; --line:#343b47; --accent:#8fb4e3;",
    "  --accent-ink:#a9c4ea; --card:#212630; --page:#161a20; --field:#1a1e26; --logo-bg:#ffffff;",
    "  --ok:#8fd1a8; --warn:#f0b46e; --bad:#f09a94; --odd:#c9a5ec; }",
    "html { color-scheme: light; } [data-theme='dark'] { color-scheme: dark; }",
    "body { font-family: -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;",
    "  color: var(--ink); background:var(--page); font-size:14px; line-height:1.5; }",
    ".container-fluid { max-width:1000px; margin:0 auto; padding:0 20px 64px; }",
    ".pam-header { padding:28px 0 14px; text-align:center; position:relative; }",
    ".pam-brand { display:flex; align-items:center; justify-content:center; gap:14px; }",
    ".pam-logo { height:56px; width:auto; background:var(--logo-bg); border-radius:10px; padding:3px; }",
    ".pam-theme { position:absolute; top:14px; right:0; display:inline-flex; align-items:center; gap:8px;",
    "  background:transparent; border:none; color:var(--muted); font-size:13px; cursor:pointer; padding:4px; }",
    ".pam-theme-track { width:34px; height:20px; border-radius:10px; background:var(--line); position:relative;",
    "  display:inline-block; transition:background .15s; }",
    ".pam-theme-thumb { position:absolute; top:3px; left:3px; width:14px; height:14px; border-radius:50%;",
    "  background:var(--ink); transition:transform .15s; }",
    ".pam-theme[aria-checked='true'] .pam-theme-track { background:var(--accent); }",
    ".pam-theme[aria-checked='true'] .pam-theme-thumb { transform:translateX(14px); background:var(--on-accent); }",
    ".pam-theme:focus-visible { outline:2px solid var(--accent-ink); outline-offset:2px; border-radius:6px; }",
    ".pam-header h1 { font-size:24px; font-weight:600; letter-spacing:-0.01em; margin:0; }",
    ".pam-header::after { content:''; display:block; width:48px; height:3px; border-radius:2px;",
    "  background:var(--accent); margin:14px auto 0; }",
    # cards
    ".pam-card { background:var(--card); border-radius:10px; padding:14px 16px; margin-bottom:12px; }",
    ".pam-grid { display:grid; gap:12px; margin-bottom:12px; }",
    ".pam-grid > .pam-card { margin-bottom:0; }",
    ".pam-cols-2 { grid-template-columns:repeat(2, minmax(0, 1fr)); }",
    ".pam-cols-3 { grid-template-columns:repeat(3, minmax(0, 1fr)); }",
    ".pam-grid .form-group, .pam-card .form-group { margin-bottom:6px; }",
    ".pam-card-title { display:block; font-weight:600; font-size:14px; color:var(--ink); margin:0; }",
    ".pam-card-title.pam-sub { margin:12px 0 4px; font-size:13px; }",
    ".pam-card-desc { color:var(--muted); font-size:12.5px; margin:2px 0 10px; }",
    ".pam-path { display:flex; gap:8px; align-items:flex-start; }",
    ".pam-path .form-group { flex:1; margin-bottom:0; }",
    ".pam-advanced { margin:18px 0 6px; }",
    ".pam-eval-controls { margin:8px 0 12px; }",
    ".pam-advanced > summary { list-style:none; cursor:pointer; padding:10px 0; font-size:13px;",
    "  text-transform:uppercase; letter-spacing:0.06em; color:var(--accent-ink); font-weight:600; }",
    ".pam-advanced > summary::-webkit-details-marker { display:none; }",
    ".pam-advanced > summary::after { content:'+'; float:right; font-size:16px; line-height:1; }",
    ".pam-advanced[open] > summary::after { content:'\\2212'; }",
    ".pam-curve { background:var(--card); border-radius:10px; padding:10px; margin:18px 0 12px; }",
    # pill radios
    ".shiny-options-group { display:flex; flex-wrap:wrap; gap:8px; }",
    ".radio-inline { margin:0 !important; padding:0 !important; border:1px solid var(--line);",
    "  border-radius:8px; background:var(--field); cursor:pointer; }",
    ".radio-inline > span { display:block; padding:7px 16px; }",
    ".radio-inline input[type=radio] { position:absolute; opacity:0; margin:0 !important; }",
    ".radio-inline:has(input:checked) { background:var(--accent); border-color:var(--accent);",
    "  color:var(--on-accent); font-weight:600; }",
    ".radio-inline:has(input:focus-visible) { outline:2px solid var(--accent-ink); outline-offset:2px; }",
    ".checkbox { margin:4px 0 0; }",
    # controls
    "summary:focus-visible, .btn:focus-visible, .form-control:focus { outline:2px solid var(--accent-ink);",
    "  outline-offset:2px; box-shadow:none; }",
    ".form-control { border:1px solid var(--line); border-radius:8px; box-shadow:none; height:36px;",
    "  background:var(--field); }",
    ".form-control:focus { border-color:var(--accent); }",
    ".help-block { color:var(--muted); font-size:12.5px; margin-top:2px; }",
    ".btn { border-radius:8px; box-shadow:none; border:1px solid var(--line); background:var(--field);",
    "  color:var(--ink); padding:7px 16px; }",
    ".btn:hover { background:var(--card); }",
    ".btn-primary, .btn-primary:focus { background:var(--accent); color:var(--on-accent);",
    "  border-color:var(--accent); font-weight:600; }",
    ".btn-primary:hover { background:#7ba5da; color:var(--on-accent); border-color:#7ba5da; }",
    ".pam-start { display:block; width:100%; padding:13px 16px; font-size:15px; }",
    ".pam-actions { display:flex; gap:8px; flex-wrap:wrap; justify-content:center; margin:10px 0 18px; }",
    ".progress { height:6px; border-radius:3px; box-shadow:none; background:var(--line); margin:6px 0 20px; }",
    ".progress-bar { background:var(--accent); box-shadow:none; }",
    ".pam-status { font-size:16px; font-weight:600; margin:2px 0 6px; text-align:center; }",
    ".pam-log-title { margin-top:20px; color:var(--muted); }",
    # tabs
    ".nav-tabs { border-bottom:1px solid var(--line); text-align:center; }",
    ".nav-tabs > li { float:none; display:inline-block; }",
    ".nav-tabs > li > a { border:none; border-bottom:2px solid transparent; color:var(--muted);",
    "  border-radius:0; margin:0 12px; padding:10px 2px; }",
    ".nav-tabs > li.active > a, .nav-tabs > li.active > a:hover, .nav-tabs > li.active > a:focus {",
    "  border:none; border-bottom:2px solid var(--accent); color:var(--ink); background:transparent; }",
    ".nav-tabs > li > a:hover { background:transparent; border-bottom-color:var(--line); }",
    ".tab-content { padding-top:18px; }",
    "pre, .shiny-text-output { background:var(--field); border:1px solid var(--line); border-radius:8px;",
    "  font-size:12px; color:var(--ink); }",
    "table { font-size:13px; } .table > thead > tr > th { border-bottom:1px solid var(--line);",
    "  color:var(--muted); font-weight:500; } .table > tbody > tr > td { border-top:1px solid var(--line); }",
    ".table-striped > tbody > tr:nth-of-type(odd) { background:var(--card); }",
    ".irs--shiny .irs-bar, .irs-bar { background:var(--accent); border-color:var(--accent); }",
    ".alert { border-radius:8px; box-shadow:none; }",
    ".shiny-notification { background:var(--card); color:var(--ink); border:1px solid var(--line); border-radius:8px; box-shadow:0 2px 10px rgba(53,86,138,0.12); opacity:1; }",
    # number cards, media and review controls (standardization, validation and annotation apps)
    ".pam-stat { background:var(--card); border-radius:10px; padding:14px 16px; text-align:center; }",
    ".pam-stat-num { font-size:26px; font-weight:600; line-height:1.15; color:var(--accent-ink); }",
    ".pam-stat-label { color:var(--muted); font-size:12.5px; margin-top:2px; }",
    ".pam-stat-ok .pam-stat-num { color:var(--ok); } .pam-stat-warn .pam-stat-num { color:var(--warn); }",
    ".pam-stat-bad .pam-stat-num { color:var(--bad); } .pam-stat-odd .pam-stat-num { color:var(--odd); }",
    ".pam-media { background:var(--card); border-radius:10px; padding:12px; margin-bottom:12px; }",
    ".pam-media img { width:100%; height:auto; border-radius:6px; background:#ffffff; }",
    ".pam-media audio { width:100%; margin-top:4px; }",
    ".pam-audio-label { font-size:12.5px; color:var(--muted); margin:10px 0 2px; }",
    ".pam-meta-title { font-size:18px; font-weight:600; margin:0; }",
    ".pam-meta-sub { color:var(--muted); font-style:italic; }",
    ".pam-meta-line { color:var(--muted); font-size:12.5px; margin:2px 0 0; }",
    ".pam-progress-text { text-align:center; color:var(--muted); font-size:13px; margin:0; }",
    ".pam-nav { display:flex; gap:8px; margin:10px 0 18px; } .pam-nav .btn { flex:1; }",
    ".pam-preview p { margin:0 0 4px; } .pam-preview .pam-out { color:var(--accent-ink); font-weight:600; }",
    # selectize dropdowns and pickers: Shiny's own theme sets a white background, so these win with !important
    ".selectize-control .selectize-input, .selectize-control.single .selectize-input,",
    "  .selectize-control.single .selectize-input.input-active { border:1px solid var(--line); border-radius:8px;",
    "  box-shadow:none; background:var(--field) !important; background-image:none !important; color:var(--ink);",
    "  min-height:36px; padding:7px 10px; }",
    ".selectize-control .selectize-input.focus { border-color:var(--accent); box-shadow:none; }",
    ".selectize-control .selectize-input > .item, .selectize-control .selectize-input input { color:var(--ink); }",
    ".selectize-control .selectize-input input::placeholder { color:var(--muted); }",
    ".selectize-control.single .selectize-input:after { border-color:var(--muted) transparent transparent transparent; }",
    ".selectize-control.single .selectize-input.dropdown-active:after { border-color:transparent transparent var(--muted) transparent; }",
    ".selectize-dropdown, .selectize-dropdown.form-control { background:var(--field); color:var(--ink);",
    "  border:1px solid var(--line); border-radius:8px; height:auto; box-shadow:none; }",
    ".selectize-dropdown .option, .selectize-dropdown .create { color:var(--ink); }",
    ".selectize-dropdown .active, .selectize-dropdown .option:hover { background:var(--card); color:var(--ink); }",
    ".selectize-control.multi .selectize-input > div { background:var(--accent); color:var(--on-accent); border-radius:6px; }",
    ".checkbox label, .radio label { cursor:pointer; }",
    "@media (max-width: 700px) { .container-fluid { padding:0 12px 40px; }",
    "  .pam-cols-2, .pam-cols-3 { grid-template-columns:1fr; } }",
    sep = "\n")
}

#' Script behind the light/dark switch (internal)
#'
#' Applies the saved choice (or the system preference) before the page is drawn,
#' flips it when the switch is pressed, remembers it in the browser when storage
#' is allowed, and tells the app through `input$theme` so the plots follow.
#'
#' @return A single string of JavaScript.
#' @keywords internal
#' @noRd
pam_train_theme_js <- function() {
  paste(
    "(function () {",
    "  var key = 'pamflow-theme', root = document.documentElement, theme = null;",
    "  try { theme = window.localStorage.getItem(key); } catch (e) {}",
    "  if (theme !== 'dark' && theme !== 'light') {",
    "    theme = (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';",
    "  }",
    "  function report() {",
    "    if (window.Shiny && Shiny.setInputValue) Shiny.setInputValue('theme', root.getAttribute('data-theme'));",
    "  }",
    "  function apply(value, save) {",
    "    root.setAttribute('data-theme', value);",
    "    var sw = document.getElementById('theme_switch');",
    "    if (sw) sw.setAttribute('aria-checked', value === 'dark' ? 'true' : 'false');",
    "    if (save) { try { window.localStorage.setItem(key, value); } catch (e) {} }",
    "    report();",
    "  }",
    "  root.setAttribute('data-theme', theme);",
    "  document.addEventListener('DOMContentLoaded', function () {",
    "    var sw = document.getElementById('theme_switch');",
    "    if (sw) {",
    "      sw.setAttribute('aria-checked', root.getAttribute('data-theme') === 'dark' ? 'true' : 'false');",
    "      sw.addEventListener('click', function () {",
    "        apply(root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark', true);",
    "      });",
    "    }",
    "    if (window.jQuery) jQuery(document).on('shiny:connected', report);",
    "  });",
    "})();",
    sep = "\n")
}

#' Quiet ggplot theme shared by the app plots (internal)
#' @param base_size Base font size.
#' @return A ggplot2 theme.
#' @keywords internal
#' @noRd
pam_train_plot_theme <- function(base_size = 12, dark = FALSE) {
  muted <- if (dark) "#a3acb9" else "#5f6670"
  ink <- if (dark) "#e6e9ee" else "#1f2328"
  grid_col <- if (dark) "#343b47" else "#e9edf4"
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = NA, colour = NA),
      panel.background = ggplot2::element_rect(fill = NA, colour = NA),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = grid_col, linewidth = 0.4),
      axis.text = ggplot2::element_text(colour = muted),
      axis.title = ggplot2::element_text(colour = muted),
      plot.title = ggplot2::element_text(face = "bold", colour = ink, size = base_size + 1),
      plot.title.position = "plot",
      legend.position = "bottom",
      legend.text = ggplot2::element_text(colour = muted))
}

#' Series colors of the app plots (internal)
#' @param dark Logical, dark theme.
#' @return Character vector of two colors.
#' @keywords internal
#' @noRd
pam_train_plot_colours <- function(dark = FALSE) {
  if (dark) c("#7fb2ee", "#f0a08f") else c("#4f86c6", "#d9776a")
}

# ---- shared page pieces of all pamflow apps ----------------------------------------------

#' Make the logo folder available to the apps (internal)
#' @return The folder, invisibly (empty when the package is not installed).
#' @keywords internal
#' @noRd
pam_app_assets <- function() {
  dir <- system.file("app", "www", package = "pamflow")
  if (nzchar(dir)) shiny::addResourcePath("pamflow-assets", dir)
  invisible(dir)
}

#' The `<head>` of an app page: stylesheet and theme script (internal)
#' @return A Shiny tag.
#' @keywords internal
#' @noRd
pam_app_head <- function() {
  shiny::tags$head(shiny::tags$style(shiny::HTML(pam_train_css())),
                   shiny::tags$script(shiny::HTML(pam_train_theme_js())))
}

#' Page header of the apps: logo, title and the light/dark switch (internal)
#'
#' @param tr Translation function from `pam_i18n()`.
#' @param title_key Translation key of the title.
#' @return A Shiny tag.
#' @keywords internal
#' @noRd
pam_app_header <- function(tr, title_key) {
  shiny::div(
    class = "pam-header",
    shiny::tags$button(
      type = "button", id = "theme_switch", class = "pam-theme", role = "switch",
      `aria-checked` = "false",
      shiny::span(class = "pam-theme-track", shiny::span(class = "pam-theme-thumb")),
      shiny::span(tr("lbl_dark_mode"))),
    shiny::div(
      class = "pam-brand",
      shiny::tags$img(src = "pamflow-assets/logo.png", class = "pam-logo", alt = tr("logo_alt")),
      shiny::tags$h1(tr(title_key))))
}

#' Building blocks of the app layout (internal)
#'
#' One setting is one card: a title, a one-line description and the control.
#' All texts go through `tr`, so an app is translated by translating its keys.
#'
#' @param tr Translation function from `pam_i18n()`.
#' @return A list of functions: `choices(values, keys)`, `card(id, title_key,
#'   desc_key, control, kind, class)` (`kind` "label" ties the title to the
#'   input, "group" labels a radio group), `pills(id, values, keys, selected)`,
#'   `grid(..., cols)`, `path_row(id, value, pick_id)`, `number(id, value, ...)`
#'   and `stat(output_id, label_key, tone)` (a number card for `uiOutput`).
#' @keywords internal
#' @noRd
pam_app_widgets <- function(tr) {
  choices <- function(values, keys) stats::setNames(values, vapply(keys, tr, character(1)))
  card <- function(id, title_key, desc_key = NULL, control, kind = "label", class = NULL) {
    title_id <- paste0(id, "_title")
    desc_id <- paste0(id, "_desc")
    title <- if (identical(kind, "label")) {
      shiny::tags$label(id = title_id, `for` = id, class = "pam-card-title", tr(title_key))
    } else {
      shiny::div(id = title_id, class = "pam-card-title", tr(title_key))
    }
    body <- shiny::div(
      title,
      if (!is.null(desc_key)) shiny::div(id = desc_id, class = "pam-card-desc", tr(desc_key)),
      if (identical(kind, "group")) {
        shiny::div(role = "radiogroup", `aria-labelledby` = title_id, control)
      } else {
        control
      })
    shiny::div(class = paste(c("pam-card", class), collapse = " "), body)
  }
  pills <- function(id, values, keys, selected) {
    shiny::radioButtons(id, label = NULL, inline = TRUE, choices = choices(values, keys),
                        selected = selected)
  }
  grid <- function(..., cols = 2L) {
    shiny::div(class = paste0("pam-grid pam-cols-", cols), ...)
  }
  path_row <- function(id, value, pick_id) {
    shiny::div(
      class = "pam-path",
      shiny::textInput(id, label = NULL, value = value, width = "100%"),
      shiny::actionButton(pick_id, tr("btn_browse")))
  }
  number <- function(id, value, ...) {
    shiny::numericInput(id, label = NULL, value = value, width = "100%", ...)
  }
  stat <- function(output_id, label_key, tone = NULL) {
    shiny::div(class = paste(c("pam-stat", if (!is.null(tone)) paste0("pam-stat-", tone)), collapse = " "),
               shiny::uiOutput(output_id),
               shiny::div(class = "pam-stat-label", tr(label_key)))
  }
  list(choices = choices, card = card, pills = pills, grid = grid, path_row = path_row,
       number = number, stat = stat)
}

#' Fill a path box from a folder dialog (internal)
#'
#' Call inside an observer. Starts in the folder already typed, tells the user when no
#' dialog is available, and runs `after` with the chosen folder.
#'
#' @param session,input The Shiny session and input of the app.
#' @param tr Translation function from `pam_i18n()`.
#' @param input_id Id of the text box to fill.
#' @param key Translation key of the dialog title.
#' @param after Optional function called with the chosen folder.
#' @return `NULL`, invisibly.
#' @keywords internal
#' @noRd
pam_app_pick_into <- function(session, input, tr, input_id, key, after = NULL) {
  typed <- trimws(as.character(input[[input_id]]))
  start <- if (length(typed) == 1L && nzchar(typed) && dir.exists(typed)) typed else getwd()
  chosen <- pam_pick_dir(tr(key), default = start)
  if (is.null(chosen)) {
    shiny::showNotification(tr("picker_unavailable"), type = "message")
  } else {
    shiny::updateTextInput(session, input_id, value = chosen)
    if (!is.null(after)) after(chosen)
  }
  invisible(NULL)
}

#' Thin progress bar for "n of N" displays (internal)
#'
#' @param done Number finished.
#' @param total Total number (0 gives an empty bar).
#' @return A Shiny tag.
#' @keywords internal
#' @noRd
pam_app_progress_bar <- function(done, total) {
  pct <- if (total > 0) round(100 * min(done, total) / total) else 0
  shiny::div(class = "progress", role = "progressbar", `aria-valuemin` = 0, `aria-valuemax` = 100,
             `aria-valuenow` = pct,
             shiny::div(class = "progress-bar", style = sprintf("width:%d%%;", as.integer(pct))))
}

# ---- test-set results ------------------------------------------------------------------

#' Per-class test results as a display table (internal)
#'
#' @param evaluation The `evaluation` element of a training result (see
#'   `pam_train_read_evaluation()`); NULL gives NULL.
#' @param threshold "opt" for the per-class optimised threshold (default) or
#'   "default" for 0.5.
#' @param labels Named list of texts: `overall`, `class`, `clips`, `precision`,
#'   `recall`, `f1`, `auprc`, `auroc`, `threshold`.
#' @return A data frame of strings: a macro-average row first, then one row per
#'   class, ordered as in the file; NULL if there is nothing to show.
#' @keywords internal
#' @noRd
pam_train_eval_table <- function(evaluation, threshold = c("opt", "default"), labels = list()) {
  if (is.null(evaluation) || is.null(evaluation$classes) || !nrow(evaluation$classes)) return(NULL)
  threshold <- match.arg(threshold)
  lab <- utils::modifyList(list(overall = "All classes (macro average)", class = "Class",
                                clips = "Test clips", precision = "Precision", recall = "Recall",
                                f1 = "F1", auprc = "AUPRC", auroc = "AUROC",
                                threshold = "Threshold"), labels)
  pick <- function(df, base) df[[paste0(base, "_", threshold)]]
  fmt <- function(x, digits = 3L) ifelse(is.na(x), "", formatC(x, format = "f", digits = digits))
  build <- function(df, name, clips, thr) {
    data.frame(name, clips, fmt(pick(df, "precision")), fmt(pick(df, "recall")),
               fmt(pick(df, "f1")), fmt(df$auprc), fmt(df$auroc), thr,
               stringsAsFactors = FALSE, check.names = FALSE)
  }
  cls <- evaluation$classes
  thr_cls <- if (threshold == "opt") fmt(cls$threshold, 2L) else rep("0.50", nrow(cls))
  out <- build(cls, cls$class, ifelse(is.na(cls$n_test), "", as.character(as.integer(cls$n_test))), thr_cls)
  if (!is.null(evaluation$overall)) {
    out <- rbind(build(evaluation$overall, lab$overall, "", ""), out)
  }
  names(out) <- c(lab$class, lab$clips, lab$precision, lab$recall, lab$f1, lab$auprc, lab$auroc,
                  lab$threshold)
  out
}

#' Per-class confusion counts at the optimised threshold (internal)
#'
#' @param evaluation See `pam_train_eval_table()`.
#' @param labels Named list of texts: `class`, `tp`, `fp`, `fn`, `tn`.
#' @return A data frame of integers (class names as text), or NULL.
#' @keywords internal
#' @noRd
pam_train_eval_counts <- function(evaluation, labels = list()) {
  if (is.null(evaluation) || is.null(evaluation$classes) || !nrow(evaluation$classes)) return(NULL)
  lab <- utils::modifyList(list(class = "Class", tp = "TP", fp = "FP", fn = "FN", tn = "TN"), labels)
  cls <- evaluation$classes
  as_count <- function(x) ifelse(is.na(x), "", as.character(as.integer(x)))
  out <- data.frame(cls$class, as_count(cls$tp), as_count(cls$fp), as_count(cls$fn), as_count(cls$tn),
                    stringsAsFactors = FALSE, check.names = FALSE)
  names(out) <- c(lab$class, lab$tp, lab$fp, lab$fn, lab$tn)
  out
}

# ---- folder picker ---------------------------------------------------------------------

#' Ask the user for a folder with the best picker available (internal)
#'
#' Windows: the system dialog. Elsewhere: RStudio's dialog, then Tk. Returns NULL
#' when no picker is available or the dialog is cancelled; the app then relies on
#' the text box.
#'
#' @param caption Dialog title.
#' @param default Folder to start in.
#' @return A path with forward slashes, or NULL.
#' @keywords internal
#' @noRd
pam_pick_dir <- function(caption = "Select a folder", default = getwd()) {
  path <- tryCatch({
    if (.Platform$OS.type == "windows") {
      getExportedValue("utils", "choose.dir")(default = default, caption = caption)
    } else if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
      rstudioapi::selectDirectory(caption = caption, path = default)
    } else if (requireNamespace("tcltk", quietly = TRUE) && isTRUE(capabilities("tcltk"))) {
      as.character(tcltk::tk_choose.dir(default = default, caption = caption))
    } else NULL
  }, error = function(e) NULL)
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(NULL)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

#' Ask the user for a file (internal)
#' @return A path with forward slashes, or NULL.
#' @keywords internal
#' @noRd
pam_pick_file <- function() {
  path <- tryCatch(file.choose(), error = function(e) NULL)
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(NULL)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}
