mk_procs <- function() {
  data.frame(
    pid = c(100L, 101L, 102L, 103L, 104L, 105L),
    name = c("python.exe", "python.exe", "python.exe", "node.exe", "python.exe", "Python.exe"),
    cmdline = c(
      "python.exe script.py --model m.tflite",
      "python.exe -c from multiprocessing.spawn import spawn_main; spawn_main(parent_pid=100, pipe_handle=7) --multiprocessing-fork",
      "python.exe -c from multiprocessing.spawn import spawn_main; spawn_main(parent_pid=999, pipe_handle=8) --multiprocessing-fork",
      "node.exe -c from multiprocessing.spawn import spawn_main; spawn_main(parent_pid=999, pipe_handle=9)",
      "python.exe -c from multiprocessing.resource_tracker import main;main(5)",
      "Python.exe -c from multiprocessing.spawn import spawn_main; spawn_main(parent_pid=998, pipe_handle=3) --multiprocessing-fork"),
    stringsAsFactors = FALSE)
}

test_that("only workers whose parent process is gone are reported", {
  o <- pam_find_orphan_workers(mk_procs())
  expect_equal(sort(o$pid), c(102L, 105L))          # parent 999 and 998 do not exist
  expect_equal(o$parent_pid[o$pid == 102L], 999L)
  expect_false(101L %in% o$pid)                     # its parent (100) is running
  expect_false(103L %in% o$pid)                     # not a python process
  expect_false(104L %in% o$pid)                     # not a spawned worker
})

test_that("empty, NA and worker-free process tables give no orphans", {
  empty <- data.frame(pid = integer(), name = character(), cmdline = character())
  expect_equal(nrow(pam_find_orphan_workers(empty)), 0L)
  expect_equal(nrow(pam_find_orphan_workers(NULL)), 0L)
  na_cmd <- data.frame(pid = 1:2, name = c("python.exe", "python.exe"),
                       cmdline = c(NA_character_, "python.exe -m pip list"))
  expect_equal(nrow(pam_find_orphan_workers(na_cmd)), 0L)
  expect_named(pam_find_orphan_workers(empty), c("pid", "name", "parent_pid"))
})

test_that("cleanup stops the orphans and reports what it did", {
  procs <- mk_procs(); procs$handle <- as.list(procs$pid)        # stand-ins for ps handles
  stopped <- integer()
  local_mocked_bindings(
    pam_process_snapshot = function() procs,
    pam_kill_process = function(handle) { stopped <<- c(stopped, handle); handle != 105L })
  res <- pam_birdnet_cleanup(quiet = TRUE)
  expect_equal(sort(stopped), c(102L, 105L))
  expect_equal(res$killed[res$pid == 102L], TRUE)
  expect_equal(res$killed[res$pid == 105L], FALSE)                # kill failed -> reported as not stopped
})

test_that("kill = FALSE only reports", {
  procs <- mk_procs(); procs$handle <- as.list(procs$pid)
  local_mocked_bindings(
    pam_process_snapshot = function() procs,
    pam_kill_process = function(handle) stop("must not be called"))
  res <- pam_birdnet_cleanup(kill = FALSE, quiet = TRUE)
  expect_equal(nrow(res), 2L)
  expect_false(any(res$killed))
})

test_that("no orphans gives an empty result and a friendly message", {
  procs <- mk_procs()[1:2, ]; procs$handle <- as.list(procs$pid)
  local_mocked_bindings(pam_process_snapshot = function() procs)
  expect_message(res <- pam_birdnet_cleanup(), "No leftover")
  expect_equal(nrow(res), 0L)
})

test_that("the real process snapshot has the columns the cleanup needs", {
  skip_if_not_installed("ps")
  snap <- pam_process_snapshot()
  expect_true(all(c("pid", "name", "cmdline", "handle") %in% names(snap)))
  expect_true(Sys.getpid() %in% snap$pid)
  expect_equal(nrow(pam_find_orphan_workers(snap)) >= 0L, TRUE)   # runs on a real table without error
})
