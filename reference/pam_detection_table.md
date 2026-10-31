# Table of detections and recording effort per site, time bin and species

The shared starting point for activity patterns, richness and abundance
indices. It counts the cleaned detections (Stage 4) of every species in
every site and time bin, and puts the recording effort next to the
counts, so rates per recorded hour can be compared between sites that
were recorded for different lengths of time.

## Usage

``` r
pam_detection_table(
  cfg,
  run_id = cfg$birdnet$run_id,
  bin_days = NULL,
  thresholds = NULL,
  min_effort_hours = NULL,
  extra_by = character(),
  complete = TRUE,
  write = FALSE
)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run (sub-folder of paths\$detections).

- bin_days:

  Length of a time bin in days. `NULL` (the default) uses
  `occupancy$occasion_length_days` from the config (1 if not set); use 7
  for weekly bins.

- thresholds:

  Optional per-species thresholds: a data frame, or the path of a CSV
  file, with `scientific_name` and `threshold` (for example the result
  of
  [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md)).
  They are applied to the event confidence on top of Stage 4, so they
  can only remove more events. To keep events below the Stage 4 cut-off,
  lower it there and run Stage 4 again.

- min_effort_hours:

  Minimum recorded hours for a bin to count as surveyed. `NULL` uses
  `occupancy$min_effort_hours` (2 if not set).

- extra_by:

  Optional names of further detection columns to count by, for example a
  call type, if your detections have one.

- complete:

  If `TRUE` (the default), every surveyed site and bin gets a row for
  every species, with 0 where it was not detected. Set to `FALSE` for
  very large projects to keep only rows with detections.

- write:

  If `TRUE`, also save the table as
  `<outputs>/<run_id>/detection_table.csv`. Nothing is written by
  default.

## Value

A data.table with one row per site, bin and species (and `extra_by`
column): `site_id`, `bin_start`, `bin_end`, `species`,
`scientific_name`, `n_detections` (events), `n_files` (recordings with a
detection), `max_confidence`, `effort_hours`, `n_days`, `sufficient`
(the bin reached the minimum effort) and `detections_per_hour`. Bins
below the minimum effort are kept and flagged, not dropped. The bin
length and first bin day are stored in the attributes `bin_days` and
`origin`.

## Details

### Sites and effort

Sites follow the occupancy stage: the grid name, or `grid_deploymentId`
for grids with several deployments. Effort counts recordings that passed
QC and lie inside a deployment window. Detections that fall in a site
and bin with no effort (for example, in a recording that failed QC) are
dropped with a warning.

### Time bins

All bins start on the first day with any recording in the project, so a
bin covers the same dates at every site.

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
proc <- suppressMessages(pam_process_detections(ex$cfg))
tab <- suppressMessages(pam_detection_table(ex$cfg))
as.data.frame(tab)[, c("site_id", "bin_start", "species", "n_detections", "effort_hours")]
#>   site_id  bin_start                                    species n_detections
#> 1   G0059 2026-04-05  Ducula nicobarica_Nicobar Imperial-Pigeon            2
#> 2   G0059 2026-04-05         Gracula religiosa_Common Hill Myna            0
#> 3   G0059 2026-04-05 Psittacula longicauda_Long-tailed Parakeet            3
#> 4   G0110 2026-04-06  Ducula nicobarica_Nicobar Imperial-Pigeon            2
#> 5   G0110 2026-04-06         Gracula religiosa_Common Hill Myna            1
#> 6   G0110 2026-04-06 Psittacula longicauda_Long-tailed Parakeet            2
#>   effort_hours
#> 1  0.001666667
#> 2  0.001666667
#> 3  0.001666667
#> 4  0.001666667
#> 5  0.001666667
#> 6  0.001666667
# two-day bins instead of one-day bins
tab2 <- suppressMessages(pam_detection_table(ex$cfg, bin_days = 2))
unique(tab2$bin_start)
#> [1] "2026-04-05"
```
