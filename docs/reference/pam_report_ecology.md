# Activity, richness and threshold tables for the report

Computes the tables of the ecological products from the cleaned
detections and the recording effort. Anything that cannot be computed
(for example when a stage has not been run) is left `NULL` and noted in
the log; it never stops the report.

## Usage

``` r
pam_report_ecology(cfg, run_id, data)
```

## Arguments

- cfg:

  A list from `pam_config_read`.

- run_id:

  Character. The detection run.

- data:

  The list built so far by `pam_report_data`.

## Value

A named list: `activity_hour` and `activity_week` (detections per
recorded hour by hour of day and by week), `richness_sites`,
`richness_estimates`, `richness_accumulation` (see `pam_richness`) and
`thresholds` (the species thresholds saved by `pam_species_thresholds`,
when present).
