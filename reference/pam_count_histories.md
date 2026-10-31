# Count histories of many species at once

Builds a
[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)
for every species (or the species you name) in one pass over the
detections. All histories share the same sites, occasions, effort and
site covariates, which is what multi-species models need.

## Usage

``` r
pam_count_histories(
  cfg,
  species = NULL,
  run_id = cfg$birdnet$run_id,
  bin_days = NULL,
  count = c("events", "files"),
  thresholds = NULL,
  min_effort_hours = NULL,
  site_covariates = NULL,
  min_total = 1
)
```

## Arguments

- cfg:

  A `pam_config` object.

- species:

  Optional species to include: scientific names, common names or species
  labels (any capitalisation). `NULL` (the default) takes every species
  in the detections.

- run_id:

  Detection run (sub-folder of paths\$detections).

- bin_days:

  Length of an occasion in days. `NULL` uses
  `occupancy$occasion_length_days` (1 if not set).

- count:

  What to count: `"events"` (the default; detected events, which Stage 4
  forms by merging overlapping BirdNET windows) or `"files"` (the number
  of recordings with at least one detection, which cannot exceed the
  number of recordings and is less affected by one animal calling for a
  long time).

- thresholds:

  Optional per-species thresholds (a data frame, or the path of a CSV
  file, with `scientific_name` and `threshold`), for example from
  [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md).

- min_effort_hours:

  Minimum recorded hours for an occasion to count as surveyed; others
  are `NA`. `NULL` uses `occupancy$min_effort_hours` (2 if not set).

- site_covariates:

  Optional data frame of site covariates with a `site_id` column (for
  example habitat or elevation). Every site must have a row.

- min_total:

  Species with fewer than this many counts in total, over all sites and
  occasions, are left out (default 1, which drops species with no count
  after the thresholds).

## Value

An object of class `pam_count_histories`: a named list (one
[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)
per species, named by species label).

## Details

Pass the result to
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)
to get a species by site by occasion array for multi-species models, or
take one species with `histories[["label"]]`.

## See also

[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md),
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
proc <- suppressMessages(pam_process_detections(ex$cfg))
hists <- suppressMessages(pam_count_histories(ex$cfg))
names(hists)
#> [1] "Ducula nicobarica_Nicobar Imperial-Pigeon" 
#> [2] "Gracula religiosa_Common Hill Myna"        
#> [3] "Psittacula longicauda_Long-tailed Parakeet"
```
