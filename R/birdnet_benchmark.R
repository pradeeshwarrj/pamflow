#' Summarise benchmark timings (internal)
#'
#' Pure function (no I/O) so it can be tested.
#'
#' @param timings data.frame with `workers`, `elapsed_s`, `n_done`, `n_failed`.
#' @param n_total Number of files in the full archive, or NULL.
#' @return A data.frame with `files_per_hour`, `speedup` (relative to the
#'   smallest worker count run), `efficiency` (speedup per worker ratio) and,
#'   when `n_total` is given, `est_hours_full`.
#' @keywords internal
#' @noRd
pam_bench_summarise <- function(timings, n_total = NULL) {
  out <- timings[order(timings$workers), , drop = FALSE]
  n_files <- out$n_done + out$n_failed
  out$files_per_hour <- ifelse(out$elapsed_s > 0, n_files / out$elapsed_s * 3600, NA_real_)
  base <- out$files_per_hour[1L]
  out$speedup <- out$files_per_hour / base
  out$efficiency <- out$speedup / (out$workers / out$workers[1L])
  if (!is.null(n_total)) out$est_hours_full <- n_total / out$files_per_hour
  rownames(out) <- NULL
  out
}

#' Benchmark Stage 3 detection speed at several worker counts
#'
#' Runs `pam_detect()` on the same random sample of recordings once per worker
#' count and reports throughput, scaling efficiency, and an estimate for the
#' whole archive. Use it to choose `birdnet$workers` for your CPU, and as the
#' baseline to compare the new backend against.
#'
#' @param cfg A `pam_config` object.
#' @param workers Integer vector of worker counts to test. Counts above the
#'   number of logical cores are dropped with a warning.
#' @param n_files Files per run. Each file takes about a minute for a 60-minute
#'   recording, so keep this small (default 8).
#' @param seed Seed for the file sample, identical for every run.
#' @param keep_runs If FALSE (default) the temporary detection folders are
#'   deleted afterwards.
#' @return A data.frame with one row per worker count: `workers`, `n_done`,
#'   `n_failed`, `elapsed_s`, `files_per_hour`, `speedup`, `efficiency` and
#'   `est_hours_full`. Also written to `<logs>/birdnet_benchmark.csv`.
#' @details The timing includes model loading in every worker, which is part of
#'   the real cost of starting a run. Real runs amortise it over many files, so
#'   the full-archive estimate is slightly pessimistic. Run on an otherwise idle
#'   machine.
#' @examples
#' \dontrun{
#' cfg <- pam_load_config("config.yml")
#' pam_birdnet_benchmark(cfg, workers = c(1, 4, 8), n_files = 8)
#' }
#' @export
pam_birdnet_benchmark <- function(cfg, workers = c(1L, 2L, 4L, 8L), n_files = 8L,
                                  seed = 1L, keep_runs = FALSE) {
  stage <- "03_benchmark"; log_dir <- cfg$paths$logs
  workers <- sort(unique(as.integer(workers)))
  logical_cores <- parallel::detectCores(logical = TRUE)
  if (!is.na(logical_cores) && any(workers > logical_cores)) {
    pam_log("WARN", sprintf("dropping worker counts above the %d logical cores", logical_cores),
            stage, log_dir)
    workers <- workers[workers <= logical_cores]
  }
  if (!length(workers)) rlang::abort("No valid worker counts to test.")

  master_path <- file.path(cfg$paths$metadata, "audio_master.csv")
  n_total <- NULL
  if (file.exists(master_path)) {
    qc <- data.table::fread(master_path, select = "qc_pass")
    n_total <- sum(qc$qc_pass == TRUE, na.rm = TRUE)
  }

  stamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  rows <- vector("list", length(workers))
  for (i in seq_along(workers)) {
    w <- workers[i]
    cfg_run <- cfg
    cfg_run$birdnet$workers <- w
    cfg_run$birdnet$run_id <- sprintf("bench_%s_w%d", stamp, w)
    run_dir <- file.path(cfg$paths$detections, cfg_run$birdnet$run_id)
    pam_log("INFO", sprintf("benchmark: %d worker(s), %d files", w, n_files), stage, log_dir)

    t0 <- proc.time()[["elapsed"]]
    res <- tryCatch(
      pam_detect(cfg_run, sample_n = n_files, seed = seed, force = TRUE),
      error = function(e) {
        pam_log("ERROR", sprintf("run with %d workers failed: %s", w, conditionMessage(e)),
                stage, log_dir)
        NULL
      })
    elapsed <- proc.time()[["elapsed"]] - t0
    if (!keep_runs) unlink(run_dir, recursive = TRUE)

    rows[[i]] <- data.frame(
      workers = w,
      n_done = if (is.null(res)) 0L else res$n_done,
      n_failed = if (is.null(res)) as.integer(n_files) else res$n_failed,
      elapsed_s = round(elapsed, 1))
  }

  timings <- do.call(rbind, rows)
  usable <- timings[timings$n_done > 0L, , drop = FALSE]
  if (!nrow(usable)) rlang::abort("Every benchmark run failed; see the log for details.")
  summary <- pam_bench_summarise(usable, n_total)

  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(summary, file.path(log_dir, "birdnet_benchmark.csv"))
  best <- summary[which.max(summary$files_per_hour), ]
  pam_log("INFO", sprintf("fastest: %d worker(s) at %.1f files/h%s", best$workers,
                          best$files_per_hour,
                          if (is.null(n_total)) "" else sprintf(" (about %.1f h for %d files)",
                                                                best$est_hours_full, n_total)),
          stage, log_dir)
  summary
}
