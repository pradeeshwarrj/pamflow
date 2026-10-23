# Stage 00 Shiny Triage & Standardization Application (Raven Compass Style)

#' Launch PAM Standardization & Data Triage Shiny App
#'
#' Interactive GUI for inspecting raw acoustic data, parsing timestamps, previewing
#' conversions, isolating non-audio/memo files, and performing standardized audio transcoding.
#'
#' @param cfg Optional configuration object from `pam_load_config()`.
#' @param raw_dir Optional path override for raw audio directory.
#' @return Runs Shiny application.
#' @importFrom shiny req
#' @importFrom utils head
#' @export
pam_standardization_app <- function(cfg = NULL, raw_dir = NULL) {
  if (is.null(cfg)) {
    cfg <- tryCatch(pam_load_config(), error = function(e) list())
  }

  paths_cfg <- pam_or(cfg$paths, list())
  dir_cfg <- pam_or(cfg$directories, list())
  std_cfg <- pam_or(cfg$standardization, list())
  fn_cfg <- pam_or(cfg$filenames, list())
  audio_cfg <- pam_or(cfg$audio, list())

  init_raw <- pam_or(raw_dir, pam_or(paths_cfg$audio_raw, pam_or(dir_cfg$raw, pam_or(dir_cfg$input, "data/raw"))))
  init_std <- pam_or(paths_cfg$audio_standardized, pam_or(dir_cfg$standardized, "data/standardized"))
  init_iso <- pam_or(paths_cfg$audio_isolated, pam_or(dir_cfg$isolated, "data/isolated"))
  init_tz <- pam_or(std_cfg$timezone, pam_or(fn_cfg$timezone, "Asia/Kolkata"))
  init_pattern <- pam_or(fn_cfg$pattern, "")
  init_target_hz <- pam_or(std_cfg$target_hz, pam_or(audio_cfg$sample_rate, 48000))

  ui <- shiny::fluidPage(
    title = "pamflow | Stage 00 Standardization & Data Triage",
    shiny::tags$head(
      shiny::tags$style(shiny::HTML("
        body { background-color: #121212; color: #e0e0e0; font-family: 'Segoe UI', Roboto, sans-serif; }
        .well, .panel { background-color: #1e1e1e; border: 1px solid #333; color: #e0e0e0; }
        .card-stat { background: #252526; border-radius: 6px; padding: 15px; text-align: center; border: 1px solid #3c3c3c; margin-bottom: 15px; }
        .card-stat h3 { margin: 0; color: #4fc3f7; font-weight: 600; }
        .card-stat p { margin: 5px 0 0 0; color: #aaaaaa; font-size: 0.9em; }
        .btn-primary { background-color: #0288d1; border-color: #0277bd; }
        .btn-success { background-color: #2e7d32; border-color: #1b5e20; }
        .btn-warning { background-color: #ef6c00; border-color: #e65100; }
        .table { color: #e0e0e0; }
        .nav-tabs > li > a { color: #aaaaaa; }
        .nav-tabs > li.active > a, .nav-tabs > li.active > a:focus, .nav-tabs > li.active > a:hover { color: #4fc3f7; background-color: #1e1e1e; border-color: #333; }
        .form-control { background-color: #2d2d2d; color: #ffffff; border: 1px solid #444; }
        .form-control:focus { background-color: #333333; color: #ffffff; border-color: #4fc3f7; }
        pre { background-color: #1e1e1e; color: #81c784; border: 1px solid #333; }
      "))
    ),

    shiny::titlePanel(
      shiny::div(
        shiny::span("pamflow", style = "color: #4fc3f7; font-weight: bold;"),
        shiny::span(" | Stage 00 Data Triage & Standardization", style = "font-size: 0.8em; color: #aaaaaa;")
      )
    ),

    shiny::tabsetPanel(
      id = "main_tabs",

      # TAB 1: INSPECT
      shiny::tabPanel(
        title = "Inspect Raw Data",
        shiny::br(),
        shiny::fluidRow(
          shiny::column(12,
                        shiny::wellPanel(
                          shiny::fluidRow(
                            shiny::column(5, shiny::textInput("raw_path", "Raw Data Directory:", value = init_raw, width = "100%")),
                            shiny::column(2, shiny::numericInput("min_dur", "Min Duration (s):", value = pam_or(std_cfg$min_duration_s, 60), min = 1)),
                            shiny::column(2, shiny::textInput("tz", "Timezone:", value = init_tz)),
                            shiny::column(3,
                                          shiny::br(),
                                          shiny::actionButton("btn_scan", "Scan Raw Directory", class = "btn-primary btn-block")
                            )
                          )
                        )
          )
        ),

        shiny::fluidRow(
          shiny::column(2, shiny::div(class = "card-stat", shiny::uiOutput("stat_total_files"), shiny::p("Total Files"))),
          shiny::column(2, shiny::div(class = "card-stat", shiny::uiOutput("stat_total_gb"), shiny::p("Total Size (GB)"))),
          shiny::column(2, shiny::div(class = "card-stat", shiny::uiOutput("stat_standardizable"), shiny::p("Standard Audio"))),
          shiny::column(2, shiny::div(class = "card-stat", shiny::uiOutput("stat_memos"), shiny::p("Short Memos"))),
          shiny::column(2, shiny::div(class = "card-stat", shiny::uiOutput("stat_non_audio"), shiny::p("Non-Audio Files"))),
          shiny::column(2, shiny::div(class = "card-stat", shiny::uiOutput("stat_corrupt"), shiny::p("Corrupt/Unreadable")))
        ),

        shiny::fluidRow(
          shiny::column(12,
                        shiny::h4("Raw File Inventory"),
                        shiny::tableOutput("tbl_inspect")
          )
        )
      ),

      # TAB 2: CONVERT
      shiny::tabPanel(
        title = "Convert & Standardize",
        shiny::br(),
        shiny::fluidRow(
          shiny::column(4,
                        shiny::wellPanel(
                          shiny::h4("Standardization Configuration"),
                          shiny::textInput("std_path", "Standardized Dir:", value = init_std),
                          shiny::textInput("iso_path", "Isolated Dir:", value = init_iso),
                          shiny::textInput("prefix", "Filename Prefix (optional):", value = pam_or(std_cfg$prefix, "")),
                          shiny::radioButtons("target_format", "Target Format:", choices = c("flac", "wav"), selected = pam_or(std_cfg$target_format, "flac"), inline = TRUE),
                          shiny::numericInput("target_hz", "Target Sample Rate (Hz):", value = init_target_hz),
                          shiny::radioButtons("channels", "Audio Channels:", choices = c("Mono (1)" = 1, "Stereo (2)" = 2), selected = pam_or(std_cfg$channels, 1)),
                          shiny::selectInput("organize_folders", "Subfolder Structure:", choices = c("Grid Directory (G0059/)" = "grid", "Grid + Date (G0059/YYYY/MM/DD)" = "grid_date", "Date Folders (YYYY/MM/DD)" = "date", "Preserve Hierarchy" = "preserve", "Flat (Single Directory)" = "flat"), selected = pam_or(std_cfg$organize_folders, "grid")),
                          shiny::selectInput("rename_strategy", "Rename Strategy:", choices = c("Auto Parsed Datetime" = "auto", "Keep Original Filename" = "keep"), selected = pam_or(std_cfg$rename_strategy, "auto")),
                          shiny::checkboxInput("isolate_non_audio", "Isolate Non-Audio Files", value = TRUE),
                          shiny::checkboxInput("isolate_short", "Isolate Short Clips (< Min Duration)", value = TRUE),
                          shiny::hr(),
                          shiny::fluidRow(
                            shiny::column(6, shiny::actionButton("btn_dry_run", "Dry Run", class = "btn-warning btn-block")),
                            shiny::column(6, shiny::actionButton("btn_run_std", "Run Standardization", class = "btn-success btn-block"))
                          )
                        )
          ),
          shiny::column(8,
                        shiny::wellPanel(
                          shiny::h4("Filename Transformation Preview"),
                          shiny::uiOutput("live_preview"),
                          shiny::hr(),
                          shiny::h4("Execution Log Output"),
                          shiny::verbatimTextOutput("log_console")
                        )
          )
        )
      ),

      # TAB 3: LOG
      shiny::tabPanel(
        title = "Log & Audit Trail",
        shiny::br(),
        shiny::fluidRow(
          shiny::column(12,
                        shiny::h4("Standardization Execution Summary"),
                        shiny::tableOutput("tbl_log")
          )
        )
      )
    )
  )

  server <- function(input, output, session) {
    inspect_data <- shiny::reactiveVal(data.table::data.table())
    log_data <- shiny::reactiveVal(data.table::data.table())
    console_text <- shiny::reactiveVal("Ready. Click 'Scan Raw Directory' or 'Dry Run' to evaluate dataset.")

    # Hidden reactive for pattern from config
    pattern_val <- shiny::reactiveVal(if (nzchar(init_pattern)) init_pattern else NULL)

    # Scan button trigger
    shiny::observeEvent(input$btn_scan, {
      shiny::req(input$raw_path)
      if (!dir.exists(input$raw_path)) {
        console_text(paste0("ERROR: Raw directory does not exist: ", input$raw_path))
        return()
      }

      shiny::withProgress(message = "Scanning and inspecting raw audio directory...", value = 0.5, {
        dt <- tryCatch({
          pam_inspect_raw(input$raw_path, recursive = TRUE, min_duration_s = input$min_dur, timezone = input$tz, pattern = pattern_val())
        }, error = function(e) {
          console_text(paste0("ERROR: ", e$message))
          data.table::data.table()
        })
        inspect_data(dt)
      })
    })

    # KPI stats outputs
    output$stat_total_files <- shiny::renderUI({ shiny::h3(nrow(inspect_data())) })
    output$stat_total_gb <- shiny::renderUI({
      dt <- inspect_data()
      gb <- if (nrow(dt) > 0) round(sum(dt$file_size_mb, na.rm = TRUE) / 1024, 2) else 0
      shiny::h3(gb)
    })
    output$stat_standardizable <- shiny::renderUI({
      dt <- inspect_data()
      cnt <- if (nrow(dt) > 0) sum(dt$category == "standardizable") else 0
      shiny::h3(cnt, style = "color: #81c784;")
    })
    output$stat_memos <- shiny::renderUI({
      dt <- inspect_data()
      cnt <- if (nrow(dt) > 0) sum(dt$category == "isolated_memo") else 0
      shiny::h3(cnt, style = "color: #ffb74d;")
    })
    output$stat_non_audio <- shiny::renderUI({
      dt <- inspect_data()
      cnt <- if (nrow(dt) > 0) sum(dt$category == "isolated_non_audio") else 0
      shiny::h3(cnt, style = "color: #e57373;")
    })
    output$stat_corrupt <- shiny::renderUI({
      dt <- inspect_data()
      cnt <- if (nrow(dt) > 0) sum(dt$category == "corrupt") else 0
      shiny::h3(cnt, style = "color: #ba68c8;")
    })

    # File inventory table
    output$tbl_inspect <- shiny::renderTable({
      dt <- inspect_data()
      if (nrow(dt) == 0) return(data.frame(Status = "No data loaded. Click 'Scan Raw Directory' above."))
      display_cols <- c("filename", "grid", "rel_path", "file_size_mb", "ext", "sample_rate", "channels", "duration_s", "parsed_datetime", "category")
      utils::head(dt[, display_cols, with = FALSE], 100)
    })

    # Live preview
    output$live_preview <- shiny::renderUI({
      dt <- inspect_data()
      if (nrow(dt) == 0) {
        return(shiny::p("No raw files scanned yet. Click 'Scan Raw Directory' first."))
      }

      valid_rows <- dt[category == "standardizable"]
      if (nrow(valid_rows) == 0) {
        return(shiny::p("No valid standardizable audio files found."))
      }

      sample_row <- valid_rows[1]
      base_name <- if (input$rename_strategy == "auto") sample_row$parsed_datetime else fs::path_ext_remove(sample_row$filename)
      pfx <- input$prefix
      grid_id <- sample_row$grid

      out_name <- if (nzchar(pfx)) {
        paste0(pfx, "_", base_name, ".", input$target_format)
      } else if (grepl(paste0("^", grid_id), sample_row$filename)) {
        paste0(fs::path_ext_remove(sample_row$filename), ".", input$target_format)
      } else if (grid_id != "unassigned") {
        paste0(grid_id, "_", base_name, ".", input$target_format)
      } else {
        paste0(base_name, ".", input$target_format)
      }

      shiny::tagList(
        shiny::p(shiny::strong("Sample Input File: "), sample_row$rel_path),
        shiny::p(shiny::strong("Extracted Grid/Site: "), sample_row$grid),
        shiny::p(shiny::strong("Input Specs: "), paste0(sample_row$ext, " | ", sample_row$sample_rate, " Hz | ", sample_row$channels, " ch | ", sample_row$duration_s, " s")),
        shiny::p(shiny::strong("Transformed Output Filename: "), shiny::span(out_name, style = "color: #4fc3f7; font-weight: bold;")),
        shiny::p(shiny::strong("Output Specs: "), paste0(input$target_format, " | ", input$target_hz, " Hz | ", input$channels, " ch"))
      )
    })

    # Execution Console Output
    output$log_console <- shiny::renderText({
      console_text()
    })

    # Dry Run
    shiny::observeEvent(input$btn_dry_run, {
      shiny::req(input$raw_path)
      shiny::withProgress(message = "Executing Dry-Run simulation...", value = 0.5, {
        res <- tryCatch({
          pam_standardize(
            raw_dir = input$raw_path,
            standardized_dir = input$std_path,
            isolated_dir = input$iso_path,
            dry_run = TRUE,
            prefix = input$prefix,
            target_format = input$target_format,
            target_hz = input$target_hz,
            channels = as.numeric(input$channels),
            min_duration_s = input$min_dur,
            organize_folders = input$organize_folders,
            rename_strategy = input$rename_strategy,
            isolate_non_audio = input$isolate_non_audio,
            isolate_short = input$isolate_short,
            timezone = input$tz
          )
        }, error = function(e) {
          console_text(paste0("Dry run error: ", e$message))
          NULL
        })

        if (!is.null(res)) {
          log_data(res)
          console_text(paste0("Dry-Run Simulation Complete!
Total actions planned: ", nrow(res), "
Transcodes planned: ", sum(res$action == "PLANNED_TRANSCODE"), "
Copies planned: ", sum(res$action == "PLANNED_COPY_COMPLIANT"), "
Isolations planned: ", sum(grepl("PLANNED_ISOLATE", res$action))))
        }
      })
    })

    # Run Standardization
    shiny::observeEvent(input$btn_run_std, {
      shiny::req(input$raw_path)
      shiny::withProgress(message = "Executing Live Standardization & Transcoding...", value = 0.5, {
        res <- tryCatch({
          pam_standardize(
            raw_dir = input$raw_path,
            standardized_dir = input$std_path,
            isolated_dir = input$iso_path,
            dry_run = FALSE,
            prefix = input$prefix,
            target_format = input$target_format,
            target_hz = input$target_hz,
            channels = as.numeric(input$channels),
            min_duration_s = input$min_dur,
            organize_folders = input$organize_folders,
            rename_strategy = input$rename_strategy,
            isolate_non_audio = input$isolate_non_audio,
            isolate_short = input$isolate_short,
            timezone = input$tz
          )
        }, error = function(e) {
          console_text(paste0("Standardization error: ", e$message))
          NULL
        })

        if (!is.null(res)) {
          log_data(res)
          console_text(paste0("SUCCESS: Standardization Complete!
Total files processed: ", nrow(res), "
Transcoded: ", sum(res$action == "TRANSCODED"), "
Direct copied: ", sum(res$action == "COPIED_COMPLIANT"), "
Isolations completed: ", sum(grepl("ISOLATED", res$action))))
        }
      })
    })

    # Execution Log Table
    output$tbl_log <- shiny::renderTable({
      dt <- log_data()
      if (nrow(dt) == 0) return(data.frame(Status = "No log data available. Perform Dry Run or Run Standardization."))
      utils::head(dt, 100)
    })
  }

  shiny::shinyApp(ui = ui, server = server)
}
