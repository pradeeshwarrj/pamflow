# Stage 00: Raw Audio Data Standardization and Triage Engine

#' Extract Grid, Recorder, or Site Identifier from Filename
#'
#' Helper function to parse site/grid/recorder identifier from filename using
#' pattern capture groups or leading token prior to first underscore.
#'
#' @param filename Character, filename or base name.
#' @param pattern Optional regular expression pattern (e.g., cfg$filenames$pattern).
#' @return Character string identifier or "unassigned".
#' @examples
#' pam_extract_grid("G0059_20260405_183000.wav")
#' pam_extract_grid("recording.wav")   # no recognisable identifier
#' @export
pam_extract_grid <- function(filename, pattern = NULL) {
  base_name <- basename(filename)

  # 1. Custom pattern check with named capture group extraction
  if (!is.null(pattern) && nzchar(pattern)) {
    m <- regexpr(pattern, base_name, perl = TRUE)
    if (m != -1) {
      st <- attr(m, "capture.start")
      len <- attr(m, "capture.length")
      nms <- attr(m, "capture.names")
      if (!is.null(nms)) {
        target_col <- intersect(c("grid", "recorder", "site", "deployment"), nms)
        if (length(target_col) > 0) {
          idx <- which(nms == target_col[1])
          if (st[idx] > 0) {
            return(substr(base_name, st[idx], st[idx] + len[idx] - 1))
          }
        }
      }
    }
  }

  # 2. Match leading alphanumeric/hyphen token before first underscore
  m2 <- regmatches(base_name, regexpr("^[A-Za-z0-9\\-]+(?=_)", base_name, perl = TRUE))
  if (length(m2) > 0 && nchar(m2[1]) > 0) return(m2[1])

  "unassigned"
}

#' Parse Datetime from Audio Filename or Metadata
#'
#' Automatically detects and extracts recording timestamp from filename (ISO formats,
#' 14-digit, 12-digit) or falls back to file modification time.
#' Timestamps are returned as local time strings.
#'
#' @param filename Character, filename or base name.
#' @param file_path Optional character path to file for metadata fallback.
#' @param timezone Character string timezone (e.g. "Asia/Kolkata").
#' @return Character string timestamp in "YYYYMMDD_HHMMSS" format.
#' @examples
#' pam_parse_datetime("G0059_20260405_183000.wav")
#' pam_parse_datetime("SM4_260405183000.wav")   # 12-digit stamp: yymmddhhmmss
#' @export
pam_parse_datetime <- function(filename, file_path = NULL, timezone = "Asia/Kolkata") {
  base_name <- basename(filename)
  base_no_ext <- fs::path_ext_remove(base_name)

  # 1. Standard YYYYMMDD_HHMMSS / YYYYMMDD-HHMMSS / YYYYMMDDTHHMMSS
  m1 <- regmatches(base_no_ext, regexpr("20[0-9]{2}[01][0-9][0-3][0-9][-_T][0-2][0-9][0-5][0-9][0-5][0-9]", base_no_ext, perl = TRUE))
  if (length(m1) > 0 && nchar(m1[1]) > 0) {
    clean <- gsub("[^0-9]", "", m1[1])
    if (nchar(clean) == 14) {
      return(paste0(substr(clean, 1, 8), "_", substr(clean, 9, 14)))
    }
  }

  # 2. 14 consecutive digits YYYYMMDDHHMMSS
  m2 <- regmatches(base_no_ext, regexpr("20[0-9]{2}[01][0-9][0-3][0-9][0-2][0-9][0-5][0-9][0-5][0-9]", base_no_ext, perl = TRUE))
  if (length(m2) > 0 && nchar(m2[1]) > 0) {
    clean <- m2[1]
    return(paste0(substr(clean, 1, 8), "_", substr(clean, 9, 14)))
  }

  # 3. 12 consecutive digits YYMMDDHHMMSS
  m3 <- regmatches(base_no_ext, regexpr("[2-3][0-9][01][0-9][0-3][0-9][0-2][0-9][0-5][0-9][0-5][0-9]", base_no_ext, perl = TRUE))
  if (length(m3) > 0 && nchar(m3[1]) > 0) {
    clean <- m3[1]
    return(paste0("20", substr(clean, 1, 6), "_", substr(clean, 7, 12)))
  }

  # 4. Fallback to file modification time
  if (!is.null(file_path) && file.exists(file_path)) {
    fi <- file.info(file_path)
    if (!is.na(fi$mtime)) {
      return(format(fi$mtime, "%Y%m%d_%H%M%S"))
    }
  }

  # Ultimate fallback
  format(Sys.time(), "%Y%m%d_%H%M%S")
}

#' Inspect Raw Audio Directory
#'
#' Recursively scans a raw data directory, classifies files (audio, short clips/memos,
#' non-audio, corrupt), extracts audio properties, and parses recording datetimes.
#'
#' @param raw_dir Path to raw data folder.
#' @param recursive Logical, scan subfolders recursively?
#' @param min_duration_s Minimum duration in seconds for standard audio clips (default 60s).
#' @param timezone Timezone string for timestamp parsing.
#' @param pattern Optional filename regex pattern.
#' @return data.table containing detailed file metadata and triage categorization.
#' @examples
#' ex <- pam_example_project()
#' # the example audio stands in for a raw dump; recordings under 1 s would count as memos
#' insp <- suppressMessages(pam_inspect_raw(ex$audio_dir, min_duration_s = 1))
#' as.data.frame(insp)[, c("filename", "duration_s", "grid", "category")]
#' @export
pam_inspect_raw <- function(raw_dir, recursive = TRUE, min_duration_s = 60, timezone = "Asia/Kolkata", pattern = NULL) {
  if (!dir.exists(raw_dir)) {
    pam_log("ERROR", as.character(glue::glue("Raw directory does not exist: {raw_dir}")), stage = "00_standardization")
    stop("Raw directory does not exist: ", raw_dir)
  }

  pam_log("INFO", as.character(glue::glue("Scanning raw directory: {raw_dir} (recursive = {recursive})")), stage = "00_standardization")
  all_files <- as.character(fs::dir_ls(raw_dir, recurse = recursive, type = "file"))

  if (length(all_files) == 0) {
    pam_log("WARN", as.character(glue::glue("No files found in raw directory: {raw_dir}")), stage = "00_standardization")
    return(data.table::data.table(
      file_path = character(0),
      rel_path = character(0),
      filename = character(0),
      file_size_mb = numeric(0),
      is_audio = logical(0),
      ext = character(0),
      sample_rate = integer(0),
      channels = integer(0),
      duration_s = numeric(0),
      parsed_datetime = character(0),
      grid = character(0),
      category = character(0),
      status_msg = character(0)
    ))
  }

  known_audio_exts <- c("wav", "flac", "mp3", "m4a", "ogg", "wma", "aiff", "aif")

  res_list <- lapply(all_files, function(fp) {
    rel_path <- as.character(fs::path_rel(fp, start = raw_dir))
    fn <- basename(fp)
    ext <- tolower(fs::path_ext(fp))
    sz_mb <- round(as.numeric(fs::file_size(fp)) / (1024 * 1024), 3)
    grid_id <- pam_extract_grid(fn, pattern = pattern)

    is_audio_ext <- ext %in% known_audio_exts

    if (!is_audio_ext) {
      dt_str <- pam_parse_datetime(fn, file_path = fp, timezone = timezone)
      return(data.table::data.table(
        file_path = fp,
        rel_path = rel_path,
        filename = fn,
        file_size_mb = sz_mb,
        is_audio = FALSE,
        ext = ext,
        sample_rate = NA_integer_,
        channels = NA_integer_,
        duration_s = NA_real_,
        parsed_datetime = dt_str,
        grid = grid_id,
        category = "isolated_non_audio",
        status_msg = "Non-audio file isolated"
      ))
    }

    # Audio file inspection
    info <- pam_audio_info(fp)

    if (is.na(info$readable[1]) || !info$readable[1]) {
      dt_str <- pam_parse_datetime(fn, file_path = fp, timezone = timezone)
      return(data.table::data.table(
        file_path = fp,
        rel_path = rel_path,
        filename = fn,
        file_size_mb = sz_mb,
        is_audio = TRUE,
        ext = ext,
        sample_rate = NA_integer_,
        channels = NA_integer_,
        duration_s = NA_real_,
        parsed_datetime = dt_str,
        grid = grid_id,
        category = "corrupt",
        status_msg = "Unreadable audio stream"
      ))
    }

    dur <- info$duration_s[1]
    sr <- info$sample_rate[1]
    ch <- info$channels[1]
    dt_str <- pam_parse_datetime(fn, file_path = fp, timezone = timezone)

    cat_type <- if (!is.na(dur) && dur < min_duration_s) "isolated_memo" else "standardizable"
    status <- if (cat_type == "isolated_memo") "Short audio memo (< min_duration)" else "Valid audio recording"

    data.table::data.table(
      file_path = fp,
      rel_path = rel_path,
      filename = fn,
      file_size_mb = sz_mb,
      is_audio = TRUE,
      ext = ext,
      sample_rate = as.integer(sr),
      channels = as.integer(ch),
      duration_s = as.numeric(dur),
      parsed_datetime = dt_str,
      grid = grid_id,
      category = cat_type,
      status_msg = status
    )
  })

  inspect_dt <- data.table::rbindlist(res_list, use.names = TRUE, fill = TRUE, ignore.attr = TRUE)
  pam_log("INFO", as.character(glue::glue("Inspection complete. Total files: {nrow(inspect_dt)} | Standardizable: {sum(inspect_dt$category == 'standardizable')} | Non-audio: {sum(inspect_dt$category == 'isolated_non_audio')} | Memos: {sum(inspect_dt$category == 'isolated_memo')}")), stage = "00_standardization")
  inspect_dt
}

#' Standardize Raw PAM Audio Files (Stage 00 Engine)
#'
#' Standardizes raw audio datasets by organizing folders, parsing timestamps, converting formats
#' (WAV/FLAC), resampling, mixing channels to mono, isolating non-audio/memos, and logging results.
#'
#' @param cfg Optional configuration object from `pam_load_config()`.
#' @param raw_dir Directory containing raw audio files.
#' @param standardized_dir Directory to save standardized audio.
#' @param isolated_dir Directory to save isolated non-audio and memo files.
#' @param dry_run Logical, if TRUE simulates actions without modifying disk.
#' @param prefix Prefix string prepended to standardized filenames.
#' @param target_format Output format: "flac" or "wav".
#' @param target_hz Target sample rate (Hz). If NULL or higher than input, original rate is kept.
#' @param channels Target audio channels (1 = mono, 2 = stereo).
#' @param min_duration_s Minimum duration threshold for valid recordings (default 60s).
#' @param organize_folders Subfolder structure: "grid" (G0059/), "date" (YYYY/MM/DD), "grid_date" (G0059/YYYY/MM/DD), "preserve", or "flat".
#' @param rename_strategy Naming strategy: "auto" (uses extracted datetime) or "keep".
#' @param isolate_non_audio Logical, isolate non-audio files?
#' @param isolate_short Logical, isolate short audio clips?
#' @param timezone Timezone string (default "Asia/Kolkata").
#' @return data.table containing audit log of standardization operations.
#' @examples
#' ex <- pam_example_project()
#' demo <- tempfile("pamflow_std_")
#'
#' # dry_run = TRUE only plans what would happen; nothing is written
#' plan <- suppressMessages(pam_standardize(
#'   ex$cfg, raw_dir = ex$audio_dir, standardized_dir = file.path(demo, "standardized"),
#'   isolated_dir = file.path(demo, "isolated"), dry_run = TRUE,
#'   target_format = "wav", min_duration_s = 1))
#' table(plan$action)
#'
#' \donttest{
#' if (requireNamespace("av", quietly = TRUE)) {
#'   # convert for real: the example WAV files become FLAC
#'   done <- suppressMessages(pam_standardize(
#'     ex$cfg, raw_dir = ex$audio_dir, standardized_dir = file.path(demo, "standardized"),
#'     isolated_dir = file.path(demo, "isolated"), target_format = "flac", min_duration_s = 1))
#'   table(done$action)
#' }
#' }
#' unlink(demo, recursive = TRUE)
#' @export
pam_standardize <- function(cfg = NULL,
                            raw_dir = NULL,
                            standardized_dir = NULL,
                            isolated_dir = NULL,
                            dry_run = NULL,
                            prefix = NULL,
                            target_format = NULL,
                            target_hz = NULL,
                            channels = NULL,
                            min_duration_s = NULL,
                            organize_folders = NULL,
                            rename_strategy = NULL,
                            isolate_non_audio = NULL,
                            isolate_short = NULL,
                            timezone = NULL) {

  if (is.null(cfg)) {
    cfg <- tryCatch(pam_load_config(), error = function(e) list())
  }

  paths_cfg <- pam_or(cfg$paths, list())
  dir_cfg <- pam_or(cfg$directories, list())
  std_cfg <- pam_or(cfg$standardization, list())
  audio_cfg <- pam_or(cfg$audio, list())
  fn_cfg <- pam_or(cfg$filenames, list())

  # Path resolutions (supports both cfg$paths and cfg$directories)
  raw_dir <- pam_or(raw_dir, pam_or(paths_cfg$audio_raw, pam_or(dir_cfg$raw, pam_or(dir_cfg$input, "data/raw"))))
  standardized_dir <- pam_or(standardized_dir, pam_or(paths_cfg$audio_standardized, pam_or(dir_cfg$standardized, "data/standardized")))
  isolated_dir <- pam_or(isolated_dir, pam_or(paths_cfg$audio_isolated, pam_or(dir_cfg$isolated, "data/isolated")))

  # Parameter resolutions
  dry_run <- pam_or(dry_run, pam_or(std_cfg$dry_run, FALSE))
  prefix <- pam_or(prefix, pam_or(std_cfg$prefix, ""))
  target_format <- tolower(pam_or(target_format, pam_or(std_cfg$target_format, "flac")))
  target_hz <- pam_or(target_hz, pam_or(std_cfg$target_hz, pam_or(audio_cfg$sample_rate, 48000)))
  channels <- pam_or(channels, pam_or(std_cfg$channels, 1))
  min_duration_s <- pam_or(min_duration_s, pam_or(std_cfg$min_duration_s, 60))
  organize_folders <- pam_or(organize_folders, pam_or(std_cfg$organize_folders, "grid"))
  rename_strategy <- pam_or(rename_strategy, pam_or(std_cfg$rename_strategy, "auto"))
  isolate_non_audio <- pam_or(isolate_non_audio, pam_or(std_cfg$isolate_non_audio, TRUE))
  isolate_short <- pam_or(isolate_short, pam_or(std_cfg$isolate_short, TRUE))
  timezone <- pam_or(timezone, pam_or(std_cfg$timezone, pam_or(fn_cfg$timezone, "Asia/Kolkata")))
  fn_pattern <- pam_or(fn_cfg$pattern, NULL)

  pam_log("INFO", as.character(glue::glue("Starting Stage 00 Standardization (dry_run = {dry_run})")), stage = "00_standardization")
  pam_log("INFO", as.character(glue::glue("Target format: {target_format} | Target Hz: {target_hz} | Layout: {organize_folders} | Timezone: {timezone}")), stage = "00_standardization")

  inspect_dt <- pam_inspect_raw(raw_dir, recursive = TRUE, min_duration_s = min_duration_s, timezone = timezone, pattern = fn_pattern)

  if (nrow(inspect_dt) == 0) {
    pam_log("WARN", "No files to process.", stage = "00_standardization")
    return(inspect_dt)
  }

  log_records <- list()

  for (i in seq_len(nrow(inspect_dt))) {
    row <- inspect_dt[i]
    src_path <- row$file_path
    rel_path <- row$rel_path
    category <- row$category
    ext <- row$ext
    src_hz <- row$sample_rate
    src_ch <- row$channels
    grid_id <- row$grid

    # 1. Isolate Non-Audio Files
    if (category == "isolated_non_audio") {
      if (isolate_non_audio) {
        dest_path <- file.path(isolated_dir, "non_audio", rel_path)
        action <- if (dry_run) "PLANNED_ISOLATE_NON_AUDIO" else "ISOLATED_NON_AUDIO"
        if (!dry_run) {
          fs::dir_create(dirname(dest_path))
          fs::file_copy(src_path, dest_path, overwrite = TRUE)
        }
        log_records[[i]] <- data.table::data.table(
          source_path = src_path,
          dest_path = dest_path,
          category = category,
          action = action,
          status = "SUCCESS",
          message = "Non-audio file moved to isolated directory"
        )
      } else {
        log_records[[i]] <- data.table::data.table(
          source_path = src_path,
          dest_path = NA_character_,
          category = category,
          action = "SKIPPED",
          status = "SUCCESS",
          message = "Non-audio file retained in raw"
        )
      }
      next
    }

    # 2. Isolate Short Audio Files (Voice Memos)
    if (category == "isolated_memo") {
      if (isolate_short) {
        dest_path <- file.path(isolated_dir, "memos", rel_path)
        action <- if (dry_run) "PLANNED_ISOLATE_MEMO" else "ISOLATED_MEMO"
        if (!dry_run) {
          fs::dir_create(dirname(dest_path))
          fs::file_copy(src_path, dest_path, overwrite = TRUE)
        }
        log_records[[i]] <- data.table::data.table(
          source_path = src_path,
          dest_path = dest_path,
          category = category,
          action = action,
          status = "SUCCESS",
          message = "Short audio memo moved to isolated directory"
        )
      } else {
        log_records[[i]] <- data.table::data.table(
          source_path = src_path,
          dest_path = NA_character_,
          category = category,
          action = "SKIPPED",
          status = "SUCCESS",
          message = "Short audio memo retained in raw"
        )
      }
      next
    }

    # 3. Handle Corrupt Files
    if (category == "corrupt") {
      dest_path <- file.path(isolated_dir, "corrupt", rel_path)
      action <- if (dry_run) "PLANNED_ISOLATE_CORRUPT" else "ISOLATED_CORRUPT"
      if (!dry_run) {
        fs::dir_create(dirname(dest_path))
        fs::file_copy(src_path, dest_path, overwrite = TRUE)
      }
      log_records[[i]] <- data.table::data.table(
        source_path = src_path,
        dest_path = dest_path,
        category = category,
        action = action,
        status = "WARN",
        message = "Corrupt/unreadable audio stream isolated"
      )
      next
    }

    # 4. Standardizable Audio Recording
    base_name <- if (rename_strategy == "auto") row$parsed_datetime else fs::path_ext_remove(row$filename)

    # Check if original filename already had grid identifier
    final_filename <- if (nzchar(prefix)) {
      paste0(prefix, "_", base_name, ".", target_format)
    } else if (grepl(paste0("^", grid_id), row$filename)) {
      paste0(fs::path_ext_remove(row$filename), ".", target_format)
    } else if (grid_id != "unassigned") {
      paste0(grid_id, "_", base_name, ".", target_format)
    } else {
      paste0(base_name, ".", target_format)
    }

    # Subfolder layout
    if (organize_folders == "grid") {
      dest_dir <- file.path(standardized_dir, grid_id)
    } else if (organize_folders == "grid_date") {
      yyyy <- substr(row$parsed_datetime, 1, 4)
      mm <- substr(row$parsed_datetime, 5, 6)
      dd <- substr(row$parsed_datetime, 7, 8)
      dest_dir <- file.path(standardized_dir, grid_id, yyyy, mm, dd)
    } else if (organize_folders == "date") {
      yyyy <- substr(row$parsed_datetime, 1, 4)
      mm <- substr(row$parsed_datetime, 5, 6)
      dd <- substr(row$parsed_datetime, 7, 8)
      dest_dir <- file.path(standardized_dir, yyyy, mm, dd)
    } else if (organize_folders == "preserve") {
      dest_dir <- file.path(standardized_dir, dirname(rel_path))
    } else {
      # "flat"
      dest_dir <- standardized_dir
    }

    dest_path <- file.path(dest_dir, final_filename)

    # Calculate actual output sample rate (avoid upsampling)
    actual_target_hz <- if (is.null(target_hz) || is.na(src_hz) || target_hz >= src_hz) src_hz else target_hz

    # Smart check: if source is already target format, rate, and channels
    is_already_compliant <- (ext == target_format) &&
      (is.na(src_hz) || is.null(target_hz) || src_hz == actual_target_hz) &&
      (is.na(src_ch) || is.null(channels) || src_ch == channels)

    if (is_already_compliant) {
      action <- if (dry_run) "PLANNED_COPY_COMPLIANT" else "COPIED_COMPLIANT"
      if (!dry_run) {
        fs::dir_create(dest_dir)
        fs::file_copy(src_path, dest_path, overwrite = TRUE)
      }
      log_records[[i]] <- data.table::data.table(
        source_path = src_path,
        dest_path = dest_path,
        category = category,
        action = action,
        status = "SUCCESS",
        message = "Compliant file copied directly without re-encoding"
      )
    } else {
      action <- if (dry_run) "PLANNED_TRANSCODE" else "TRANSCODED"
      if (!dry_run) {
        fs::dir_create(dest_dir)
        res <- tryCatch({
          av::av_audio_convert(
            audio = src_path,
            output = dest_path,
            sample_rate = actual_target_hz,
            channels = channels,
            verbose = FALSE
          )
          TRUE
        }, error = function(e) {
          pam_log("ERROR", as.character(glue::glue("Failed to convert {src_path}: {e$message}")), stage = "00_standardization")
          FALSE
        })

        if (!res) {
          log_records[[i]] <- data.table::data.table(
            source_path = src_path,
            dest_path = dest_path,
            category = category,
            action = "FAILED_TRANSCODE",
            status = "ERROR",
            message = "FFmpeg audio conversion failed"
          )
          next
        }
      }

      log_records[[i]] <- data.table::data.table(
        source_path = src_path,
        dest_path = dest_path,
        category = category,
        action = action,
        status = "SUCCESS",
        message = as.character(glue::glue("Transcoded to {target_format} ({actual_target_hz} Hz, {channels} ch)"))
      )
    }
  }

  log_dt <- data.table::rbindlist(log_records, use.names = TRUE, fill = TRUE, ignore.attr = TRUE)

  # Write Audit Log
  if (!dry_run) {
    fs::dir_create(standardized_dir)
    log_file <- file.path(standardized_dir, "standardization_log.csv")
    data.table::fwrite(log_dt, log_file)
    pam_log("INFO", as.character(glue::glue("Standardization complete. Log saved to: {log_file}")), stage = "00_standardization")
  } else {
    pam_log("INFO", "Dry-run simulation complete. No files were modified.", stage = "00_standardization")
  }

  invisible(log_dt)
}
