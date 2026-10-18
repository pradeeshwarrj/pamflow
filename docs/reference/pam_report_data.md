# Gather report data from all completed stages

Reads outputs from Stages 1, 4, 5, 5b and 6 and returns a single list
suitable for passing to the report template or Excel writer. Missing
stages are returned as NULL with a warning.

## Usage

``` r
pam_report_data(cfg, run_id)
```

## Arguments

- cfg:

  A list from `pam_config_read`.

- run_id:

  Character. The detection run to report on.

## Value

A named list with elements `effort`, `detections`, `species_counts`,
`hourly_pattern`, `precision`, `recall`, `occupancy`.
