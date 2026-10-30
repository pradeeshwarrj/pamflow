#' Create a small example project to try pamflow on
#'
#' Builds a tiny, synthetic pamflow project in a temporary folder: six two-second
#' WAV files (pure tones, 8 kHz, mono) from two recording grids with
#' pamflow-style file names, a deployment sheet, a configuration file, and a
#' BirdNET-style detections file for three species. It is
#' meant for the examples in the help pages, for tests, and for getting to know
#' the workflow without any field data. It needs only R packages that pamflow
#' already depends on: no FFmpeg, Python or internet connection.
#'
#' @param dir Folder to create the project in. The default is a new folder inside
#'   [tempdir()], which R removes when the session ends. If the folder exists it
#'   must be empty.
#' @return A list with:
#'   \describe{
#'     \item{`root`}{The project folder.}
#'     \item{`config`}{Path to `config/config.yml`.}
#'     \item{`cfg`}{The configuration, read with [pam_config_read()].}
#'     \item{`audio_dir`}{Folder with the standardized audio.}
#'     \item{`files`}{Paths of the six WAV files.}
#'     \item{`deployments`}{Path to the deployment sheet.}
#'     \item{`detections`}{Path to the detections batch file.}
#'   }
#' @details The project has this layout (the other folders are created when
#'   stages run):
#'   \preformatted{
#'   <root>/
#'     config/config.yml
#'     metadata/deployments.csv
#'     data/standardized/G0059/ (3 files)
#'     data/standardized/G0110/ (3 files)
#'     data/detections/run01/batches/batch_001.csv
#'   }
#'   Grid `G0059` was recorded on 2026-04-05 at 18:30 and grid `G0110` on
#'   2026-04-06 at 06:00; every file lies inside its deployment window, so a scan
#'   finds no problems.
#'
#'   The detections file looks like the batch files that [pam_detect()] writes
#'   (three species, 3-second windows). It has a few things for the cleaning
#'   stage to deal with: overlapping windows to merge, low-confidence rows, a
#'   window past the end of its recording, and one duplicated row. The stages
#'   after the scan need the master table, so run [pam_scan_audio()] on
#'   `ex$cfg` first; the help-page examples show how.
#'
#'   The configuration only sets what differs from the defaults: occupancy
#'   needs no minimum recording effort and one detection per species, recall
#'   segments are 1 second long because the recordings are only 2 seconds
#'   long, and the filter stage uses a single worker.
#' @examples
#' ex <- pam_example_project()
#' basename(ex$files)
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' res$summary$overall
#' @export
pam_example_project <- function(dir = tempfile("pamflow_example_")) {
  if (!is.character(dir) || length(dir) != 1L || is.na(dir) || !nzchar(dir)) {
    rlang::abort("`dir` must be a single folder path")
  }
  if (dir.exists(dir) && length(list.files(dir, all.files = TRUE, no.. = TRUE))) {
    rlang::abort(sprintf("Folder is not empty: %s", dir))
  }
  # create the folder first, then resolve it: symbolic links (macOS /var) and short
  # Windows names (RUNNER~1) only resolve once the folder exists, and every path below
  # must be spelled the way pam_config_read() will spell it
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  root <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  audio_dir <- file.path(root, "data", "standardized")
  dir.create(file.path(root, "metadata"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "config"), recursive = TRUE, showWarnings = FALSE)

  # six short tones: three files per grid, one right after the other
  recordings <- data.frame(
    grid = rep(c("G0059", "G0110"), each = 3L),
    stamp = c("20260405_183000", "20260405_183002", "20260405_183004",
              "20260406_060000", "20260406_060002", "20260406_060004"),
    freq = c(440, 550, 660, 330, 440, 880),
    stringsAsFactors = FALSE)
  sample_rate <- 8000L
  seconds <- 2L
  index <- seq_len(sample_rate * seconds) - 1L
  files <- character(nrow(recordings))
  for (i in seq_len(nrow(recordings))) {
    grid_dir <- file.path(audio_dir, recordings$grid[i])
    dir.create(grid_dir, recursive = TRUE, showWarnings = FALSE)
    tone <- round(10000 * sin(2 * pi * recordings$freq[i] * index / sample_rate))
    wave <- tuneR::Wave(left = as.integer(tone), samp.rate = sample_rate, bit = 16)
    files[i] <- file.path(grid_dir, sprintf("%s_%s.wav", recordings$grid[i], recordings$stamp[i]))
    tuneR::writeWave(wave, files[i])
  }

  # deployment sheet: columns are read by position; the grid is a number
  deployments <- file.path(root, "metadata", "deployments.csv")
  writeLines(c(
    paste("deployment_id", "recorder", "grid", "habitat", "deployer", "latitude", "longitude",
          "deploy_date", "deploy_time", "retrieve_date", "retrieve_time", sep = ","),
    "1,SW010,59,Forest,Asha,7.01,93.82,05-04-2026,18:00,08-04-2026,16:00",
    "2,SW012,110,Plantation,Ravi,7.05,93.85,01-04-2026,06:00,10-04-2026,18:00"),
    deployments)

  # BirdNET-style detections, as the batch files of Stage 3 look
  batch_dir <- file.path(root, "data", "detections", "run01", "batches")
  dir.create(batch_dir, recursive = TRUE, showWarnings = FALSE)
  rel <- file.path(recordings$grid, basename(files))
  species <- list(parakeet = c("Psittacula longicauda", "Long-tailed Parakeet"),
                  pigeon = c("Ducula nicobarica", "Nicobar Imperial-Pigeon"),
                  myna = c("Gracula religiosa", "Common Hill Myna"))
  one <- function(file, sp, start, end, confidence) {
    data.frame(rel = rel[file], start_s = start, end_s = end,
               scientific_name = species[[sp]][1], common_name = species[[sp]][2],
               confidence = confidence, stringsAsFactors = FALSE)
  }
  parakeet <- Map(function(file, c1, c2) rbind(one(file, "parakeet", 0, 3, c1),
                                               one(file, "parakeet", 1.5, 4.5, c2)),
                  1:6, c(0.92, 0.81, 0.66, 0.74, 0.58, 0.45), c(0.88, 0.77, 0.52, 0.69, 0.55, 0.35))
  pigeon <- Map(function(file, conf) one(file, "pigeon", 0, 3, conf),
                c(1L, 2L, 4L, 5L), c(0.71, 0.64, 0.83, 0.58))
  detections <- do.call(rbind, c(
    parakeet, pigeon,
    list(one(4L, "myna", 0, 3, 0.95),
         one(2L, "myna", 0, 3, 0.31),          # below the default threshold
         one(3L, "parakeet", 4, 7, 0.60),      # a window beyond the end of the recording
         one(1L, "parakeet", 0, 3, 0.92))))    # a duplicate of an earlier row
  batch_file <- file.path(batch_dir, "batch_001.csv")
  utils::write.csv(detections, batch_file, row.names = FALSE)

  # only what differs from the template defaults
  config <- file.path(root, "config", "config.yml")
  writeLines(c(
    "paths:",
    sprintf("  project_root: \"%s\"", root),
    "filenames:",
    "  timezone: \"Asia/Kolkata\"",
    "birdnet:",
    "  run_id: \"run01\"",
    "occupancy:",
    "  run_id: \"run01\"",
    "  min_effort_hours: 0",
    "  min_detections: 1",
    "recall:",
    "  segment_s: 1",
    "filter:",
    "  workers: 1"),
    config)

  list(root = root, config = config, cfg = pam_config_read(config), audio_dir = audio_dir,
       files = files, deployments = deployments, detections = batch_file)
}
