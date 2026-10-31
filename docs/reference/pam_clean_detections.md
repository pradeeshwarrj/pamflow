# Apply the cleaning rules to a detections table

Pure function (no file access), so it can be tested directly. Rules run
in a fixed order and each removed detection is kept with its reason.

## Usage

``` r
pam_clean_detections(det, pc, thresholds = NULL, seasons = NULL)
```

## Arguments

- det:

  A data.table of detections as returned by
  [`pam_assemble_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_assemble_detections.md),
  plus `file_duration_s`.

- pc:

  The `processing` section of the config: `min_confidence`,
  `species_whitelist`, `species_blacklist`, `date_range`,
  `drop_outside_deployment`, `max_overrun_s`, `merge_gap_s`.

- thresholds:

  Optional data.table with `scientific_name` and `threshold`; overrides
  `min_confidence` for those species.

- seasons:

  Optional data.table with `scientific_name`, `month_start`, `month_end`
  (1-12; start \> end wraps over the year end).

## Value

A list: `clean` (one row per event, with `confidence` = maximum,
`mean_confidence`, `n_windows`), `removed` (rows with `reason`), `steps`
(rule, n_before, n_removed).

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
det <- suppressMessages(pam_assemble_detections(ex$cfg))
#> Error: object 'ex' not found
det$file_duration_s <- 2    # length of the example recordings, in seconds
#> Error in det$file_duration_s <- 2: object of type 'closure' is not subsettable
cleaned <- pam_clean_detections(det, ex$cfg$processing)
#> Error in `:=`(detection_date, as.Date(format(detection_datetime, "%Y-%m-%d"))): Check that is.data.table(DT) == TRUE. Otherwise, `:=` is defined for use in j, once only and in particular ways. See help(":=", "data.table"). A common reason for this error is allocating a new column in `j` and using `<-` instead of `:=`; e.g., `DT[, new_col <- 1]` should be `DT[, new_col := 1]`. Another is using `:=` in a multi-statement `{...}` block; please use `:=` as the only statement in `j`.
cleaned$steps
#> Error: object 'cleaned' not found
cleaned$removed$reason
#> Error: object 'cleaned' not found
as.data.frame(cleaned$clean)[, c("species", "confidence", "n_windows", "start_time", "end_time")]
#> Error: object 'cleaned' not found
```
