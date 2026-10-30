#' Launch the BirdNET classifier training app
#'
#' A standalone tool, not a workflow stage: a point-and-click interface for
#' training a custom BirdNET classifier, laid out
#' like the training tab of the BirdNET-Analyzer GUI: training data, cache,
#' frequency and speed, cropping, autotune, training settings and the model save
#' mode. It shows the progress and the learning curves while training runs, can
#' repeat a training several times to show how much the scores vary, keeps a
#' history of earlier runs, and gives the `birdnet:` config lines that use the
#' trained model.
#'
#' This is a standalone tool: it is not a stage of the workflow and no workflow
#' function calls it. Use the trained model by pointing the `birdnet:` section of
#' the config at it.
#'
#' @param cfg Optional configuration from `pam_load_config()`; its
#'   `birdnet$model_dir` is used as the default output folder.
#' @param data_dir Optional training folder to start with (one sub-folder per class).
#' @param output_dir Optional output folder to start with.
#' @param lang Interface language code (for example `"en"`). `NULL` chooses from
#'   `options(pamflow.lang)`, the `PAMFLOW_LANG` variable or the system
#'   language, and falls back to English. Translations live in
#'   `inst/i18n/<code>.yml`; a translation only needs the texts it changes.
#' @param envdir Folder of the training Python environment (see
#'   `pam_birdnet_setup("training")`).
#' @return A Shiny app object. Printing it at the console starts it, or pass it
#'   to `shiny::runApp()`.
#' @details Training runs in a separate process, so the app stays responsive and
#'   Stop ends the training and everything it started. Closing the app also stops
#'   a running training. The settings shown are the BirdNET-Analyzer 2.4.0
#'   defaults; each value you see is the value used, and it is recorded in the
#'   run's `_run.yml`. The first training downloads the base BirdNET model
#'   (about 224 MB) once.
#'
#'   The scores shown come from clips held out of the training folder and are
#'   therefore optimistic; give a separate test folder for a more honest
#'   estimate.
#' @examples
#' if (interactive()) {
#'   pam_train_app()
#' }
#' \dontrun{
#' pam_train_app(data_dir = "E:/clips", output_dir = "E:/models", lang = "en")
#' }
#' @export
pam_train_app <- function(cfg = NULL, data_dir = NULL, output_dir = NULL, lang = NULL,
                          envdir = pam_birdnet_env_dir("training")) {
  tr <- pam_i18n(lang)
  d <- pam_train_defaults()
  env_ok <- file.exists(pam_birdnet_train_bin(envdir))

  init_out <- output_dir
  if (is.null(init_out) && !is.null(cfg$birdnet$model_dir) && !is.null(cfg$paths$project_root)) {
    md <- cfg$birdnet$model_dir
    init_out <- if (fs::is_absolute_path(md)) md else as.character(fs::path(cfg$paths$project_root, md))
  }
  if (is.null(init_out)) init_out <- ""
  if (is.null(data_dir)) data_dir <- ""

  choices <- function(values, keys) stats::setNames(values, vapply(keys, tr, character(1)))

  # One setting = one card: a title, a one-line description and the control.
  # `kind` "label" ties the title to the input; "group" labels a radio group.
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

  logo_dir <- system.file("app", "www", package = "pamflow")
  if (nzchar(logo_dir)) shiny::addResourcePath("pamflow-assets", logo_dir)

  ui <- shiny::fluidPage(
    shiny::tags$head(shiny::tags$style(shiny::HTML(pam_train_css())),
                     shiny::tags$script(shiny::HTML(pam_train_theme_js()))),
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
        shiny::tags$h1(tr("app_title")))),
    if (!env_ok) shiny::div(class = "alert alert-danger", role = "alert", tr("env_missing")),
    shiny::tabsetPanel(
      id = "main_tabs",
      # ------------------------------------------------------------- train tab
      shiny::tabPanel(
        tr("tab_train"),
        grid(
          card("train_dir", "lbl_train_dir", "desc_train_dir",
               shiny::tagList(
                 path_row("train_dir", data_dir, "pick_train"),
                 shiny::actionButton("check_data", tr("btn_check_data")),
                 shiny::uiOutput("data_summary"))),
          card("out_dir", "lbl_out_dir", "desc_out_dir",
               shiny::tagList(
                 path_row("out_dir", init_out, "pick_out"),
                 shiny::tags$label(`for` = "clf_name", class = "pam-card-title pam-sub", tr("lbl_clf_name")),
                 shiny::textInput("clf_name", label = NULL, value = d$clf_name, width = "100%")))),
        card("test_dir", "lbl_test_dir", "help_test_dir", path_row("test_dir", "", "pick_test")),
        card("out_format", "lbl_out_format", "desc_out_format",
             pills("out_format", c("tflite", "raven", "both"),
                   c("fmt_tflite", "fmt_raven", "fmt_both"), d$out_format), kind = "group"),
        card("cache_mode", "lbl_cache_mode", "help_cache",
             shiny::tagList(
               pills("cache_mode", c("none", "save", "load"),
                     c("cache_none", "cache_save", "cache_load"), "none"),
               shiny::conditionalPanel(
                 "input.cache_mode != 'none'",
                 shiny::tags$label(`for` = "cache_file", class = "pam-card-title pam-sub", tr("lbl_cache_file")),
                 path_row("cache_file", "", "pick_cache")),
               shiny::conditionalPanel("input.cache_mode == 'save'",
                                       shiny::div(class = "pam-card-desc", tr("help_cache_save"))),
               shiny::conditionalPanel("input.cache_mode == 'load'",
                                       shiny::div(class = "pam-card-desc", tr("help_cache_load")))),
             kind = "group"),
        grid(
          card("fmin", "lbl_fmin", "desc_fmin", number("fmin", d$fmin, min = 0, step = 100)),
          card("fmax", "lbl_fmax", "desc_fmax", number("fmax", d$fmax, min = 0, step = 100))),
        card("audio_speed", "lbl_audio_speed", "desc_audio_speed",
             number("audio_speed", d$audio_speed, min = 0.1, step = 0.1)),
        card("crop_mode", "lbl_crop_mode", "desc_crop_mode",
             shiny::tagList(
               pills("crop_mode", c("center", "first", "segments", "smart"),
                     c("crop_center", "crop_first", "crop_segments", "crop_smart"), d$crop_mode),
               shiny::conditionalPanel(
                 "input.crop_mode == 'segments' || input.crop_mode == 'smart'",
                 shiny::tags$label(`for` = "crop_overlap", class = "pam-card-title pam-sub", tr("lbl_crop_overlap")),
                 shiny::sliderInput("crop_overlap", label = NULL, min = 0, max = 2.9,
                                    value = d$crop_overlap, step = 0.1, width = "100%"))),
             kind = "group"),
        card("autotune", "sec_autotune", "help_autotune",
             shiny::tagList(
               shiny::checkboxInput("autotune", tr("lbl_autotune"), value = FALSE),
               shiny::conditionalPanel(
                 "input.autotune",
                 grid(
                   shiny::div(shiny::tags$label(`for` = "at_trials", class = "pam-card-title pam-sub", tr("lbl_at_trials")),
                              number("at_trials", d$at_trials, min = 1, step = 1)),
                   shiny::div(shiny::tags$label(`for` = "at_exec", class = "pam-card-title pam-sub", tr("lbl_at_exec")),
                              number("at_exec", d$at_exec, min = 1, step = 1))))),
             kind = "group"),
        shiny::conditionalPanel(
          "!input.autotune",
          grid(
            card("epochs", "lbl_epochs", "desc_epochs", number("epochs", d$epochs, min = 1, step = 1)),
            card("batch_size", "lbl_batch_size", "desc_batch_size", number("batch_size", d$batch_size, min = 1, step = 8)),
            card("learning_rate", "lbl_learning_rate", "desc_learning_rate",
                 number("learning_rate", d$learning_rate, min = 0.0001, step = 0.0001)),
            card("hidden_units", "lbl_hidden_units", "desc_hidden_units",
                 number("hidden_units", d$hidden_units, min = 0, step = 64)),
            card("dropout", "lbl_dropout", "desc_dropout", number("dropout", d$dropout, min = 0, max = 0.9, step = 0.1)),
            card("val_split", "lbl_val_split", "desc_val_split",
                 number("val_split", d$val_split, min = 0.05, max = 0.95, step = 0.05)),
            cols = 3L),
          grid(
            card("ups_mode", "lbl_ups_mode", "desc_ups_mode",
                 pills("ups_mode", c("repeat", "mean", "linear", "smote"),
                       c("ups_repeat", "ups_mean", "ups_linear", "ups_smote"), d$ups_mode), kind = "group"),
            card("ups_ratio", "lbl_ups_ratio", "desc_ups_ratio",
                 shiny::sliderInput("ups_ratio", label = NULL, min = 0, max = 1, value = d$ups_ratio,
                                    step = 0.05, width = "100%"))),
          grid(
            card("label_smoothing", "lbl_label_smoothing", "desc_label_smoothing",
                 shiny::checkboxInput("label_smoothing", tr("lbl_on"), value = FALSE), kind = "group"),
            card("mixup", "lbl_mixup", "desc_mixup",
                 shiny::checkboxInput("mixup", tr("lbl_on"), value = FALSE), kind = "group"),
            card("focal", "lbl_focal", "desc_focal",
                 shiny::tagList(
                   shiny::checkboxInput("focal", tr("lbl_on"), value = FALSE),
                   shiny::conditionalPanel(
                     "input.focal",
                     shiny::sliderInput("f_gamma", tr("lbl_f_gamma"), min = 0.5, max = 5,
                                        value = d$focal_gamma, step = 0.1, width = "100%"),
                     shiny::sliderInput("f_alpha", tr("lbl_f_alpha"), min = 0.1, max = 0.9,
                                        value = d$focal_alpha, step = 0.05, width = "100%"))),
                 kind = "group"),
            cols = 3L)),
        card("save_mode", "lbl_save_mode", "help_save_mode",
             pills("save_mode", c("replace", "append"), c("save_replace", "save_append"), d$save_mode),
             kind = "group"),
        shiny::tags$details(
          class = "pam-advanced",
          shiny::tags$summary(tr("sec_advanced")),
          grid(
            card("threads", "lbl_threads", NULL, number("threads", NA, min = 1, step = 1)),
            card("n_runs", "lbl_n_runs", "help_n_runs", number("n_runs", 1, min = 1, step = 1))),
          shiny::checkboxInput("overwrite", tr("lbl_overwrite"), value = FALSE)),
        # ---------------------------------------------------- run and progress
        shiny::div(class = "pam-curve", shiny::plotOutput("curve", height = "300px")),
        shiny::actionButton("start", tr("btn_start"), class = "btn-primary pam-start"),
        shiny::div(class = "pam-actions",
                   shiny::actionButton("stop", tr("btn_stop")),
                   shiny::actionButton("open_out", tr("btn_open_folder"))),
        shiny::uiOutput("status_ui"),
        shiny::tags$h5(tr("log_title"), class = "pam-log-title"),
        shiny::verbatimTextOutput("log")),
      shiny::tabPanel(tr("tab_results"), shiny::uiOutput("results_ui")),
      shiny::tabPanel(tr("tab_runs"),
                      shiny::p(tr("runs_help")),
                      shiny::tableOutput("runs_table"),
                      shiny::plotOutput("runs_plot", height = "280px"))))

  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(job = NULL, plan = NULL, state = "idle", text = "", queue = character(),
                                k = 0L, n = 0L, t0 = NULL, results = list(), last = NULL,
                                stopped = FALSE, inputs = NULL, refresh = 0L)
    classes <- shiny::reactiveVal(NULL)

    plot_labels <- list(title = tr("plot_title"), x = tr("plot_x"), y = tr("plot_y"),
                        auprc = tr("series_auprc"), auroc = tr("series_auroc"),
                        waiting = tr("plot_waiting"))

    # ------------------------------------------------------------ data check
    check_data <- function(dir) {
      dir <- trimws(as.character(dir))
      if (!nzchar(dir) || !dir.exists(dir)) {
        classes(NULL)
        return(invisible(NULL))
      }
      classes(tryCatch(pam_birdnet_train_prepare(dir, quiet = TRUE), error = function(e) NULL))
      invisible(NULL)
    }
    pick_start <- function(path) {
      path <- trimws(as.character(path))
      if (length(path) == 1L && nzchar(path) && dir.exists(path)) path else getwd()
    }
    pick_into <- function(input_id, key, after = NULL) {
      d <- pam_pick_dir(tr(key), default = pick_start(input[[input_id]]))
      if (is.null(d)) {
        shiny::showNotification(tr("picker_unavailable"), type = "message")
      } else {
        shiny::updateTextInput(session, input_id, value = d)
        if (!is.null(after)) after(d)
      }
    }
    shiny::observeEvent(input$pick_train, pick_into("train_dir", "lbl_train_dir", check_data))
    shiny::observeEvent(input$pick_test, pick_into("test_dir", "lbl_test_dir"))
    shiny::observeEvent(input$pick_out, pick_into("out_dir", "lbl_out_dir"))
    shiny::observeEvent(input$pick_cache, {
      f <- pam_pick_file()
      if (is.null(f)) shiny::showNotification(tr("picker_unavailable"), type = "message")
      else shiny::updateTextInput(session, "cache_file", value = f)
    })
    shiny::observeEvent(input$check_data, check_data(input$train_dir))

    n_classes <- shiny::reactive({
      x <- classes()
      if (is.null(x)) NA_integer_ else nrow(x$classes)
    })

    output$class_table <- shiny::renderTable({
      x <- classes()
      shiny::req(x)
      df <- x$classes[, c("class", "n_audio"), drop = FALSE]
      names(df) <- c(tr("tbl_class"), tr("tbl_clips"))
      df
    }, striped = TRUE, spacing = "xs")

    output$data_summary <- shiny::renderUI({
      x <- classes()
      if (is.null(x)) return(NULL)
      shiny::tagList(
        shiny::div(style = "max-height:220px; overflow-y:auto; margin-top:8px;",
                   shiny::tableOutput("class_table")),
        if (x$ok) shiny::div(class = "text-success", tr("no_issues"))
        else shiny::tagList(shiny::strong(tr("issues_title")),
                            shiny::tags$ul(lapply(x$issues, shiny::tags$li))))
    })

    # --------------------------------------------------------- the form values
    collect_inputs <- function() {
      list(train_dir = input$train_dir, test_dir = input$test_dir, out_dir = input$out_dir,
           clf_name = input$clf_name, out_format = input$out_format, cache_mode = input$cache_mode,
           cache_file = input$cache_file, fmin = input$fmin, fmax = input$fmax,
           audio_speed = input$audio_speed, crop_mode = input$crop_mode,
           crop_overlap = input$crop_overlap, autotune = input$autotune, at_trials = input$at_trials,
           at_exec = input$at_exec, epochs = input$epochs, batch_size = input$batch_size,
           learning_rate = input$learning_rate, hidden_units = input$hidden_units,
           dropout = input$dropout, val_split = input$val_split,
           label_smoothing = input$label_smoothing, ups_mode = input$ups_mode,
           ups_ratio = input$ups_ratio, mixup = input$mixup, focal = input$focal,
           f_gamma = input$f_gamma, f_alpha = input$f_alpha, save_mode = input$save_mode,
           threads = input$threads, overwrite = input$overwrite, n_runs = input$n_runs)
    }

    # ------------------------------------------------------------ running jobs
    start_next <- function() {
      x <- rv$inputs
      out <- rv$queue[1L]
      rv$queue <- rv$queue[-1L]
      rv$k <- rv$k + 1L
      opts <- pam_train_params_from_inputs(x)
      plan <- tryCatch(
        pam_train_plan(data_dir = opts$data_dir, output = out, params = opts$params,
                       test_data = opts$test_data, cache_mode = opts$cache_mode,
                       cache_file = opts$cache_file, envdir = envdir,
                       overwrite = isTRUE(x$overwrite)),
        error = function(e) {
          shiny::showNotification(conditionMessage(e), type = "error", duration = NULL)
          NULL
        })
      if (is.null(plan)) {
        rv$state <- "idle"
        rv$queue <- character()
        return(invisible(NULL))
      }
      rv$plan <- plan
      rv$job <- pam_job_start(plan$bin, plan$args, plan$log_file)
      rv$text <- ""
      rv$t0 <- Sys.time()
      rv$state <- "running"
      invisible(NULL)
    }

    poll_once <- function() {
      if (!rv$state %in% c("running", "stopping")) return(invisible(NULL))
      job <- rv$job
      txt <- pam_job_poll(job)
      if (nzchar(txt)) rv$text <- paste0(rv$text, txt)
      if (pam_job_alive(job)) return(invisible(NULL))
      rest <- pam_job_drain(job)
      if (nzchar(rest)) rv$text <- paste0(rv$text, rest)
      status <- pam_job_close(job)
      elapsed <- difftime(Sys.time(), rv$t0, units = "mins")
      res <- pam_train_finish(rv$plan, status, elapsed, quiet = TRUE)
      rv$results[[length(rv$results) + 1L]] <- res
      rv$last <- res
      rv$refresh <- rv$refresh + 1L
      if (length(rv$queue) && identical(res$status, "ok") && !isTRUE(rv$stopped)) {
        start_next()
      } else {
        rv$state <- "idle"
        rv$queue <- character()
        if (isTRUE(rv$stopped)) {
          shiny::showNotification(tr("notif_stopped"), type = "warning")
        } else if (identical(res$status, "ok")) {
          shiny::showNotification(tr("notif_done"), type = "message")
        } else {
          shiny::showNotification(tr("notif_failed"), type = "error", duration = NULL)
        }
      }
      invisible(NULL)
    }

    shiny::observe({
      shiny::invalidateLater(500L, session)
      shiny::isolate(poll_once())
    })

    shiny::observeEvent(input$start, {
      if (!identical(rv$state, "idle")) return(invisible(NULL))
      x <- collect_inputs()
      errs <- pam_train_validate_inputs(x)
      if (length(errs)) {
        for (e in errs) shiny::showNotification(tr(e), type = "error", duration = 10)
        return(invisible(NULL))
      }
      base <- file.path(trimws(x$out_dir), trimws(x$clf_name))
      n <- as.integer(round(x$n_runs))
      rv$queue <- pam_train_run_names(base, n)
      rv$n <- n
      rv$k <- 0L
      rv$stopped <- FALSE
      rv$results <- list()
      rv$last <- NULL
      rv$inputs <- x
      start_next()
      invisible(NULL)
    })

    shiny::observeEvent(input$stop, {
      if (identical(rv$state, "running")) {
        rv$stopped <- TRUE
        rv$queue <- character()
        pam_job_stop(rv$job)
        rv$state <- "stopping"
      }
    })

    shiny::observeEvent(input$open_out, {
      dir <- trimws(input$out_dir)
      if (nzchar(dir) && dir.exists(dir)) utils::browseURL(dir)
      else shiny::showNotification(tr("err_no_output"), type = "error")
    })

    session$onSessionEnded(function() {
      job <- shiny::isolate(rv$job)
      if (!is.null(job)) {
        pam_job_stop(job)
        pam_job_close(job)
      }
    })

    # --------------------------------------------------------------- progress
    prog <- shiny::reactive(pam_train_progress(rv$text, n_classes()))
    metrics <- shiny::reactive(pam_train_parse_metrics(rv$text))

    status_message <- function(state, p) {
      prefix <- if (rv$n > 1L && state != "idle") paste0(tr("run_of", rv$k, rv$n), ": ") else ""
      if (state == "idle") {
        res <- rv$last
        if (is.null(res)) return(tr("status_idle"))
        if (isTRUE(rv$stopped)) return(tr("status_stopped"))
        if (!identical(res$status, "ok")) return(tr("status_failed"))
        return(paste0(tr("status_finished"), if (isTRUE(p$stopped_early)) paste0(" ", tr("res_early")) else ""))
      }
      if (state == "stopping") return(tr("status_stopping"))
      body <- switch(
        p$phase,
        starting = tr("phase_starting"),
        downloading = tr("phase_downloading", sprintf("%d%%", as.integer(p$download_pct))),
        loading = if (!is.na(p$n_classes)) tr("phase_loading", p$classes_done, p$n_classes) else tr("phase_loading_unknown"),
        cache = tr("phase_cache"),
        building = tr("phase_building"),
        training = if (!is.na(p$epoch)) tr("phase_training", p$epoch, p$n_epochs) else tr("phase_training_start"),
        saving = tr("phase_saving"),
        done = tr("phase_saving"),
        tr("phase_starting"))
      paste0(prefix, body)
    }

    output$status_ui <- shiny::renderUI({
      st <- rv$state
      p <- prog()
      pct <- as.integer(round(100 * p$fraction))
      if (identical(st, "idle")) {
        pct <- if (!is.null(rv$last) && identical(rv$last$status, "ok")) 100L else 0L
      }
      shiny::tagList(
        shiny::div(role = "status", `aria-live` = "polite",
                   class = "pam-status", status_message(st, p)),
        shiny::div(class = "progress",
                   shiny::div(class = "progress-bar", role = "progressbar",
                              `aria-valuenow` = pct, `aria-valuemin` = 0, `aria-valuemax` = 100,
                              style = sprintf("width:%d%%;", pct), sprintf("%d%%", pct))))
    })

    dark <- shiny::reactive(identical(input$theme, "dark"))
    output$curve <- shiny::renderPlot(pam_train_plot_history(metrics()$history, plot_labels, dark()),
                                      bg = "transparent")
    output$log <- shiny::renderText(paste(pam_train_log_lines(rv$text), collapse = "\n"))

    # ---------------------------------------------------------------- results
    output$files_table <- shiny::renderTable({
      res <- rv$last
      shiny::req(res)
      files <- data.frame(file = basename(paste0(res$output, c(".tflite", "_Labels.txt", "_Params.csv", "_sample_counts.csv"))),
                          present = ifelse(res$files, tr("yes"), tr("no")), stringsAsFactors = FALSE)
      names(files) <- c(tr("tbl_file"), tr("tbl_present"))
      files
    }, striped = TRUE, spacing = "xs")
    output$session_table <- shiny::renderTable(session_table(), striped = TRUE, spacing = "xs")

    output$results_ui <- shiny::renderUI({
      res <- rv$last
      if (is.null(res)) return(shiny::p(tr("results_empty")))
      m <- res$metrics
      has_best <- !is.null(m) && !is.na(m$best$auprc)
      shiny::tagList(
        shiny::h4(if (identical(res$status, "ok")) tr("res_ok") else tr("res_failed")),
        if (has_best) shiny::p(tr("res_best", sprintf("%.3f", m$best$auprc), sprintf("%.3f", m$best$auroc),
                                  m$best$epoch, m$best$n_epochs)),
        if (has_best) shiny::p(tr(if (is.null(res$evaluation)) "res_split" else "res_split_test", m$n_train, m$n_val)),
        if (isTRUE(res$cache$mismatch)) shiny::div(
          class = "alert alert-warning", role = "alert",
          shiny::strong(tr("res_cache_mismatch")),
          if (length(res$cache$cache_settings)) shiny::tags$pre(paste(res$cache$cache_settings, collapse = "\n"))),
        if (isTRUE(res$cache$missing)) shiny::div(class = "alert alert-warning", role = "alert",
                                                  tr("res_cache_missing")),
        if (is.null(res$evaluation)) shiny::p(shiny::em(tr("res_note_validation"))),
        if (!is.null(res$evaluation)) shiny::uiOutput("eval_ui"),
        shiny::h5(tr("res_files")),
        shiny::tableOutput("files_table"),
        if (identical(res$status, "ok")) shiny::tagList(
          shiny::h5(tr("res_snippet_title")),
          shiny::p(tr("res_snippet_help")),
          shiny::tags$pre(pam_train_config_snippet(res$output))),
        if (length(rv$results) > 1L) shiny::tagList(shiny::h5(tr("res_session")),
                                                     shiny::tableOutput("session_table")))
    })

    # ----------------------------------------------------- per-class test results
    eval_labels <- function() {
      list(overall = tr("res_overall"), class = tr("tbl_class"), clips = tr("tbl_test_clips"),
           precision = tr("tbl_precision"), recall = tr("tbl_recall"), f1 = tr("tbl_f1"),
           auprc = tr("series_auprc"), auroc = tr("series_auroc"), threshold = tr("tbl_threshold"),
           tp = tr("tbl_tp"), fp = tr("tbl_fp"), fn = tr("tbl_fn"), tn = tr("tbl_tn"))
    }
    output$eval_ui <- shiny::renderUI({
      res <- rv$last
      shiny::req(res, res$evaluation)
      shiny::tagList(
        shiny::h5(tr("res_test_title")),
        shiny::p(tr("res_test_help")),
        shiny::div(
          class = "pam-eval-controls",
          shiny::tags$span(class = "pam-card-title", id = "eval_thr_title", tr("lbl_eval_threshold")),
          shiny::div(role = "radiogroup", `aria-labelledby` = "eval_thr_title",
                     pills("eval_thr", c("opt", "default"), c("thr_opt", "thr_default"), "opt"))),
        shiny::div(style = "overflow-x:auto;", shiny::tableOutput("eval_table")),
        shiny::p(shiny::em(tr("res_test_note"))),
        shiny::tags$details(
          class = "pam-advanced",
          shiny::tags$summary(tr("res_counts")),
          shiny::div(style = "overflow-x:auto;", shiny::tableOutput("eval_counts"))))
    })
    output$eval_table <- shiny::renderTable({
      shiny::req(rv$last, rv$last$evaluation)
      pam_train_eval_table(rv$last$evaluation, if (identical(input$eval_thr, "default")) "default" else "opt",
                           eval_labels())
    }, striped = TRUE, spacing = "xs", align = "l")
    output$eval_counts <- shiny::renderTable({
      shiny::req(rv$last, rv$last$evaluation)
      pam_train_eval_counts(rv$last$evaluation, eval_labels())
    }, striped = TRUE, spacing = "xs", align = "l")

    session_table <- function() {
      rows <- lapply(seq_along(rv$results), function(i) {
        r <- rv$results[[i]]
        b <- if (is.null(r$metrics)) list(auprc = NA_real_, auroc = NA_real_, loss = NA_real_) else r$metrics$best
        data.frame(run = basename(r$output), auprc = b$auprc, auroc = b$auroc, loss = b$loss,
                   stringsAsFactors = FALSE)
      })
      df <- do.call(rbind, rows)
      ok <- stats::complete.cases(df[, c("auprc", "auroc", "loss")])
      if (sum(ok) > 1L) {
        summary_rows <- data.frame(
          run = c(tr("tbl_mean"), tr("tbl_sd")),
          auprc = c(mean(df$auprc[ok]), stats::sd(df$auprc[ok])),
          auroc = c(mean(df$auroc[ok]), stats::sd(df$auroc[ok])),
          loss = c(mean(df$loss[ok]), stats::sd(df$loss[ok])), stringsAsFactors = FALSE)
        df <- rbind(df, summary_rows)
      }
      names(df) <- c(tr("tbl_run"), tr("series_auprc"), tr("series_auroc"), tr("tbl_loss"))
      df
    }

    # ---------------------------------------------------------------- history
    runs <- shiny::reactive({
      rv$refresh
      pam_train_runs_table(trimws(input$out_dir))
    })
    output$runs_table <- shiny::renderTable({
      tbl <- runs()
      if (!nrow(tbl)) return(stats::setNames(data.frame(tr("runs_empty"), stringsAsFactors = FALSE), tr("tab_runs")))
      out <- data.frame(tbl$run, tbl$finished, tbl$status, tbl$epochs, tbl$auprc, tbl$auroc, tbl$loss,
                        tbl$hidden_units, tbl$dropout, tbl$learning_rate, tbl$minutes, check.names = FALSE,
                        stringsAsFactors = FALSE)
      names(out) <- c(tr("tbl_run"), tr("tbl_finished"), tr("tbl_status"), tr("tbl_epochs"),
                      tr("series_auprc"), tr("series_auroc"), tr("tbl_loss"), tr("tbl_hidden"),
                      tr("tbl_dropout"), tr("tbl_lr"), tr("tbl_minutes"))
      out
    }, striped = TRUE, spacing = "xs", na = "")
    output$runs_plot <- shiny::renderPlot(
      pam_train_plot_runs(runs(), utils::modifyList(plot_labels, list(title = tr("runs_plot_title"),
                                                                       x = tr("tbl_run"), empty = tr("runs_empty"))),
                          dark()),
      bg = "transparent")
  }

  shiny::shinyApp(ui = ui, server = server)
}
