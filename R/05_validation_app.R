#' Build the validation Shiny app (internal)
#'
#' Interactive review UI for audio clips and spectrograms. Transcodes FLAC
#' clips to temporary WAV files on demand so HTML5 `<audio>` elements play
#' reliably in all web browsers.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @param reviewer Reviewer name pre-filled in the app.
#' @param show_confidence Show the model's confidence while reviewing.
#' @param lang Interface language code (see `pam_train_app()`); `NULL` chooses it.
#' @return A `shiny.appobj`.
#' @keywords internal
#' @noRd
pam_validation_app <- function(cfg, run_id = cfg$birdnet$run_id, reviewer = "",
                               show_confidence = FALSE, lang = NULL) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    rlang::abort("Package 'shiny' is required: install.packages(\"shiny\")")
  }
  val_dir <- file.path(cfg$paths$detections, run_id, "validation")
  samples_path <- file.path(val_dir, "validation_samples.csv")
  results_path <- file.path(val_dir, "validation_results.csv")
  clip_dir <- file.path(val_dir, "clips"); spec_dir <- file.path(val_dir, "spectrograms")
  if (!file.exists(samples_path)) rlang::abort("No samples yet. Run pam_validation_draw() first.")

  samples <- data.table::fread(samples_path)
  ready <- file.exists(file.path(clip_dir, samples$clip_file)) &
    file.exists(file.path(spec_dir, samples$spec_file))
  if (!any(ready)) rlang::abort("No clips found. Run pam_validation_export() first.")
  if (!all(ready)) {
    warning(sum(!ready), " samples have no clip/spectrogram yet and are hidden")
    samples <- samples[ready]
  }

  empty <- data.table::data.table(sample_id = integer(), verdict = character(),
                                  true_species = character(), note = character(),
                                  reviewer = character(), reviewed_at = character())
  results0 <- if (file.exists(results_path)) {
    data.table::fread(results_path, colClasses = list(
      character = c("verdict", "true_species", "note", "reviewer", "reviewed_at")))
  } else empty

  labels <- tryCatch(readLines(pam_detect_settings(cfg)$labels_file, warn = FALSE),
                     error = function(e) character())
  choices <- unique(c("", "(none: noise or no animal sound)", labels, samples$species,
                      "(other / unknown)", results0$true_species))
  choices <- choices[!is.na(choices)]

  ids <- withr::with_seed(1, sample(samples$sample_id))   # fixed shuffled order: blind to species and band
  pos0 <- which(!ids %in% results0$sample_id)[1]
  if (is.na(pos0)) pos0 <- 1L

  shiny::addResourcePath("pamclips", clip_dir)
  shiny::addResourcePath("pamspecs", spec_dir)
  tg <- shiny::tags
  tr <- pam_i18n(lang)
  w <- pam_app_widgets(tr)
  card <- w$card; pills <- w$pills; grid <- w$grid
  pam_app_assets()

  ui <- shiny::fluidPage(
    title = tr("val_page_title"),
    pam_app_head(),
    pam_app_header(tr, "val_title"),
    grid(
      card("reviewer", "val_lbl_reviewer", "val_desc_reviewer",
           shiny::textInput("reviewer", label = NULL, value = reviewer, width = "100%")),
      shiny::div(class = "pam-card", shiny::uiOutput("progress"))),
    shiny::uiOutput("meta"),
    shiny::uiOutput("media"),
    card("verdict", "val_lbl_verdict", NULL,
         pills("verdict", c("correct", "incorrect", "unsure"),
               c("val_correct", "val_incorrect", "val_unsure"), character(0)),
         kind = "group"),
    shiny::conditionalPanel(
      "input.verdict == 'incorrect'",
      card("true_species", "val_lbl_true_species", "val_desc_true_species",
           shiny::selectizeInput("true_species", label = NULL, choices = choices, selected = "",
                                 width = "100%", options = list(create = TRUE)))),
    card("note", "lbl_note", NULL, shiny::textInput("note", label = NULL, width = "100%")),
    shiny::actionButton("save", tr("btn_save_next"), class = "btn-primary pam-start"),
    shiny::div(class = "pam-nav",
               shiny::actionButton("prev", tr("btn_prev")),
               shiny::actionButton("skip", tr("btn_skip"))))

  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(pos = pos0, results = results0)
    current <- shiny::reactive(samples[sample_id == ids[rv$pos]])

    # Temporary directory for transcoding FLAC clips for browser compatibility
    tmp_wav_dir <- tempfile("shiny_wav_")
    dir.create(tmp_wav_dir, recursive = TRUE, showWarnings = FALSE)
    shiny::addResourcePath("pamtmps", tmp_wav_dir)

    session$onSessionEnded(function() {
      if (dir.exists(tmp_wav_dir)) unlink(tmp_wav_dir, recursive = TRUE)
    })

    # Helper function to ensure playable WAV URL for HTML5 audio controls
    get_audio_src <- function(s) {
      clip_path <- file.path(clip_dir, s$clip_file)
      if (pam_is_flac(clip_path)) {
        wav_name <- paste0(tools::file_path_sans_ext(s$clip_file), ".wav")
        tmp_wav_path <- file.path(tmp_wav_dir, wav_name)
        if (!file.exists(tmp_wav_path)) {
          if (requireNamespace("av", quietly = TRUE)) {
            suppressMessages(av::av_audio_convert(clip_path, tmp_wav_path, verbose = FALSE))
          } else {
            wave_obj <- pam_read_audio(clip_path)
            tuneR::writeWave(wave_obj, tmp_wav_path)
          }
        }
        return(paste0("pamtmps/", wav_name))
      }
      paste0("pamclips/", s$clip_file)
    }

    output$progress <- shiny::renderUI(shiny::tagList(
      tg$p(class = "pam-progress-text", tr("val_progress", nrow(rv$results), nrow(samples))),
      pam_app_progress_bar(nrow(rv$results), nrow(samples))))
    output$meta <- shiny::renderUI({
      s <- current()
      shiny::div(
        class = "pam-card",
        tg$p(class = "pam-meta-title", s$common_name),
        tg$span(class = "pam-meta-sub", s$scientific_name),
        tg$p(class = "pam-meta-line", tr("val_meta_where", s$grid, s$detection_datetime)),
        if (show_confidence) tg$p(class = "pam-meta-line", tr("val_meta_conf", s$confidence)))
    })
    output$media <- shiny::renderUI({
      s <- current()
      clip_src <- get_audio_src(s)
      shiny::div(
        class = "pam-media",
        tg$img(src = paste0("pamspecs/", s$spec_file), alt = tr("val_spec_alt")),
        tg$p(class = "pam-meta-line", tr("val_window", s$event_offset_s, s$event_end_offset_s)),
        shiny::div(class = "pam-audio-label", tr("val_whole_clip")),
        tg$audio(src = clip_src, controls = NA),
        shiny::div(class = "pam-audio-label", tr("val_window_only")),
        tg$audio(src = sprintf("%s#t=%.2f,%.2f", clip_src, s$event_offset_s, s$event_end_offset_s),
                 controls = NA))
    })

    shiny::observeEvent(rv$pos, {             # show an earlier verdict when revisiting
      r <- rv$results[sample_id == ids[rv$pos]]
      if (nrow(r)) {
        shiny::updateRadioButtons(session, "verdict", selected = r$verdict[1])
        shiny::updateSelectizeInput(session, "true_species", selected = r$true_species[1])
        shiny::updateTextInput(session, "note", value = r$note[1])
      } else {
        shiny::updateRadioButtons(session, "verdict", selected = character(0))
        shiny::updateSelectizeInput(session, "true_species", selected = "")
        shiny::updateTextInput(session, "note", value = "")
      }
    })

    shiny::observeEvent(input$save, {
      if (is.null(input$verdict) || !nzchar(input$verdict)) {
        shiny::showNotification(tr("val_choose_first"), type = "warning")
        return()
      }
      sp <- if (identical(input$verdict, "incorrect") && !is.null(input$true_species)) {
        input$true_species
      } else ""
      row <- data.table::data.table(
        sample_id = ids[rv$pos], verdict = input$verdict, true_species = sp,
        note = pam_or(input$note, ""), reviewer = pam_or(input$reviewer, ""),
        reviewed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      res <- data.table::rbindlist(list(rv$results[sample_id != row$sample_id], row))
      pam_write_csv_atomic(res, results_path)
      rv$results <- res
      todo <- which(!ids %in% res$sample_id)
      nxt <- todo[todo > rv$pos]
      if (!length(nxt)) nxt <- todo
      if (length(nxt)) rv$pos <- nxt[1] else {
        shiny::showNotification(tr("val_all_done"), type = "message")
      }
    })
    shiny::observeEvent(input$prev, rv$pos <- max(1L, rv$pos - 1L))
    shiny::observeEvent(input$skip, rv$pos <- min(length(ids), rv$pos + 1L))
  }
  shiny::shinyApp(ui, server)
}

#' Open the validation app
#'
#' Shows the exported spectrogram and audio of each sampled event in random
#' order and records "correct", "incorrect" (plus the true species) or
#' "unsure". Every save is written immediately to `validation_results.csv`, so
#' you can stop at any time and continue later.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @param reviewer Name pre-filled in the app.
#' @param show_confidence Show the model's confidence while reviewing. Hidden
#'   by default (`validation$show_confidence`) to avoid biasing the reviewer.
#' @param lang Interface language code (for example `"en"`); `NULL` chooses it as
#'   `pam_train_app()` does. Translations live in `inst/i18n/<code>.yml`.
#' @return Nothing; runs until the app is closed.
#' @examples
#' if (interactive() && nzchar(Sys.which("ffmpeg"))) {
#'   ex <- pam_example_project()
#'   res <- suppressMessages(pam_scan_audio(ex$cfg))
#'   proc <- suppressMessages(pam_process_detections(ex$cfg))
#'   new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 5))
#'   out <- suppressMessages(pam_validation_export(ex$cfg))   # clips and spectrograms to review
#'   pam_validate(ex$cfg)
#' }
#' @export
pam_validate <- function(cfg, run_id = cfg$birdnet$run_id,
                         reviewer = pam_or(cfg$validation$reviewer, ""),
                         show_confidence = isTRUE(cfg$validation$show_confidence), lang = NULL) {
  app <- pam_validation_app(cfg, run_id, reviewer, show_confidence, lang)
  shiny::runApp(app, launch.browser = TRUE)
}
