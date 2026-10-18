# Write a timestamped log line to a per-stage log file

Write a timestamped log line to a per-stage log file

## Usage

``` r
pam_log(level = c("INFO", "WARN", "ERROR"), msg, stage, log_dir, echo = TRUE)
```

## Arguments

- level:

  One of "INFO", "WARN", "ERROR".

- msg:

  Character message.

- stage:

  Stage name, used as the log file name (`<stage>.log`).

- log_dir:

  Directory for log files (created if missing).

- echo:

  Also print to the console.

## Value

The log line, invisibly.
