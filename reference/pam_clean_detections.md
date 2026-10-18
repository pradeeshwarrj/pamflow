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
