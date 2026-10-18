# Assemble raw detection batches into one detections table

Reads all batch files of a run, removes duplicates (from interrupted
runs), joins recording metadata from the Stage 1 master table, and
writes `<detections>/<run_id>/detections.csv`.

## Usage

``` r
pam_assemble_detections(cfg, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Name of the detection run (a sub-folder of paths\$detections).
  Defaults to birdnet\$run_id.

## Value

A data.table with `filename`, `species`, `scientific_name`,
`common_name`, `confidence`, `start_time` and `end_time` (seconds into
the recording), `site` (= grid), `grid`, `recorder`, `deployment_id`,
`in_deployment`, `recording_date`, `recording_start` and
`detection_datetime` (local time), `rel`.
