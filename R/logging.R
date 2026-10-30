#' Write a timestamped log line to a per-stage log file
#'
#' @param level One of "INFO", "WARN", "ERROR".
#' @param msg Character message.
#' @param stage Stage name, used as the log file name (`<stage>.log`).
#' @param log_dir Directory for log files (created if missing). If NULL, file logging is skipped.
#' @param echo Also print to the console.
#' @return The log line, invisibly.
#' @examples
#' log_dir <- tempfile("pamflow_logs_")
#' pam_log("INFO", "scan started", stage = "01_scan", log_dir = log_dir)
#' readLines(file.path(log_dir, "01_scan.log"))
#' unlink(log_dir, recursive = TRUE)
#' @export
pam_log <- function(level = c("INFO", "WARN", "ERROR"), msg, stage = "pamflow", log_dir = NULL, echo = TRUE) {
  level <- match.arg(level)
  line <- sprintf("%s [%s] [%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                  level, stage, msg)
  if (!is.null(log_dir) && nzchar(log_dir)) {
    dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
    cat(paste0(line, "
"), file = file.path(log_dir, paste0(stage, ".log")), append = TRUE)
  }
  if (echo) message(line)
  invisible(line)
}

#' Run a workflow stage with logging and error isolation
#'
#' Logs start time, end time, duration and every warning, and converts errors
#' into a logged failure instead of terminating the whole workflow.
#'
#' @param stage Stage name (e.g. "03_detect").
#' @param fn Function taking `cfg` as its first argument.
#' @param cfg A `pam_config` object.
#' @param ... Passed on to `fn`.
#' @return A list: `status` ("ok" or "failed"), `result`, `duration` (difftime),
#'   `warnings` (character).
#' @examples
#' ex <- pam_example_project()
#' res <- suppressMessages(pam_run_stage("demo", function(cfg, x) x * 2, ex$cfg, x = 21))
#' res$status
#' res$result
#'
#' # an error is logged and returned as a failed status; it does not stop your script
#' bad <- suppressMessages(pam_run_stage("demo_fail", function(cfg) stop("boom"), ex$cfg))
#' bad$status
#' @export
pam_run_stage <- function(stage, fn, cfg, ...) {
  log_dir <- cfg$paths$logs
  t0 <- Sys.time()
  pam_log("INFO", "stage started", stage, log_dir)
  warns <- character()

  out <- withCallingHandlers(
    tryCatch(
      list(status = "ok", value = fn(cfg, ...)),
      error = function(e) {
        pam_log("ERROR", conditionMessage(e), stage, log_dir)
        list(status = "failed", value = NULL)
      }
    ),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      pam_log("WARN", conditionMessage(w), stage, log_dir)
      invokeRestart("muffleWarning")
    }
  )

  dur <- difftime(Sys.time(), t0, units = "mins")
  pam_log("INFO", sprintf("stage %s in %.2f min (%d warnings)",
                          if (out$status == "ok") "finished" else "FAILED",
                          as.numeric(dur), length(warns)), stage, log_dir)

  list(status = out$status, result = out$value, duration = dur, warnings = warns)
}
