# Build occupancy detection histories for all qualifying species

Reads cleaned detections and the audio master, constructs per-species
detection history matrices (wide format), occasion covariates (effort
and Julian date), and site covariates. Writes everything to
`data/occupancy/<run_id>/`.

## Usage

``` r
pam_build_occupancy(cfg, run_id = cfg$occupancy$run_id, force = FALSE)
```

## Arguments

- cfg:

  A list from `pam_config_read`.

- run_id:

  Character. The detection run to use. Defaults to
  `cfg$occupancy$run_id`.

- force:

  Logical. Rebuild even if outputs exist? Default FALSE.

## Value

Invisibly, a list with `histories` (named list of wide matrices),
`effort`, `site_covariates`, `summary`.

## Details

### Occasion definition

Each occasion is one calendar day (midnight to midnight in the project
timezone). Days with less than `min_effort_hours` of recording are coded
NA (not surveyed).

### Site definition

Grids with a single deployment use the grid name as the site ID. Grids
with multiple deployments get `grid_deployment_id`.

### Confidence thresholds

If `processing.species_thresholds_file` points to a CSV with columns
`scientific_name` and `threshold`, those per-species values are used.
Species not listed fall back to `processing.min_confidence`.

### Species filter

Only species with at least `occupancy.min_detections` total detections
(after the confidence cut) get a history matrix.
