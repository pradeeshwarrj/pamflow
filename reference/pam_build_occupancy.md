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

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
proc <- suppressMessages(pam_process_detections(ex$cfg))   # occupancy builds on cleaned detections
occ <- suppressMessages(pam_build_occupancy(ex$cfg))
names(occ$histories)
#> [1] "Ducula nicobarica_Nicobar Imperial-Pigeon" 
#> [2] "Psittacula longicauda_Long-tailed Parakeet"
#> [3] "Gracula religiosa_Common Hill Myna"        
occ$summary
#>                                       species threshold_used n_sites
#>                                        <char>          <num>   <int>
#> 1:  Ducula nicobarica_Nicobar Imperial-Pigeon            0.5       2
#> 2: Psittacula longicauda_Long-tailed Parakeet            0.5       2
#> 3:         Gracula religiosa_Common Hill Myna            0.5       2
#>    n_occasions n_sites_detected naive_occupancy
#>          <int>            <int>           <num>
#> 1:           2                2             1.0
#> 2:           2                2             1.0
#> 3:           2                1             0.5
# detection history of the first species: rows = sites, columns = days, NA = not surveyed
occ$histories[[1]]
#> Key: <site_id>
#>    site_id 2026-04-05 2026-04-06
#>     <char>      <int>      <int>
#> 1:   G0059          1         NA
#> 2:   G0110         NA          1
```
