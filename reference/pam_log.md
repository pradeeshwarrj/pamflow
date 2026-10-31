# Write a timestamped log line to a per-stage log file

Write a timestamped log line to a per-stage log file

## Usage

``` r
pam_log(
  level = c("INFO", "WARN", "ERROR"),
  msg,
  stage = "pamflow",
  log_dir = NULL,
  echo = TRUE
)
```

## Arguments

- level:

  One of "INFO", "WARN", "ERROR".

- msg:

  Character message.

- stage:

  Stage name, used as the log file name (`<stage>.log`).

- log_dir:

  Directory for log files (created if missing). If NULL, file logging is
  skipped.

- echo:

  Also print to the console.

## Value

The log line, invisibly.

## Examples

``` r
log_dir <- tempfile("pamflow_logs_")
pam_log("INFO", "scan started", stage = "01_scan", log_dir = log_dir)
#> 2026-10-31 10:03:43 [INFO] [01_scan] scan started
readLines(file.path(log_dir, "01_scan.log"))
#> [1] "2026-10-31 10:03:43 [INFO] [01_scan] scan started"
unlink(log_dir, recursive = TRUE)
```
