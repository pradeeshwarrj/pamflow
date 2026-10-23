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
#' @return A `shiny.appobj`.
#' @keywords internal
#' @noRd
pam_validation_app <- function(cfg, run_id = cfg$birdnet$run_id, reviewer = "",
                               show_confidence = FALSE) {
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

  set.seed(1)
  ids <- sample(samples$sample_id)            # fixed shuffled order: blind to species and band
  pos0 <- which(!ids %in% results0$sample_id)[1]
  if (is.na(pos0)) pos0 <- 1L

  shiny::addResourcePath("pamclips", clip_dir)
  shiny::addResourcePath("pamspecs", spec_dir)
  tg <- shiny::tags

  ui <- shiny::fluidPage(
    shiny::titlePanel("PAM validation"),
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        width = 4,
        shiny::textInput("reviewer", "Reviewer", value = reviewer),
        shiny::uiOutput("progress"),
        shiny::hr(),
        shiny::uiOutput("meta"),
        shiny::radioButtons("verdict", "Is the predicted species present in the highlighted window?",
                            choices = c("Correct" = "correct", "Incorrect" = "incorrect",
                                        "Unsure" = "unsure"), selected = character(0)),
        shiny::conditionalPanel(
          "input.verdict == 'incorrect'",
          shiny::selectizeInput("true_species", "True species (pick or type, blank if unknown)",
                                choices = choices, selected = "",
                                options = list(create = TRUE))),
        shiny::textInput("note", "Note (optional)"),
        shiny::actionButton("save", "Save & next", class = "btn-primary"),
        shiny::actionButton("prev", "Previous"),
        shiny::actionButton("skip", "Skip")),
      shiny::mainPanel(width = 8, shiny::uiOutput("media"))))

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

    output$progress <- shiny::renderUI(tg$p(tg$strong(sprintf(
      "%d of %d reviewed", nrow(rv$results), nrow(samples)))))
    output$meta <- shiny::renderUI({
      s <- current()
      shiny::tagList(
        tg$h4(s$common_name), tg$em(s$scientific_name),
        tg$p(sprintf("Grid %s | %s", s$grid, s$detection_datetime)),
        if (show_confidence) tg$p(sprintf("Model confidence: %.2f", s$confidence)))
    })
    output$media <- shiny::renderUI({
      s <- current()
      clip_src <- get_audio_src(s)
      shiny::tagList(
        tg$img(src = paste0("pamspecs/", s$spec_file), style = "width:100%;max-width:1000px;"),
        tg$p(sprintf("Detection window: %.1f to %.1f s of the clip (the rest is context)",
                     s$event_offset_s, s$event_end_offset_s)),
        tg$p("Whole clip"),
        tg$audio(src = clip_src, controls = NA, style = "width:100%;"),
        tg$p("Detection window only"),
        tg$audio(src = sprintf("%s#t=%.2f,%.2f", clip_src, s$event_offset_s, s$event_end_offset_s),
                 controls = NA, style = "width:100%;"))
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
        shiny::showNotification("Choose Correct, Incorrect or Unsure first", type = "warning")
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
        shiny::showNotification("All samples reviewed", type = "message")
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
#' @return Nothing; runs until the app is closed.
#' @export
pam_validate <- function(cfg, run_id = cfg$birdnet$run_id,
                         reviewer = pam_or(cfg$validation$reviewer, ""),
                         show_confidence = isTRUE(cfg$validation$show_confidence)) {
  app <- pam_validation_app(cfg, run_id, reviewer, show_confidence)
  shiny::runApp(app, launch.browser = TRUE)
}
