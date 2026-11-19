# Validation report: precision tables written to disk

Imports the reviewed verdicts, computes
[`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md)
and writes `precision_by_cell.csv`, `precision_by_threshold.csv` and
`confusion_incorrect.csv` to `<detections>/<run_id>/validation/`.

## Usage

``` r
pam_validation_report(cfg, run_id = cfg$birdnet$run_id, pool = NULL)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run.

- pool:

  Optional pool from
  [`pam_validation_pool()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_pool.md).

## Value

The metrics list (see
[`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md)).

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
proc <- suppressMessages(pam_process_detections(ex$cfg))
new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 8))
val_dir <- file.path(ex$cfg$paths$detections, "run01", "validation")
# normally the review app writes this file; here the verdicts are made up
results <- data.frame(sample_id = new$sample_id,
                      verdict = rep_len(c("correct", "correct", "incorrect"), nrow(new)),
                      true_species = NA_character_, note = "", reviewer = "example",
                      reviewed_at = format(Sys.time()), stringsAsFactors = FALSE)
utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)
metrics <- suppressMessages(pam_validation_report(ex$cfg))
list.files(val_dir, pattern = "^precision")
#> [1] "precision_by_cell.csv"      "precision_by_threshold.csv"
```
