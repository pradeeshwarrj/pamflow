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

An occasion is a block of `occupancy$occasion_length_days` calendar days
(default 1, midnight to midnight in the project timezone). Blocks start
on the first day with any recording in the project and are the same for
every site. Occasions with less than `min_effort_hours` of recording in
total are coded NA (not surveyed). A detection counts in the occasion
that contains its date. Outputs that already exist are kept unless
`force = TRUE`, so rebuild after changing the occasion length.

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

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
proc <- suppressMessages(pam_process_detections(ex$cfg))   # occupancy builds on cleaned detections
#> Error: object 'ex' not found
occ <- suppressMessages(pam_build_occupancy(ex$cfg))
#> Error: object 'ex' not found
names(occ$histories)
#> Error: object 'occ' not found
occ$summary
#> Error: object 'occ' not found
# detection history of the first species: rows = sites, columns = days, NA = not surveyed
occ$histories[[1]]
#> Error: object 'occ' not found
```
