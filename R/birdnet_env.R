#' Folder holding pamflow's private BirdNET Python environments
#'
#' Environments live outside the project (in the user's R data directory) so
#' they are shared by all projects and never touch the system Python.
#'
#' @param component One of "inference" or "training".
#' @return A path (the environment may not exist yet).
#' @keywords internal
#' @noRd
pam_birdnet_env_dir <- function(component = c("inference", "training")) {
  component <- match.arg(component)
  normalizePath(file.path(tools::R_user_dir("pamflow", which = "data"), "venvs",
                          paste0("birdnet-", component)),
                winslash = "/", mustWork = FALSE)
}

#' Path of the Python executable inside a virtual environment
#'
#' @param envdir Environment folder.
#' @return Path to python(.exe); may not exist.
#' @keywords internal
#' @noRd
pam_birdnet_python_path <- function(envdir) {
  if (.Platform$OS.type == "windows") {
    file.path(envdir, "Scripts", "python.exe")
  } else {
    file.path(envdir, "bin", "python")
  }
}

#' Default pip requirements for each BirdNET component
#'
#' The inference component uses the `birdnet` Python package (the same API
#' that `birdnetR` wraps; it brings in TensorFlow). The training
#' component uses the BirdNET-Analyzer package. They are kept in separate
#' environments because their TensorFlow pins may conflict.
#'
#' @return A named list of character vectors.
#' @keywords internal
#' @noRd
pam_birdnet_default_requirements <- function() {
  list(inference = c("birdnet>=0.2.16,<0.3"),
       training = c("birdnet-analyzer"))
}

#' Python probe script run inside an environment (internal)
#'
#' Prints `PAMPROBE key=value` lines. Run as a separate process so the R
#' session never loads TensorFlow.
#'
#' @return Character vector of script lines.
#' @keywords internal
#' @noRd
pam_birdnet_probe_script <- function() {
  c(
    "import os, platform",
    "os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '3')",
    "def emit(k, v):",
    "    print('PAMPROBE %s=%s' % (k, str(v).replace(chr(10), ' ')))",
    "emit('python', platform.python_version())",
    "from importlib import metadata",
    "found = {}",
    "for dist in ('tensorflow', 'birdnet', 'birdnet-analyzer'):",
    "    try:",
    "        found[dist] = metadata.version(dist)",
    "    except Exception:",
    "        found[dist] = 'missing'",
    "    emit('pkg_' + dist, found[dist])",
    "if found['tensorflow'] != 'missing':",
    "    try:",
    "        import tensorflow as tf",
    "        emit('tf_gpus', len(tf.config.list_physical_devices('GPU')))",
    "    except Exception as e:",
    "        emit('tf_import', 'error: ' + type(e).__name__)",
    "emit('cpu_count', os.cpu_count())"
  )
}

#' Parse `PAMPROBE key=value` lines into a named list (internal)
#'
#' Ignores every other line (TensorFlow prints a lot of log noise).
#'
#' @param lines Character vector of process output.
#' @return Named list of strings; empty if no probe lines.
#' @keywords internal
#' @noRd
pam_birdnet_parse_probe <- function(lines) {
  lines <- as.character(lines)
  hit <- lines[startsWith(lines, "PAMPROBE ")]
  if (!length(hit)) return(list())
  kv <- sub("^PAMPROBE ", "", hit)
  eq <- regexpr("=", kv, fixed = TRUE)
  ok <- eq > 0L
  keys <- substr(kv[ok], 1L, eq[ok] - 1L)
  vals <- substr(kv[ok], eq[ok] + 1L, nchar(kv[ok]))
  stats::setNames(as.list(vals), keys)
}

#' Run the probe script with one environment's Python (internal)
#'
#' @param python Path to a Python executable.
#' @return Named list from `pam_birdnet_parse_probe()`, or an empty list when
#'   the executable is missing or the process fails.
#' @keywords internal
#' @noRd
pam_birdnet_probe <- function(python) {
  if (!nzchar(python) || !file.exists(python)) return(list())
  script <- tempfile(fileext = ".py")
  on.exit(unlink(script), add = TRUE)
  writeLines(pam_birdnet_probe_script(), script)
  out <- tryCatch(
    suppressWarnings(system2(python, c("-I", shQuote(script)), stdout = TRUE, stderr = TRUE)),
    error = function(e) character())
  pam_birdnet_parse_probe(out)
}

#' Total physical memory in GB (internal; NA if it cannot be determined)
#'
#' @return Numeric scalar.
#' @keywords internal
#' @noRd
pam_system_ram_gb <- function() {
  tryCatch({
    if (.Platform$OS.type == "windows") {
      out <- suppressWarnings(system2(
        "powershell",
        c("-NoProfile", "-Command",
          shQuote("(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory")),
        stdout = TRUE, stderr = FALSE))
      round(as.numeric(trimws(out[1L])) / 1024^3, 1)
    } else if (file.exists("/proc/meminfo")) {
      line <- grep("^MemTotal:", readLines("/proc/meminfo", n = 3L), value = TRUE)
      round(as.numeric(gsub("[^0-9]", "", line)) / 1024^2, 1)
    } else NA_real_
  }, error = function(e) NA_real_, warning = function(w) NA_real_)
}

#' GPU name reported by nvidia-smi (internal; NA if none)
#'
#' @return Character scalar.
#' @keywords internal
#' @noRd
pam_nvidia_gpu_name <- function() {
  exe <- Sys.which("nvidia-smi")
  if (!nzchar(exe)) return(NA_character_)
  out <- tryCatch(
    suppressWarnings(system2(exe, c("--query-gpu=name", "--format=csv,noheader"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character())
  if (!length(out)) NA_character_ else trimws(out[1L])
}

#' Build one row of the doctor report (internal)
#'
#' @param check Short name of the check.
#' @param status One of "ok", "warn", "fail", "info".
#' @param detail Human-readable detail.
#' @return A one-row data.frame.
#' @keywords internal
#' @noRd
pam_doctor_row <- function(check, status, detail) {
  stopifnot(status %in% c("ok", "warn", "fail", "info"))
  data.frame(check = check, status = status, detail = detail, stringsAsFactors = FALSE)
}

#' Check the machine and Python environments needed for BirdNET
#'
#' Inspects the R session, the machine (CPU cores, RAM, GPU) and the two
#' pamflow BirdNET Python environments, and reports what is missing and what
#' to do about it. Nothing is installed or changed. TensorFlow is probed in a
#' separate process, so this never loads Python into your R session.
#'
#' @param envs Named list with the folders of the "inference" and "training"
#'   environments. Defaults to pamflow's private environments.
#' @param quiet If TRUE, return the table without printing it.
#' @return Invisibly, a data.frame with columns `check`, `status`
#'   (`ok`/`warn`/`fail`/`info`) and `detail`. Class `pam_birdnet_doctor`.
#' @details Assumptions: on native Windows, TensorFlow has no GPU support, so
#'   pamflow runs BirdNET on CPU there; a detected NVIDIA GPU is reported as
#'   information only. Run `pam_birdnet_setup()` to create missing
#'   environments.
#' @examples
#' \dontrun{
#' pam_birdnet_doctor()
#' }
#' @export
pam_birdnet_doctor <- function(envs = list(inference = pam_birdnet_env_dir("inference"),
                                           training = pam_birdnet_env_dir("training")),
                               quiet = FALSE) {
  rows <- list()
  add <- function(...) rows[[length(rows) + 1L]] <<- pam_doctor_row(...)

  # R side
  has_ret <- requireNamespace("reticulate", quietly = TRUE)
  if (has_ret) {
    v <- utils::packageVersion("reticulate")
    add("reticulate", if (v >= "1.41") "ok" else "warn",
        sprintf("version %s%s", v, if (v >= "1.41") "" else " (>= 1.41 recommended: can download Python via uv)"))
  } else {
    add("reticulate", "fail", "not installed: install.packages('reticulate')")
  }
  add("ffmpeg", if (nzchar(Sys.which("ffmpeg"))) "ok" else "warn",
      if (nzchar(Sys.which("ffmpeg"))) Sys.which("ffmpeg") else "not on PATH (needed for Stages 0 and 2)")

  # machine
  add("cpu_cores", "info", sprintf("%s physical / %s logical",
                                   parallel::detectCores(logical = FALSE),
                                   parallel::detectCores(logical = TRUE)))
  ram <- pam_system_ram_gb()
  add("ram_gb", if (is.na(ram)) "info" else if (ram >= 16) "ok" else "warn",
      if (is.na(ram)) "could not be determined" else sprintf("%.1f GB", ram))
  gpu <- pam_nvidia_gpu_name()
  if (is.na(gpu)) {
    add("gpu", "info", "no NVIDIA GPU detected (CPU mode)")
  } else if (.Platform$OS.type == "windows") {
    add("gpu", "info", sprintf("%s detected, but TensorFlow has no native Windows GPU support: BirdNET will run on CPU", gpu))
  } else {
    add("gpu", "info", sprintf("%s detected; see the tf_gpus check for whether TensorFlow can use it", gpu))
  }

  # Python environments
  need <- list(inference = c("tensorflow", "birdnet"),
               training = c("tensorflow", "birdnet-analyzer"))
  for (comp in names(envs)) {
    py <- pam_birdnet_python_path(envs[[comp]])
    if (!file.exists(py)) {
      add(paste0("env_", comp), "fail",
          sprintf("not found at %s: run pam_birdnet_setup('%s')", envs[[comp]], comp))
      next
    }
    pr <- pam_birdnet_probe(py)
    if (!length(pr)) {
      add(paste0("env_", comp), "fail", sprintf("Python at %s did not run; recreate with pam_birdnet_setup('%s', recreate = TRUE)", py, comp))
      next
    }
    add(paste0("env_", comp), "ok", sprintf("Python %s at %s", pr$python, py))
    for (pkg in need[[comp]]) {
      ver <- pr[[paste0("pkg_", pkg)]]
      missing <- is.null(ver) || identical(ver, "missing")
      add(paste0(comp, ":", pkg), if (missing) "fail" else "ok",
          if (missing) "not installed" else ver)
    }
    if (!is.null(pr$tf_import)) add(paste0(comp, ":tensorflow_import"), "fail", pr$tf_import)
    if (!is.null(pr$tf_gpus)) {
      add(paste0(comp, ":tf_gpus"), "info",
          sprintf("TensorFlow sees %s GPU(s)", pr$tf_gpus))
    }
  }

  out <- do.call(rbind, rows)
  class(out) <- c("pam_birdnet_doctor", class(out))
  if (!quiet) print(out)
  invisible(out)
}

#' @export
print.pam_birdnet_doctor <- function(x, ...) {
  for (i in seq_len(nrow(x))) {
    line <- sprintf("%-26s %s", x$check[i], x$detail[i])
    switch(x$status[i],
           ok = cli::cli_alert_success("{line}"),
           warn = cli::cli_alert_warning("{line}"),
           fail = cli::cli_alert_danger("{line}"),
           cli::cli_alert_info("{line}"))
  }
  n_fail <- sum(x$status == "fail")
  if (n_fail) cli::cli_alert_danger("{n_fail} problem{?s} found")
  invisible(x)
}

#' Locate the `uv` executable (internal)
#'
#' `uv` creates virtual environments and downloads the requested Python
#' version itself, so no system Python is needed.
#'
#' @return Path to uv, or NA_character_ if not found.
#' @keywords internal
#' @noRd
pam_find_uv <- function() {
  on_path <- Sys.which("uv")
  if (nzchar(on_path)) return(unname(as.character(on_path)))
  home <- Sys.getenv("USERPROFILE", unset = Sys.getenv("HOME"))
  candidates <- c(
    file.path(home, ".local", "bin", if (.Platform$OS.type == "windows") "uv.exe" else "uv"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "WinGet", "Links", "uv.exe"))
  winget_pkgs <- Sys.glob(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "WinGet",
                                    "Packages", "astral-sh.uv_*", "uv.exe"))
  candidates <- c(candidates, winget_pkgs)
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) normalizePath(hit[1L], winslash = "/") else NA_character_
}

#' Create a private Python environment for BirdNET
#'
#' Builds a virtual environment (never touching the system Python) with a
#' pinned Python version. Uses `uv` when it is installed (it downloads the
#' requested Python itself); otherwise falls back to `reticulate`, which needs
#' a matching Python already installed.
#'
#' @param component "inference" (the `birdnet` package, used by Stage 3) or
#'   "training" (BirdNET-Analyzer, used only by the standalone training tools,
#'   which are not part of the workflow).
#' @param python_version Python version for the environment. Default "3.11",
#'   chosen as widely supported by TensorFlow; change it if a package install
#'   reports an unsupported version.
#' @param packages pip requirements. Defaults to
#'   `pam_birdnet_default_requirements()[[component]]`.
#' @param envdir Environment folder. Defaults to pamflow's private location.
#' @param recreate If TRUE, delete and rebuild an existing environment.
#' @param dry_run If TRUE, only return the plan without creating anything.
#' @param uv Path to the uv executable. Found automatically when uv is on PATH
#'   or in a standard install location; set it if you installed uv elsewhere.
#' @return Invisibly, a list: `envdir`, `python`, `python_version`, `packages`.
#' @details Installing TensorFlow downloads roughly a gigabyte, so this can
#'   take several minutes. Afterwards run `pam_birdnet_doctor()`.
#' @examples
#' \dontrun{
#' pam_birdnet_setup("inference", dry_run = TRUE)
#' pam_birdnet_setup("inference")
#' pam_birdnet_setup("training")
#' }
#' @export
pam_birdnet_setup <- function(component = c("inference", "training"),
                              python_version = "3.11",
                              packages = NULL,
                              envdir = pam_birdnet_env_dir(component),
                              recreate = FALSE,
                              dry_run = FALSE,
                              uv = pam_find_uv()) {
  component <- match.arg(component)
  if (is.null(packages)) packages <- pam_birdnet_default_requirements()[[component]]
  plan <- list(envdir = envdir, python = pam_birdnet_python_path(envdir),
               python_version = python_version, packages = packages)
  if (dry_run) return(invisible(plan))

  if (dir.exists(envdir)) {
    if (!recreate) {
      rlang::inform(sprintf("Environment already exists at %s (use recreate = TRUE to rebuild)", envdir))
      return(invisible(plan))
    }
    unlink(envdir, recursive = TRUE)
  }
  dir.create(dirname(envdir), recursive = TRUE, showWarnings = FALSE)
  cli::cli_alert_info("Creating {component} environment (Python {python_version}) at {envdir}")

  if (!is.null(uv) && !is.na(uv) && file.exists(uv)) {
    # preferred: uv downloads Python if needed and installs quickly
    run_uv <- function(args, what) {
      status <- system2(uv, args)
      if (!identical(as.integer(status), 0L)) {
        rlang::abort(c(sprintf("uv failed while %s (exit status %s).", what, status),
                       i = "Read the uv output above; a different python_version may be needed."))
      }
    }
    run_uv(c("venv", "--python", python_version, shQuote(envdir)), "creating the environment")
    run_uv(c("pip", "install", "--python", shQuote(plan$python), shQuote(packages)),
           "installing packages")
  } else {
    # fallback: reticulate, which needs a matching Python already installed
    if (!requireNamespace("reticulate", quietly = TRUE)) {
      rlang::abort("Install uv (see below) or the 'reticulate' package.")
    }
    tryCatch(
      reticulate::virtualenv_create(envname = envdir, version = python_version,
                                    packages = packages),
      error = function(e) {
        rlang::abort(c(sprintf("Could not create the %s environment.", component),
                       x = conditionMessage(e),
                       i = "Easiest fix: install uv (Windows: winget install --id astral-sh.uv), restart R, and run this again."))
      })
  }
  if (!file.exists(plan$python)) {
    rlang::abort(sprintf("Environment was created but %s is missing", plan$python))
  }
  cli::cli_alert_success("Done. Run pam_birdnet_doctor() to verify.")
  invisible(plan)
}
