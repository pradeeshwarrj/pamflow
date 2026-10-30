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
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
det <- suppressMessages(pam_assemble_detections(ex$cfg))
det$file_duration_s <- 2    # length of the example recordings, in seconds
cleaned <- pam_clean_detections(det, ex$cfg$processing)
cleaned$steps
#>                                                    rule n_before n_removed
#>                                                  <char>    <int>     <int>
#> 1:                     invalid confidence or timestamps       19         0
#> 2:                             file not in master table       19         0
#> 3:                              beyond end of recording       19         1
#> 4:                            outside deployment window       18         0
#> 5:                           below confidence threshold       18         3
#> 6: merged overlapping windows into events (not removed)       15         5
cleaned$removed$reason
#> [1] "beyond end of recording"    "below confidence threshold"
#> [3] "below confidence threshold" "below confidence threshold"
as.data.frame(cleaned$clean)[, c("species", "confidence", "n_windows", "start_time", "end_time")]
#>                                       species confidence n_windows start_time
#> 1   Ducula nicobarica_Nicobar Imperial-Pigeon       0.71         1          0
#> 2  Psittacula longicauda_Long-tailed Parakeet       0.92         2          0
#> 3   Ducula nicobarica_Nicobar Imperial-Pigeon       0.64         1          0
#> 4  Psittacula longicauda_Long-tailed Parakeet       0.81         2          0
#> 5  Psittacula longicauda_Long-tailed Parakeet       0.66         2          0
#> 6   Ducula nicobarica_Nicobar Imperial-Pigeon       0.83         1          0
#> 7          Gracula religiosa_Common Hill Myna       0.95         1          0
#> 8  Psittacula longicauda_Long-tailed Parakeet       0.74         2          0
#> 9   Ducula nicobarica_Nicobar Imperial-Pigeon       0.58         1          0
#> 10 Psittacula longicauda_Long-tailed Parakeet       0.58         2          0
#>    end_time
#> 1       3.0
#> 2       4.5
#> 3       3.0
#> 4       4.5
#> 5       4.5
#> 6       3.0
#> 7       3.0
#> 8       4.5
#> 9       3.0
#> 10      4.5
```
