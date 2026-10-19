#' Soundscape Analysis Functions (Stage 2b)
#'
#' Implementation of Bradfer-Lawrence et al. (2019) ecoacoustic index workflow
#' calculating 7 core acoustic indices: ACI, ADI, AEve, Bio, H, M, and NDSI.
#'
#' @name pam_soundscape
NULL

to_scalar_num <- function(x) {
  if (is.null(x)) return(NA_real_)
  if (is.list(x) || is.matrix(x) || is.data.frame(x)) return(NA_real_)
  if (length(x) != 1L) return(NA_real_)
  val <- suppressWarnings(as.numeric(x))
  if (length(val) != 1L || is.na(val) || is.nan(val)) return(NA_real_)
  val
}

#' Calculate Soundscape Indices for One Audio File
#'
#' @param file_path Character path to a WAV audio file.
#' @param low_stop_hz Numeric frequency (Hz) for highpass low-stop filter. Default 500.
#' @param anthrophony_range Numeric length-2 vector for anthrophony band (Hz). Default c(1000, 2000).
#' @param biophony_range Numeric length-2 vector for biophony band (Hz). Default c(2000, 11000).
#'
#' @return A data.table with 1 row and columns for all 7 indices (ACI, ADI, AEve, Bio, H, M, NDSI).
#' @export
pam_soundscape_one <- function(file_path,
                               low_stop_hz = 500,
                               anthrophony_range = c(1000, 2000),
                               biophony_range = c(2000, 11000)) {
  if (!requireNamespace("seewave", quietly = TRUE) ||
      !requireNamespace("soundecology", quietly = TRUE) ||
      !requireNamespace("tuneR", quietly = TRUE)) {
    rlang::abort("Packages 'seewave', 'soundecology', and 'tuneR' are required for soundscape analysis.")
  }

  empty_res <- data.table::data.table(
    file_name = basename(file_path),
    ACI = NA_real_, ADI = NA_real_, AEve = NA_real_,
    Bio = NA_real_, H = NA_real_, M = NA_real_, NDSI = NA_real_,
    status = "error"
  )

  if (!file.exists(file_path)) return(empty_res)

  wave <- tryCatch(tuneR::readWave(file_path), error = function(e) NULL)
  if (is.null(wave) || length(wave@left) == 0) return(empty_res)

  # Apply 500 Hz low-stop highpass filter if requested
  if (!is.null(low_stop_hz) && low_stop_hz > 0 && wave@samp.rate > (2 * low_stop_hz)) {
    wave <- tryCatch(
      seewave::ffilter(wave, from = low_stop_hz, output = "Wave"),
      error = function(e) wave
    )
  }

  nyquist <- floor(wave@samp.rate / 2) - 100
  b_min <- min(biophony_range[1], nyquist - 500)
  b_max <- min(biophony_range[2], nyquist)
  a_min <- min(anthrophony_range[1], b_min - 500)
  a_max <- min(anthrophony_range[2], b_min)

  # 1. ACI (Acoustic Complexity Index)
  aci <- tryCatch({
    suppressMessages(suppressWarnings(utils::capture.output(
      res <- soundecology::acoustic_complexity(wave)
    )))
    if ("Acoustic_Complexity" %in% names(res)) res$Acoustic_Complexity else res$tot_aci
  }, error = function(e) NA_real_)

  # 2. ADI (Acoustic Diversity Index)
  adi <- tryCatch({
    suppressMessages(suppressWarnings(utils::capture.output(
      res <- soundecology::acoustic_diversity(wave)
    )))
    res$Acoustic_Diversity_Value
  }, error = function(e) NA_real_)

  # 3. AEve (Acoustic Evenness Index)
  aeve <- tryCatch({
    suppressMessages(suppressWarnings(utils::capture.output(
      res <- soundecology::acoustic_evenness(wave)
    )))
    res$Acoustic_Evenness_Value
  }, error = function(e) NA_real_)

  # 4. Bio (Bioacoustic Index)
  bio <- tryCatch({
    suppressMessages(suppressWarnings(utils::capture.output(
      res <- soundecology::bioacoustic_index(wave, min_freq = b_min, max_freq = b_max)
    )))
    res$Left_Bioacc
  }, error = function(e) NA_real_)

  # 5. H (Acoustic Entropy)
  h_val <- tryCatch({
    seewave::H(wave)
  }, error = function(e) NA_real_)

  # 6. M (Median envelope amplitude)
  m_val <- tryCatch({
    seewave::M(wave)
  }, error = function(e) NA_real_)

  # 7. NDSI (Normalized Difference Soundscape Index)
  ndsi_val <- tryCatch({
    suppressMessages(suppressWarnings(utils::capture.output(
      res <- soundecology::ndsi(
        wave,
        anthro_min = a_min, anthro_max = a_max,
        bio_min = b_min, bio_max = b_max
      )
    )))
    res$ndsi_left
  }, error = function(e) NA_real_)

  data.table::data.table(
    file_name = basename(file_path),
    ACI = to_scalar_num(aci),
    ADI = to_scalar_num(adi),
    AEve = to_scalar_num(aeve),
    Bio = to_scalar_num(bio),
    H = to_scalar_num(h_val),
    M = to_scalar_num(m_val),
    NDSI = to_scalar_num(ndsi_val),
    status = "ok"
  )
}

#' Calculate Soundscape Indices Across Audio Files
#'
#' @param cfg Config list or path to YAML config file.
#' @return data.table of raw soundscape results for all files.
#' @export
pam_soundscape_batch <- function(cfg) {
  if (is.character(cfg)) cfg <- pam_config_read(cfg)
  stage <- "02b_soundscape"
  log_dir <- cfg$paths$logs
  run_id <- pam_or(cfg$run_id, pam_or(cfg$birdnet$run_id, "run01"))

  sc_cfg <- cfg$soundscape
  low_stop <- pam_or(sc_cfg$low_stop_hz, 500)
  anthro <- pam_or(sc_cfg$anthrophony_range, c(1000, 2000))
  bio <- pam_or(sc_cfg$biophony_range, c(2000, 11000))

  root <- cfg$paths$project_root
  out_dir <- file.path(root, "data", "soundscape", run_id)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  raw_path <- file.path(out_dir, "soundscape_raw.csv")

  master_path <- file.path(root, "data", "master_table.csv")
  if (!file.exists(master_path)) {
    rlang::abort(sprintf("Master table not found at: %s", master_path))
  }
  master <- data.table::fread(master_path)
  valid_files <- master[qc_pass == TRUE & in_deployment == TRUE, file_path]

  if (file.exists(raw_path)) {
    existing <- data.table::fread(raw_path)
    done_files <- existing$file_name
  } else {
    existing <- data.table::data.table()
    done_files <- character()
  }

  pending <- valid_files[!basename(valid_files) %in% done_files]

  pam_log("INFO", sprintf("Processing soundscapes for %d files (%d already done)",
                          length(pending), length(done_files)), stage, log_dir)

  if (length(pending) == 0L) {
    return(existing)
  }

  new_results <- vector("list", length(pending))
  for (i in seq_along(pending)) {
    f <- pending[i]
    new_results[[i]] <- pam_soundscape_one(
      file_path = f,
      low_stop_hz = low_stop,
      anthrophony_range = anthro,
      biophony_range = bio
    )
    if (i %% 50 == 0 || i == length(pending)) {
      pam_log("INFO", sprintf("Soundscapes: %d/%d processed", i, length(pending)), stage, log_dir)
    }
  }

  res_dt <- data.table::rbindlist(new_results, fill = TRUE)
  combined <- data.table::rbindlist(list(existing, res_dt), fill = TRUE)

  pam_fwrite_local(combined, raw_path)
  combined
}

#' Summarise Soundscape Indices by Hour and Diel Phase
#'
#' @param cfg Config list or path to YAML config file.
#' @param raw_dt Optional data.table of raw soundscape results. If NULL, loaded from disk.
#' @return List of data.tables containing hourly and diel site-level summaries.
#' @export
pam_soundscape_summarise <- function(cfg, raw_dt = NULL) {
  if (is.character(cfg)) cfg <- pam_config_read(cfg)
  run_id <- pam_or(cfg$run_id, pam_or(cfg$birdnet$run_id, "run01"))
  sc_cfg <- cfg$soundscape

  root <- cfg$paths$project_root
  out_dir <- file.path(root, "data", "soundscape", run_id)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (is.null(raw_dt)) {
    raw_path <- file.path(out_dir, "soundscape_raw.csv")
    if (!file.exists(raw_path)) {
      rlang::abort(sprintf("Raw soundscape file not found at: %s", raw_path))
    }
    raw_dt <- data.table::fread(raw_path)
  }

  master_path <- file.path(root, "data", "master_table.csv")
  if (!file.exists(master_path)) {
    rlang::abort(sprintf("Master table not found at: %s", master_path))
  }
  master <- data.table::fread(master_path)

  # Join master info
  dt <- merge(
    raw_dt[status == "ok"],
    master[, .(file_name, grid, recording_start)],
    by = "file_name",
    all.x = TRUE
  )

  dt[, recording_start := as.POSIXct(recording_start, tz = pam_or(cfg$occupancy$timezone, "UTC"))]
  dt[, hour := data.table::hour(recording_start)]

  day_start <- pam_or(sc_cfg$day_hours[1], 6)
  day_end <- pam_or(sc_cfg$day_hours[2], 17)

  dt[, diel_phase := data.table::fifelse(hour >= day_start & hour <= day_end, "Day", "Night")]

  # 1. Hourly Summary
  hourly <- dt[!is.na(hour), .(
    n_files = .N,
    ACI_mean = mean(ACI, na.rm = TRUE), ACI_sd = stats::sd(ACI, na.rm = TRUE),
    ADI_mean = mean(ADI, na.rm = TRUE), ADI_sd = stats::sd(ADI, na.rm = TRUE),
    AEve_mean = mean(AEve, na.rm = TRUE), AEve_sd = stats::sd(AEve, na.rm = TRUE),
    Bio_mean = mean(Bio, na.rm = TRUE), Bio_sd = stats::sd(Bio, na.rm = TRUE),
    H_mean = mean(H, na.rm = TRUE), H_sd = stats::sd(H, na.rm = TRUE),
    M_mean = mean(M, na.rm = TRUE), M_sd = stats::sd(M, na.rm = TRUE),
    NDSI_mean = mean(NDSI, na.rm = TRUE), NDSI_sd = stats::sd(NDSI, na.rm = TRUE)
  ), by = .(grid, hour)]
  data.table::setorder(hourly, grid, hour)

  # 2. Diel Summary (Long)
  diel_long <- dt[!is.na(diel_phase), .(
    n_files = .N,
    ACI_mean = mean(ACI, na.rm = TRUE), ACI_sd = stats::sd(ACI, na.rm = TRUE),
    ADI_mean = mean(ADI, na.rm = TRUE), ADI_sd = stats::sd(ADI, na.rm = TRUE),
    AEve_mean = mean(AEve, na.rm = TRUE), AEve_sd = stats::sd(AEve, na.rm = TRUE),
    Bio_mean = mean(Bio, na.rm = TRUE), Bio_sd = stats::sd(Bio, na.rm = TRUE),
    H_mean = mean(H, na.rm = TRUE), H_sd = stats::sd(H, na.rm = TRUE),
    M_mean = mean(M, na.rm = TRUE), M_sd = stats::sd(M, na.rm = TRUE),
    NDSI_mean = mean(NDSI, na.rm = TRUE), NDSI_sd = stats::sd(NDSI, na.rm = TRUE)
  ), by = .(grid, diel_phase)]
  data.table::setorder(diel_long, grid, diel_phase)

  # 3. Diel Summary (Wide for Stage 6 site covariates)
  diel_melt <- data.table::melt(
    diel_long,
    id.vars = c("grid", "diel_phase", "n_files"),
    variable.name = "metric",
    value.name = "value"
  )
  diel_melt[, feature := paste(metric, diel_phase, sep = "_")]
  diel_wide <- data.table::dcast(diel_melt, grid ~ feature, value.var = "value")

  pam_fwrite_local(hourly, file.path(out_dir, "soundscape_hourly.csv"))
  pam_fwrite_local(diel_long, file.path(out_dir, "soundscape_diel_summary.csv"))
  pam_fwrite_local(diel_wide, file.path(out_dir, "soundscape_site_covariates.csv"))

  list(hourly = hourly, diel_summary = diel_long, site_covariates = diel_wide)
}

#' Master Soundscape Pipeline Stage (Stage 2b)
#'
#' @param cfg Config list or path to YAML config file.
#' @return List with raw, hourly, and site summary data.tables.
#' @export
pam_soundscape_run <- function(cfg) {
  if (is.character(cfg)) cfg <- pam_config_read(cfg)
  stage <- "02b_soundscape"
  log_dir <- cfg$paths$logs

  if (isFALSE(cfg$soundscape$enabled)) {
    pam_log("INFO", "Soundscape analysis disabled in config; skipping Stage 2b", stage, log_dir)
    return(NULL)
  }

  pam_log("INFO", "Starting Stage 2b soundscape analysis...", stage, log_dir)
  raw_dt <- pam_soundscape_batch(cfg)
  sums <- pam_soundscape_summarise(cfg, raw_dt = raw_dt)
  pam_log("INFO", "Stage 2b soundscape analysis complete.", stage, log_dir)

  c(list(raw = raw_dt), sums)
}
