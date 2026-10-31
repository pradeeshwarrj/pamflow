# Recall report for a detection run

Compares a run's detections with the ground-truth annotations and writes
`recall_by_species_threshold.csv` to
`<detections>/<run_id>/validation/`. Only annotated segments from
recordings the run processed are used.

## Usage

``` r
pam_recall_report(
  cfg,
  run_id = cfg$birdnet$run_id,
  thresholds = NULL,
  pool = NULL
)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run.

- thresholds:

  Confidence thresholds. Default: the band edges of `validation$bands`
  except the last.

- pool:

  Optional pool from
  [`pam_validation_pool()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_pool.md).

## Value

A list: `metrics` (see
[`pam_recall_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_metrics.md)),
`n_segments`, `n_no_species`, `n_other_only`.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
segments <- suppressMessages(pam_recall_draw(ex$cfg, n = 12, run_id = NULL))
#> Error: object 'ex' not found
gt_dir <- file.path(ex$cfg$paths$validation, "ground_truth")
#> Error: object 'ex' not found
# normally the annotation app writes this file; here the parakeet is "heard" everywhere
truth <- data.frame(segment_id = segments$segment_id,
                    present = "Psittacula longicauda_Long-tailed Parakeet",
                    possible = "", other = "", none_audible = FALSE, note = "",
                    reviewer = "example", reviewed_at = format(Sys.time()),
                    stringsAsFactors = FALSE)
#> Error in segments$segment_id: object of type 'closure' is not subsettable
utils::write.csv(truth, file.path(gt_dir, "recall_annotations.csv"), row.names = FALSE)
#> Error in eval(expr, p): object 'truth' not found
rep <- suppressMessages(pam_recall_report(ex$cfg))
#> Error: object 'ex' not found
rep$n_segments
#> Error in rep$n_segments: object of type 'special' is not subsettable
```
