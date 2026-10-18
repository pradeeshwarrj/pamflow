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
