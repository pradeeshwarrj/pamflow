#' Build the ground-truth annotation app (internal)
#'
#' @param cfg A `pam_config` object.
#' @param reviewer Annotator name pre-filled in the app.
#' @return A `shiny.appobj`.
#' @keywords internal
#' @noRd
pam_annotation_app <- function(cfg, reviewer = "") {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    rlang::abort("Package 'shiny' is required: install.packages(\"shiny\")")
  }
  gt_dir <- pam_gt_dir(cfg)
  seg_path <- file.path(gt_dir, "recall_segments.csv")
  res_path <- file.path(gt_dir, "recall_annotations.csv")
  clip_dir <- file.path(gt_dir, "clips"); spec_dir <- file.path(gt_dir, "spectrograms")
  if (!file.exists(seg_path)) rlang::abort("No segments yet. Run pam_recall_draw() first.")

  seg <- data.table::fread(seg_path)
  ready <- file.exists(file.path(clip_dir, seg$clip_file)) &
    file.exists(file.path(spec_dir, seg$spec_file))
  if (!any(ready)) rlang::abort("No segment files found. Run pam_recall_export() first.")
  if (!all(ready)) {
    warning(sum(!ready), " segments have no files yet and are hidden")
    seg <- seg[ready]
  }

  chr <- c("present", "possible", "other", "note", "reviewer", "reviewed_at")
  empty <- data.table::data.table(segment_id = integer(), present = character(),
                                  possible = character(), other = character(),
                                  none_audible = logical(), note = character(),
                                  reviewer = character(), reviewed_at = character())
  res0 <- if (file.exists(res_path)) {
    data.table::fread(res_path, colClasses = list(character = chr))
  } else empty

  labels <- tryCatch(readLines(pam_detect_settings(cfg)$labels_file, warn = FALSE),
                     error = function(e) character())
  labels <- labels[nzchar(labels)]

  set.seed(1)
  ids <- sample(seg$segment_id)                  # shuffled order
  pos0 <- which(!ids %in% res0$segment_id)[1]
  if (is.na(pos0)) pos0 <- 1L

  shiny::addResourcePath("gtclips", clip_dir)
  shiny::addResourcePath("gtspecs", spec_dir)
  tg <- shiny::tags
  split_labels <- function(x) {
    if (is.null(x) || is.na(x) || !nzchar(x)) character(0) else strsplit(x, ";", fixed = TRUE)[[1]]
  }

  ui <- shiny::fluidPage(
    shiny::titlePanel("Ground-truth annotation"),
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        width = 4,
        shiny::textInput("reviewer", "Annotator", value = reviewer),
        shiny::uiOutput("progress"),
        shiny::hr(),
        shiny::selectizeInput("present", "Species you hear (all of them)", choices = labels,
                              multiple = TRUE),
        shiny::selectizeInput("possible", "Possibly present (not sure)", choices = labels,
                              multiple = TRUE),
        shiny::textInput("other", "Other species heard (not in the list)"),
        shiny::checkboxInput("none", "No species from the list audible in this segment"),
        shiny::textInput("note", "Note (optional)"),
        shiny::actionButton("save", "Save & next", class = "btn-primary"),
        shiny::actionButton("prev", "Previous"),
        shiny::actionButton("skip", "Skip")),
      shiny::mainPanel(width = 8, shiny::uiOutput("media"))))

  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(pos = pos0, results = res0)
    current <- shiny::reactive(seg[segment_id == ids[rv$pos]])

    output$progress <- shiny::renderUI(tg$p(tg$strong(sprintf(
      "%d of %d segments annotated", nrow(rv$results), nrow(seg)))))
    output$media <- shiny::renderUI({
      s <- current()
      src <- paste0("gtclips/", s$clip_file)
      shiny::tagList(
        tg$p(sprintf("Segment of %d s, local time %s", s$segment_s, substr(s$slot_time, 12, 19))),
        tg$img(src = paste0("gtspecs/", s$spec_file), style = "width:100%;"),
        tg$audio(src = src, controls = NA, style = "width:100%;"))
    })

    shiny::observeEvent(rv$pos, {
      r <- rv$results[segment_id == ids[rv$pos]]
      if (nrow(r)) {
        shiny::updateSelectizeInput(session, "present", selected = split_labels(r$present[1]))
        shiny::updateSelectizeInput(session, "possible", selected = split_labels(r$possible[1]))
        shiny::updateTextInput(session, "other", value = r$other[1])
        shiny::updateCheckboxInput(session, "none", value = isTRUE(r$none_audible[1]))
        shiny::updateTextInput(session, "note", value = r$note[1])
      } else {
        shiny::updateSelectizeInput(session, "present", selected = character(0))
        shiny::updateSelectizeInput(session, "possible", selected = character(0))
        shiny::updateTextInput(session, "other", value = "")
        shiny::updateCheckboxInput(session, "none", value = FALSE)
        shiny::updateTextInput(session, "note", value = "")
      }
    })

    shiny::observeEvent(input$save, {
      present <- pam_or(input$present, character(0))
      other <- trimws(pam_or(input$other, ""))
      none <- isTRUE(input$none)
      if (!length(present) && !none && !nzchar(other)) {
        shiny::showNotification(
          "Pick the species you hear, or tick 'No species from the list audible'", type = "warning")
        return()
      }
      if (none && length(present)) {
        shiny::showNotification(
          "You ticked 'No species audible' but also picked species. Fix one of them.",
          type = "error")
        return()
      }
      row <- data.table::data.table(
        segment_id = ids[rv$pos], present = paste(present, collapse = ";"),
        possible = paste(pam_or(input$possible, character(0)), collapse = ";"),
        other = other, none_audible = none, note = pam_or(input$note, ""),
        reviewer = pam_or(input$reviewer, ""),
        reviewed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      res <- data.table::rbindlist(list(rv$results[segment_id != row$segment_id], row))
      pam_write_csv_atomic(res, res_path)
      rv$results <- res
      todo <- which(!ids %in% res$segment_id)
      nxt <- todo[todo > rv$pos]
      if (!length(nxt)) nxt <- todo
      if (length(nxt)) rv$pos <- nxt[1] else {
        shiny::showNotification("All segments annotated", type = "message")
      }
    })
    shiny::observeEvent(input$prev, rv$pos <- max(1L, rv$pos - 1L))
    shiny::observeEvent(input$skip, rv$pos <- min(length(ids), rv$pos + 1L))
  }
  shiny::shinyApp(ui, server)
}

#' Open the ground-truth annotation app
#'
#' Shows random recording segments, one at a time, in shuffled order, with a
#' spectrogram and audio. The model's detections are never shown, so the
#' annotation is independent of the detector. Record every species you hear;
#' mark doubtful ones as "possibly present". Each save is written immediately to
#' `recall_annotations.csv`, so you can stop and resume.
#'
#' @param cfg A `pam_config` object.
#' @param reviewer Annotator name pre-filled in the app.
#' @return Nothing; runs until the app is closed.
#' @export
pam_annotate <- function(cfg, reviewer = pam_or(cfg$recall$reviewer, "")) {
  shiny::runApp(pam_annotation_app(cfg, reviewer), launch.browser = TRUE)
}
