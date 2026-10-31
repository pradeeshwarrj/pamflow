# Stage 00 Shiny Triage & Standardization Application (Raven Compass Style)

#' Launch PAM Standardization & Data Triage Shiny App
#'
#' Interactive GUI for inspecting raw acoustic data, parsing timestamps, previewing
#' conversions, isolating non-audio/memo files, and performing standardized audio transcoding.
#'
#' @param cfg Optional configuration object from `pam_load_config()`.
#' @param raw_dir Optional path override for raw audio directory.
#' @param lang Interface language code (for example `"en"`); `NULL` chooses it as
#'   `pam_train_app()` does. Translations live in `inst/i18n/<code>.yml`.
#' @return Runs Shiny application.
#' @importFrom shiny req
#' @importFrom utils head
#' @examples
#' if (interactive()) {
#'   ex <- pam_example_project()
#'   pam_standardization_app(ex$cfg, raw_dir = ex$audio_dir)
#' }
#' @export
pam_standardization_app <- function(cfg = NULL, raw_dir = NULL, lang = NULL) {
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

  tr <- pam_i18n(lang)
  w <- pam_app_widgets(tr)
  card <- w$card; pills <- w$pills; grid <- w$grid
  path_row <- w$path_row; number <- w$number; stat <- w$stat
  pam_app_assets()

  ui <- shiny::fluidPage(
    title = tr("std_page_title"),
    pam_app_head(),
    pam_app_header(tr, "std_title"),

    shiny::tabsetPanel(
      id = "main_tabs",

      # TAB 1: INSPECT
      shiny::tabPanel(
        tr("std_tab_inspect"),
        card("raw_path", "std_lbl_raw", "std_desc_raw", path_row("raw_path", init_raw, "pick_raw")),
        grid(
          card("min_dur", "std_lbl_min_dur", "std_desc_min_dur",
               number("min_dur", pam_or(std_cfg$min_duration_s, 60), min = 1)),
          card("tz", "std_lbl_tz", "std_desc_tz",
               shiny::textInput("tz", label = NULL, value = init_tz, width = "100%"))),
        shiny::div(class = "pam-actions",
                   shiny::actionButton("btn_scan", tr("std_btn_scan"), class = "btn-primary pam-start")),
        grid(
          stat("stat_total_files", "std_stat_total"),
          stat("stat_total_gb", "std_stat_gb"),
          stat("stat_standardizable", "std_stat_audio", "ok"),
          cols = 3L),
        grid(
          stat("stat_memos", "std_stat_memos", "warn"),
          stat("stat_non_audio", "std_stat_non_audio", "bad"),
          stat("stat_corrupt", "std_stat_corrupt", "odd"),
          cols = 3L),
        shiny::tags$h5(tr("std_inventory"), class = "pam-log-title"),
        shiny::div(style = "overflow-x:auto;", shiny::tableOutput("tbl_inspect"))
      ),

      # TAB 2: CONVERT
      shiny::tabPanel(
        tr("std_tab_convert"),
        grid(
          card("std_path", "std_lbl_std_dir", "std_desc_std_dir", path_row("std_path", init_std, "pick_std")),
          card("iso_path", "std_lbl_iso_dir", "std_desc_iso_dir", path_row("iso_path", init_iso, "pick_iso"))),
        grid(
          card("prefix", "std_lbl_prefix", "std_desc_prefix",
               shiny::textInput("prefix", label = NULL, value = pam_or(std_cfg$prefix, ""), width = "100%")),
          card("target_hz", "std_lbl_hz", NULL, number("target_hz", init_target_hz, min = 1000, step = 1000))),
        grid(
          card("target_format", "std_lbl_format", NULL,
               shiny::radioButtons("target_format", label = NULL, inline = TRUE,
                                   choices = c("flac", "wav"),
                                   selected = pam_or(std_cfg$target_format, "flac")),
               kind = "group"),
          card("channels", "std_lbl_channels", NULL,
               pills("channels", c("1", "2"), c("std_ch_mono", "std_ch_stereo"),
                     as.character(pam_or(std_cfg$channels, 1))),
               kind = "group")),
        card("organize_folders", "std_lbl_organize", NULL,
             shiny::selectInput("organize_folders", label = NULL, width = "100%",
                                choices = w$choices(c("grid", "grid_date", "date", "preserve", "flat"),
                                                    c("std_org_grid", "std_org_grid_date", "std_org_date",
                                                      "std_org_preserve", "std_org_flat")),
                                selected = pam_or(std_cfg$organize_folders, "grid"))),
        grid(
          card("rename_strategy", "std_lbl_rename", NULL,
               pills("rename_strategy", c("auto", "keep"), c("std_ren_auto", "std_ren_keep"),
                     pam_or(std_cfg$rename_strategy, "auto")),
               kind = "group"),
          card("isolate", "std_lbl_isolate", NULL,
               shiny::tagList(
                 shiny::checkboxInput("isolate_non_audio", tr("std_isolate_non_audio"), value = TRUE),
                 shiny::checkboxInput("isolate_short", tr("std_isolate_short"), value = TRUE)),
               kind = "group")),
        shiny::div(
          class = "pam-card pam-preview",
          shiny::tags$span(class = "pam-card-title", tr("std_preview_title")),
          shiny::uiOutput("live_preview")),
        shiny::actionButton("btn_run_std", tr("std_btn_run"), class = "btn-primary pam-start"),
        shiny::div(class = "pam-actions", shiny::actionButton("btn_dry_run", tr("std_btn_dry"))),
        shiny::tags$h5(tr("std_console_title"), class = "pam-log-title"),
        shiny::verbatimTextOutput("log_console")
      ),

      # TAB 3: LOG
      shiny::tabPanel(
        tr("std_tab_log"),
        shiny::tags$h5(tr("std_log_title"), class = "pam-log-title"),
        shiny::div(style = "overflow-x:auto;", shiny::tableOutput("tbl_log"))
      )
    )
  )

  server <- function(input, output, session) {
    inspect_data <- shiny::reactiveVal(data.table::data.table())
    log_data <- shiny::reactiveVal(data.table::data.table())
    console_text <- shiny::reactiveVal(tr("std_console_ready"))

    # Hidden reactive for pattern from config
    pattern_val <- shiny::reactiveVal(if (nzchar(init_pattern)) init_pattern else NULL)

    # Folder buttons
    pick_into <- function(input_id, key) pam_app_pick_into(session, input, tr, input_id, key)
    shiny::observeEvent(input$pick_raw, pick_into("raw_path", "std_lbl_raw"))
    shiny::observeEvent(input$pick_std, pick_into("std_path", "std_lbl_std_dir"))
    shiny::observeEvent(input$pick_iso, pick_into("iso_path", "std_lbl_iso_dir"))

    # Scan button trigger
    shiny::observeEvent(input$btn_scan, {
      shiny::req(input$raw_path)
      if (!dir.exists(input$raw_path)) {
        console_text(tr("std_err_no_dir", input$raw_path))
        return()
      }

      shiny::withProgress(message = tr("std_progress_scan"), value = 0.5, {
        dt <- tryCatch({
          pam_inspect_raw(input$raw_path, recursive = TRUE, min_duration_s = input$min_dur, timezone = input$tz, pattern = pattern_val())
        }, error = function(e) {
          console_text(tr("std_err_generic", e$message))
          data.table::data.table()
        })
        inspect_data(dt)
      })
    })

    # Number cards
    stat_num <- function(value) shiny::div(class = "pam-stat-num", value)
    count_category <- function(category) {
      dt <- inspect_data()
      if (nrow(dt) > 0) sum(dt$category == category) else 0L
    }
    output$stat_total_files <- shiny::renderUI(stat_num(nrow(inspect_data())))
    output$stat_total_gb <- shiny::renderUI({
      dt <- inspect_data()
      stat_num(if (nrow(dt) > 0) round(sum(dt$file_size_mb, na.rm = TRUE) / 1024, 2) else 0)
    })
    output$stat_standardizable <- shiny::renderUI(stat_num(count_category("standardizable")))
    output$stat_memos <- shiny::renderUI(stat_num(count_category("isolated_memo")))
    output$stat_non_audio <- shiny::renderUI(stat_num(count_category("isolated_non_audio")))
    output$stat_corrupt <- shiny::renderUI(stat_num(count_category("corrupt")))

    # File inventory table
    output$tbl_inspect <- shiny::renderTable({
      dt <- inspect_data()
      if (nrow(dt) == 0) return(stats::setNames(data.frame(tr("std_no_data")), tr("std_status")))
      display_cols <- c("filename", "grid", "rel_path", "file_size_mb", "ext", "sample_rate", "channels", "duration_s", "parsed_datetime", "category")
      utils::head(dt[, display_cols, with = FALSE], 100)
    }, striped = TRUE, spacing = "s")

    # Live preview
    output$live_preview <- shiny::renderUI({
      dt <- inspect_data()
      if (nrow(dt) == 0) {
        return(shiny::p(tr("std_preview_none")))
      }

      valid_rows <- dt[category == "standardizable"]
      if (nrow(valid_rows) == 0) {
        return(shiny::p(tr("std_preview_no_valid")))
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
        shiny::p(shiny::strong(paste0(tr("std_preview_input"), ": ")), sample_row$rel_path),
        shiny::p(shiny::strong(paste0(tr("std_preview_grid"), ": ")), sample_row$grid),
        shiny::p(shiny::strong(paste0(tr("std_preview_in_specs"), ": ")),
                 paste0(sample_row$ext, " | ", sample_row$sample_rate, " Hz | ", sample_row$channels, " ch | ", sample_row$duration_s, " s")),
        shiny::p(shiny::strong(paste0(tr("std_preview_output"), ": ")), shiny::span(out_name, class = "pam-out")),
        shiny::p(shiny::strong(paste0(tr("std_preview_out_specs"), ": ")),
                 paste0(input$target_format, " | ", input$target_hz, " Hz | ", input$channels, " ch"))
      )
    })

    # Execution Console Output
    output$log_console <- shiny::renderText({
      console_text()
    })

    # Run standardization or its dry run (same call, different message)
    run_standardization <- function(dry_run) {
      shiny::req(input$raw_path)
      progress_key <- if (dry_run) "std_progress_dry" else "std_progress_run"
      shiny::withProgress(message = tr(progress_key), value = 0.5, {
        res <- tryCatch({
          pam_standardize(
            raw_dir = input$raw_path,
            standardized_dir = input$std_path,
            isolated_dir = input$iso_path,
            dry_run = dry_run,
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
          console_text(tr(if (dry_run) "std_err_dry" else "std_err_run", e$message))
          NULL
        })

        if (!is.null(res)) {
          log_data(res)
          console_text(if (dry_run) {
            tr("std_done_dry", nrow(res), sum(res$action == "PLANNED_TRANSCODE"),
               sum(res$action == "PLANNED_COPY_COMPLIANT"), sum(grepl("PLANNED_ISOLATE", res$action)))
          } else {
            tr("std_done_run", nrow(res), sum(res$action == "TRANSCODED"),
               sum(res$action == "COPIED_COMPLIANT"), sum(grepl("ISOLATED", res$action)))
          })
        }
      })
    }
    shiny::observeEvent(input$btn_dry_run, run_standardization(TRUE))
    shiny::observeEvent(input$btn_run_std, run_standardization(FALSE))

    # Execution Log Table
    output$tbl_log <- shiny::renderTable({
      dt <- log_data()
      if (nrow(dt) == 0) return(stats::setNames(data.frame(tr("std_no_log")), tr("std_status")))
      utils::head(dt, 100)
    }, striped = TRUE, spacing = "s")
  }

  shiny::shinyApp(ui = ui, server = server)
}
