# Stage 4: clean the detections of a run

Assembles the run's detections, applies
[`pam_clean_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_clean_detections.md)
using the `processing` settings of the config, and writes the results to
`<detections>/<run_id>/processed/`.

## Usage

``` r
pam_process_detections(cfg, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run (sub-folder of paths\$detections). Defaults to
  birdnet\$run_id.

## Value

A list: `clean`, `removed`, `steps` (see
[`pam_clean_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_clean_detections.md)).

## Details

Writes `detections_clean.csv`, `removed_detections.csv` (with the reason
for each removal) and `processing_steps.csv`. Times are written as
local-time text. Run with
`pam_run_stage("04_process", pam_process_detections, cfg, run_id = "...")`.
