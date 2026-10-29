#' Find orphaned BirdNET worker processes in a process table (internal)
#'
#' The Python `birdnet` package starts worker processes with
#' `multiprocessing` ("spawn"). Each one is started as
#' `... spawn_main(parent_pid=<PID>, ...)`. If the process with that id no
#' longer exists, the worker was left behind (for example after an interrupted
#' run) and nothing will ever stop it. Pure function (no I/O), so it can be tested.
#'
#' @param procs A data.frame with columns `pid`, `name` and `cmdline` (one
#'   string per process; NA when unknown), covering all processes on the machine.
#' @return A data.frame with `pid`, `name` and `parent_pid` of the orphans
#'   (zero rows if none).
#' @keywords internal
#' @noRd
pam_find_orphan_workers <- function(procs) {
  empty <- data.frame(pid = integer(), name = character(), parent_pid = integer(),
                      stringsAsFactors = FALSE)
  if (is.null(procs) || !nrow(procs)) return(empty)
  cmd <- ifelse(is.na(procs$cmdline), "", procs$cmdline)
  is_worker <- grepl("^python", procs$name, ignore.case = TRUE) &
    grepl("multiprocessing.spawn", cmd, fixed = TRUE) &
    grepl("parent_pid=[0-9]+", cmd)
  if (!any(is_worker)) return(empty)
  parent <- as.integer(sub(".*parent_pid=([0-9]+).*", "\\1", cmd[is_worker]))
  orphan <- !(parent %in% procs$pid)
  data.frame(pid = as.integer(procs$pid[is_worker][orphan]),
             name = as.character(procs$name[is_worker][orphan]),
             parent_pid = parent[orphan], stringsAsFactors = FALSE)
}

#' Snapshot of the running processes (internal; replaced by a mock in tests)
#'
#' @return A data.frame with `pid`, `name`, `cmdline` and a list column
#'   `handle` (a `ps` handle for each process). Command lines are only read
#'   for Python processes.
#' @keywords internal
#' @noRd
pam_process_snapshot <- function() {
  procs <- ps::ps()
  is_py <- grepl("^python", procs$name, ignore.case = TRUE)
  cmd <- rep(NA_character_, nrow(procs))
  for (i in which(is_py)) {
    cmd[i] <- tryCatch(paste(ps::ps_cmdline(procs$ps_handle[[i]]), collapse = " "),
                       error = function(e) NA_character_)
  }
  out <- data.frame(pid = as.integer(procs$pid), name = as.character(procs$name),
                    cmdline = cmd, stringsAsFactors = FALSE)
  out$handle <- procs$ps_handle
  out
}

#' Stop one process (internal; replaced by a mock in tests)
#'
#' @param handle A `ps` process handle.
#' @return TRUE if the process was stopped (or already gone), FALSE otherwise.
#' @keywords internal
#' @noRd
pam_kill_process <- function(handle) {
  tryCatch({ ps::ps_kill(handle); TRUE }, error = function(e) FALSE)
}

#' Stop BirdNET worker processes that were left behind
#'
#' Interrupting a run (Esc) or a crash can leave the worker processes of the
#' Python `birdnet` package running in the background, holding memory (about
#' 260 MB each). This finds those orphans and stops them. A worker counts as an
#' orphan only if the process that started it no longer exists, so workers of a
#' run that is still going are never touched.
#'
#' @param kill If FALSE, only report the orphans without stopping them.
#' @param quiet If TRUE, print nothing.
#' @return Invisibly, a data.frame with `pid`, `name`, `parent_pid` and `killed`
#'   (zero rows if there were no orphans).
#' @details `pam_detect()` and the training functions call this automatically
#'   (after an interrupt, and before a run starts), so you rarely need it.
#' @examples
#' \dontrun{
#' pam_birdnet_cleanup(kill = FALSE)   # just look
#' pam_birdnet_cleanup()               # stop them
#' }
#' @export
pam_birdnet_cleanup <- function(kill = TRUE, quiet = FALSE) {
  if (!requireNamespace("ps", quietly = TRUE)) {
    rlang::abort("Package 'ps' is required: install.packages('ps')")
  }
  procs <- pam_process_snapshot()
  orphans <- pam_find_orphan_workers(procs)
  orphans$killed <- rep(FALSE, nrow(orphans))
  if (nrow(orphans) && isTRUE(kill)) {
    for (i in seq_len(nrow(orphans))) {
      handle <- procs$handle[[match(orphans$pid[i], procs$pid)]]
      orphans$killed[i] <- pam_kill_process(handle)
    }
  }
  if (!quiet) {
    if (!nrow(orphans)) {
      cli::cli_alert_success("No leftover BirdNET worker processes found")
    } else if (isTRUE(kill)) {
      cli::cli_alert_info("Stopped {sum(orphans$killed)} of {nrow(orphans)} leftover worker process{?es}")
    } else {
      cli::cli_alert_warning("{nrow(orphans)} leftover worker process{?es} found (not stopped)")
    }
  }
  invisible(orphans)
}
