#' Check that the config has what pam_detect() needs (internal)
#'
#' Gives one clear message instead of a cryptic error later (an unset path makes
#' `file.path()` return nothing and `dir.create()` fail with "invalid 'path'").
#'
#' @param cfg A `pam_config` object.
#' @param need_master TRUE when the master table must be read from `paths$metadata`.
#' @return `cfg`, invisibly. Aborts listing the missing entries.
#' @keywords internal
#' @noRd
pam_detect_check_cfg <- function(cfg, need_master = TRUE) {
  bc <- cfg$birdnet
  missing <- character()
  chk <- function(x, name) {
    if (is.null(x) || length(x) != 1L || is.na(x) || !nzchar(as.character(x))) {
      missing <<- c(missing, name)
    }
  }
  chk(cfg$paths$detections, "paths$detections")
  chk(cfg$paths$logs, "paths$logs")
  chk(cfg$paths$audio_standardized, "paths$audio_standardized")
  if (need_master) chk(cfg$paths$metadata, "paths$metadata")
  if (identical(bc$input, "filtered")) chk(cfg$paths$filtered, "paths$filtered")
  chk(bc$run_id, "birdnet$run_id")
  chk(bc$chunk_size, "birdnet$chunk_size")
  if (length(missing)) {
    rlang::abort(c("The configuration is incomplete for pam_detect(); these entries are missing:",
                   stats::setNames(missing, rep("x", length(missing))),
                   i = "Reload it with cfg <- pam_load_config('<full path to your config.yml>')."))
  }
  invisible(cfg)
}

#' Resolve and validate BirdNET settings from the config (internal)
#'
#' Resolves the model files and the options passed to the Python runner. It does
#' not start Python; `pam_birdnet_py_check()` verifies the environment.
#'
#' @param cfg A `pam_config` object.
#' @return A plain list of settings.
#' @keywords internal
#' @noRd
pam_detect_settings <- function(cfg) {
  bc <- cfg$birdnet
  root <- cfg$paths$project_root
  resolve <- function(p) {
    if (is.null(p) || is.na(p)) return(NULL)
    if (fs::is_absolute_path(p)) as.character(p) else as.character(fs::path(root, p))
  }
  model_dir <- resolve(bc$model_dir)
  if (is.null(model_dir) || !dir.exists(model_dir)) {
    rlang::abort(sprintf("Custom classifier folder not found: %s",
                         paste(model_dir, collapse = "")))
  }
  # accept "Name" or "Name.tflite"
  name <- sub("\\.tflite$", "", bc$classifier_name, ignore.case = TRUE)
  model_file <- file.path(model_dir, paste0(name, ".tflite"))
  labels_file <- if (is.null(bc$labels_file)) {
    file.path(model_dir, paste0(name, "_Labels.txt"))
  } else resolve(bc$labels_file)
  need <- c(model_file, labels_file)
  if (any(!file.exists(need))) {
    rlang::abort(c("Custom classifier files not found:",
                   stats::setNames(need[!file.exists(need)], rep("x", sum(!file.exists(need))))))
  }
  # the birdnetR engine was removed; only the Python `birdnet` engine remains
  backend <- if (is.null(bc$backend)) "birdnet" else bc$backend
  if (!identical(backend, "birdnet")) {
    rlang::abort(c(sprintf("birdnet$backend \"%s\" is not supported.", paste(backend, collapse = ",")),
                   i = "The birdnetR engine was removed. Delete the `backend` line or set it to \"birdnet\"."))
  }
  env_dir <- if (is.null(bc$python_env)) pam_birdnet_env_dir("inference") else resolve(bc$python_env)
  w <- pam_birdnet_resolve_workers(bc$workers)
  s <- list(model_dir = model_dir, classifier_name = name,
            model_file = model_file, labels_file = labels_file,
            min_confidence = bc$min_confidence, overlap_s = bc$overlap_s,
            use_bandpass = bc$use_bandpass,
            bandpass_fmin = bc$bandpass_fmin, bandpass_fmax = bc$bandpass_fmax,
            python = pam_birdnet_python_path(env_dir), script = pam_birdnet_py_script(),
            workers = w$workers, worker_notes = w$notes,
            py_batch_size = if (is.null(bc$py_batch_size)) 1L else bc$py_batch_size,
            n_producers = if (is.null(bc$n_producers)) 1L else bc$n_producers,
            sigmoid_sensitivity = if (is.null(bc$sigmoid_sensitivity)) 1 else bc$sigmoid_sensitivity,
            device = if (is.null(bc$device)) "CPU" else bc$device,
            model_version = if (is.null(bc$model_version)) "2.4" else bc$model_version)
  s$top_k <- bc$top_k                                   # NULL = every species above the threshold
  s
}

#' Stage 3: run the custom BirdNET classifier on all QC-passed recordings
#'
#' Reads from the filtered folder (default) or the standardized folder
#' (`birdnet$input`), runs BirdNET in parallel worker processes, and writes
#' raw detections in batches to `<detections>/<run_id>/batches/`.
#'
#' @param cfg A `pam_config` object (uses the `birdnet` section).
#' @param master Optional Stage 1 master table; if NULL it is read from
#'   `metadata/audio_master.csv`.
#' @param sample_n If set, process a random sample of this many files (for
#'   pilots). The same `seed` gives the same sample.
#' @param seed Seed for the pilot sample.
#' @param force If TRUE, delete this run's earlier results and start over.
#' @return Invisibly, a list: `n_pending`, `n_done`, `n_failed`,
#'   `n_detections`, `run_dir`.
#' @details BirdNET runs in pamflow's Python inference environment (see
#'   `pam_birdnet_setup()`) using the `birdnet` Python package, which does its
#'   own multiprocessing: `birdnet$workers` worker processes each load the
#'   model (an unset value means half of the physical cores). `top_k` limits
#'   the species kept per 3 s segment (NULL = all above `min_confidence`).
#'   Resumable. A file is marked done (`<run_dir>/done.txt`) only after
#'   its batch file is on disk, and files with no detections count as done.
#'   If a crash happens between writing a batch and updating the checkpoint,
#'   those files are re-run, and `pam_assemble_detections()` removes the
#'   duplicates. Per-file outcomes (seconds, errors) go to `file_results.csv`;
#'   settings and the `birdnet` package version go to `run_settings_*.yml`.
#'   Run with `pam_run_stage("03_detect", pam_detect, cfg)`.
#' @examples
#' \dontrun{
#' # needs the BirdNET Python environment (pam_birdnet_setup("inference")) and your model
#' cfg <- pam_config_read("config/config.yml")
#' res <- pam_run_stage("03_detect", pam_detect, cfg)
#' }
#' @export
pam_detect <- function(cfg, master = NULL, sample_n = NULL, seed = 1L, force = FALSE) {
  stage <- "03_detect"; log_dir <- cfg$paths$logs
  bc <- cfg$birdnet
  pam_detect_check_cfg(cfg, need_master = is.null(master))
  s <- pam_detect_settings(cfg)
  workers <- s$workers
  run_dir <- file.path(cfg$paths$detections, bc$run_id)
  batch_dir <- file.path(run_dir, "batches")
  dir.create(batch_dir, recursive = TRUE, showWarnings = FALSE)
  ckpt <- file.path(run_dir, "done.txt")
  results_path <- file.path(run_dir, "file_results.csv")
  if (force) unlink(c(ckpt, results_path, list.files(batch_dir, full.names = TRUE)))

  if (is.null(master)) {
    mp <- file.path(cfg$paths$metadata, "audio_master.csv")
    if (!file.exists(mp)) rlang::abort("audio_master.csv not found. Run Stage 1 first.")
    master <- data.table::fread(mp, select = c("file_path", "qc_pass"))
  }
  root <- cfg$paths$audio_standardized
  src <- master[qc_pass == TRUE]
  rel <- as.character(fs::path_rel(src$file_path, start = root))
  input_dir <- if (identical(bc$input, "filtered")) cfg$paths$filtered else root
  todo <- data.table::data.table(rel = rel, path = file.path(input_dir, rel))

  absent <- !file.exists(todo$path)
  if (any(absent)) {
    pam_log("WARN", sprintf("%d files not found in %s input folder (run Stage 2?); skipped",
                            sum(absent), bc$input), stage, log_dir)
    todo <- todo[!absent]
  }
  if (!is.null(sample_n)) {
    n_todo <- nrow(todo)
    todo <- todo[withr::with_seed(seed, sample.int(n_todo, min(as.integer(sample_n), n_todo)))]
  }
  pending <- todo[!rel %in% pam_checkpoint_read(ckpt)]
  if (!nrow(pending)) {
    pam_log("INFO", "nothing pending for this run", stage, log_dir)
    return(invisible(list(n_pending = 0L, n_done = 0L, n_failed = 0L,
                          n_detections = 0L, run_dir = run_dir)))
  }

  # stop worker processes left behind by an earlier interrupted run, so they do not
  # compete for memory and CPU with this one
  orphans <- tryCatch(pam_birdnet_cleanup(quiet = TRUE), error = function(e) NULL)
  if (!is.null(orphans) && any(orphans$killed)) {
    pam_log("WARN", sprintf("stopped %d leftover BirdNET worker process(es) from an earlier interrupted run",
                            sum(orphans$killed)), stage, log_dir)
  }

  chk <- pam_birdnet_py_check(s)       # loads the model once; also checks the labels against it
  if (!chk$ok) {
    rlang::abort(c("BirdNET could not load the model.", i = chk$message))
  }
  ver <- chk$birdnet_version
  for (note in s$worker_notes) pam_log("WARN", note, stage, log_dir)
  pam_log("INFO", sprintf("birdnet %s; %d files pending; input=%s; %d workers; top_k=%s",
                          ver, nrow(pending), bc$input, workers,
                          if (is.null(s$top_k)) "all" else s$top_k), stage, log_dir)
  yaml::write_yaml(
    list(started = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), backend = "birdnet",
         birdnet_version = ver, input_dir = input_dir, n_files = nrow(todo), settings = s),
    file.path(run_dir, sprintf("run_settings_%s.yml", format(Sys.time(), "%Y%m%d_%H%M%S"))))

  batches <- split(seq_len(nrow(pending)), ceiling(seq_len(nrow(pending)) / bc$chunk_size))
  t_start <- Sys.time()
  n_done <- 0L; n_fail <- 0L; n_det <- 0L
  cli::cli_progress_bar("Detecting", total = nrow(pending))

  for (b in seq_along(batches)) {
    idx <- batches[[b]]
    items <- lapply(idx, function(i) list(rel = pending$rel[i], path = pending$path[i]))

    res <- tryCatch(
      pam_birdnet_run_batch_py(items, s),        # parallelism happens inside the Python process
      error = function(e) {
        pam_log("ERROR", paste("batch", b, "failed:", conditionMessage(e)), stage, log_dir)
        NULL
      })
    if (is.null(res)) {                    # the files stay pending for the next run
      cli::cli_progress_update(inc = length(idx))
      next
    }

    file_log <- data.table::rbindlist(lapply(res, function(r) {
      data.table::data.table(rel = r$rel, ok = r$ok, n_detections = nrow(r$det),
                             seconds = round(r$seconds, 1), message = r$message)
    }))
    det <- data.table::rbindlist(lapply(res, function(r) {
      if (!isTRUE(r$ok) || !nrow(r$det)) return(NULL)
      d <- data.table::as.data.table(r$det)
      d[, rel := r$rel]
      d
    }), use.names = TRUE, fill = TRUE)

    if (nrow(det)) {
      out_path <- file.path(batch_dir, sprintf("batch_%s_%03d.csv",
                                               format(Sys.time(), "%Y%m%d%H%M%S"), b))
      data.table::fwrite(det, paste0(out_path, ".part"))
      file.rename(paste0(out_path, ".part"), out_path)
    }
    data.table::fwrite(file_log, results_path, append = file.exists(results_path))
    pam_checkpoint_add(file_log[ok == TRUE, rel], ckpt)

    n_done <- n_done + sum(file_log$ok); n_fail <- n_fail + sum(!file_log$ok)
    n_det <- n_det + nrow(det)
    mins <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
    done_total <- n_done + n_fail
    eta <- if (done_total > 0) mins / done_total * (nrow(pending) - done_total) else NA_real_
    pam_log("INFO", sprintf("batch %d/%d: %d ok, %d failed, %d detections | %.1f files/h | ETA %.0f min",
                            b, length(batches), sum(file_log$ok), sum(!file_log$ok), nrow(det),
                            done_total / mins * 60, eta), stage, log_dir)
    cli::cli_progress_update(inc = length(idx))
  }
  cli::cli_progress_done()
  pam_log("INFO", sprintf("finished: %d ok, %d failed, %d detections", n_done, n_fail, n_det),
          stage, log_dir)
  invisible(list(n_pending = nrow(pending), n_done = n_done, n_failed = n_fail,
                 n_detections = n_det, run_dir = run_dir))
}

#' Assemble raw detection batches into one detections table
#'
#' Reads all batch files of a run, removes duplicates (from interrupted runs),
#' joins recording metadata from the Stage 1 master table, and writes
#' `<detections>/<run_id>/detections.csv`.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Name of the detection run (a sub-folder of paths$detections).
#'   Defaults to birdnet$run_id.
#' @return A data.table with `filename`, `species`, `scientific_name`,
#'   `common_name`, `confidence`, `start_time` and `end_time` (seconds into the
#'   recording), `site` (= grid), `grid`, `recorder`, `deployment_id`,
#'   `in_deployment`, `recording_date`, `recording_start` and
#'   `detection_datetime` (local time), `rel`.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' det <- suppressMessages(pam_assemble_detections(ex$cfg))
#' nrow(det)   # the batch file had one duplicate row, which is dropped
#' as.data.frame(det)[, c("filename", "species", "confidence", "start_time", "end_time")]
#' @export
pam_assemble_detections <- function(cfg, run_id = cfg$birdnet$run_id) {
  tz <- cfg$filenames$timezone
  run_dir <- file.path(cfg$paths$detections, run_id)
  files <- list.files(file.path(run_dir, "batches"), pattern = "^batch_.*\\.csv$",
                      full.names = TRUE)
  if (!length(files)) rlang::abort(sprintf("No detection batch files in %s", run_dir))

  det <- data.table::rbindlist(lapply(files, data.table::fread), use.names = TRUE, fill = TRUE)
  n_raw <- nrow(det)
  det <- unique(det, by = c("rel", "start_s", "end_s", "scientific_name"))

  m <- data.table::fread(file.path(cfg$paths$metadata, "audio_master.csv"),
                         select = c("file_path", "grid", "recorder", "deployment_id",
                                    "start_time", "in_deployment"))
  m[, rel := as.character(fs::path_rel(file_path, start = cfg$paths$audio_standardized))]
  st <- m$start_time
  if (is.character(st)) st <- as.POSIXct(st, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  attr(st, "tzone") <- tz
  m[, recording_start := st]
  m[, c("file_path", "start_time") := NULL]

  det <- merge(det, m, by = "rel", all.x = TRUE, sort = FALSE)
  det[, `:=`(
    filename = basename(rel),
    species = ifelse(is.na(common_name), scientific_name,
                     paste(scientific_name, common_name, sep = "_")),
    site = grid,
    recording_date = as.Date(format(recording_start, "%Y-%m-%d")),
    detection_datetime = recording_start + start_s)]
  data.table::setnames(det, c("start_s", "end_s"), c("start_time", "end_time"))
  data.table::setorder(det, grid, recording_start, start_time)
  data.table::setcolorder(det, c("filename", "species", "scientific_name", "common_name",
                                 "confidence", "start_time", "end_time", "site", "grid",
                                 "recorder", "deployment_id", "in_deployment",
                                 "recording_date", "recording_start", "detection_datetime",
                                 "rel"))

  out <- data.table::copy(det)
  out[, c("recording_start", "detection_datetime") :=
        .(format(recording_start, "%Y-%m-%d %H:%M:%S"),
          format(detection_datetime, "%Y-%m-%d %H:%M:%OS1"))]
  data.table::fwrite(out, file.path(run_dir, "detections.csv"))
  pam_log("INFO", sprintf("assembled %d detections (%d duplicates removed) from %d batch files",
                          nrow(det), n_raw - nrow(det), length(files)),
          "03_assemble", cfg$paths$logs)
  det[]
}
