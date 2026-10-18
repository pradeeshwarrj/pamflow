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
