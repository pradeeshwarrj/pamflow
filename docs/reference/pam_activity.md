# Activity patterns: detections per recorded hour

Counts the cleaned detections of each species in every hour of the day,
day, week or month, and divides them by the time that was recorded in
that period. Because the division uses recording effort, periods and
sites that were recorded for different lengths of time can be compared.
Use it for daily (diel) activity patterns and for seasonal patterns such
as migration or breeding timing.

## Usage

``` r
pam_activity(
  cfg,
  run_id = cfg$birdnet$run_id,
  by = c("hour", "day", "week", "month"),
  by_site = FALSE,
  species = NULL,
  thresholds = NULL,
  min_effort_hours = 0,
  write = FALSE
)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run (sub-folder of paths\$detections).

- by:

  The period: `"hour"` (hour of the day, pooled over all dates),
  `"day"`, `"week"` (weeks start on Monday) or `"month"`.

- by_site:

  If `FALSE` (the default), sites are pooled: the rate is all detections
  divided by all recorded hours. If `TRUE`, one row per site.

- species:

  Optional species to keep: scientific names, common names or species
  labels, in any capitalization. `NULL` keeps all.

- thresholds:

  Optional per-species thresholds (a data frame, or the path of a CSV
  file, with `scientific_name` and `threshold`), for example from
  [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md).
  They are applied on top of Stage 4 and can only remove more events.

- min_effort_hours:

  Periods with less recorded time than this get no rate (`NA`) and
  `sufficient = FALSE`. Default 0 keeps every period with any recording.

- write:

  If `TRUE`, also save the table as
  `<outputs>/<run_id>/activity_<by>.csv`. Nothing is written by default.

## Value

A data.table with one row per period and species (and per site when
`by_site = TRUE`): `period` (hour 0-23, or the first day of the period),
`species`, `scientific_name`, `n_detections`, `effort_hours`,
`detections_per_hour`, `relative_activity` (the rate divided by the
species' highest rate, so 1 marks its peak), `sufficient` and, for
pooled tables, `n_sites_surveyed` and `n_sites_detected`. Periods with
recordings but no detection get 0. Periods with no recording have no
row. The choices are stored in the attributes `by` and `by_site`.

## Details

### What the rate means

`detections_per_hour` is the number of detected events (Stage 4 merges
overlapping BirdNET windows into events) per hour of recording. It is an
activity index: it depends on how often and how loudly animals call, not
only on how many are present, and on the confidence thresholds used.
Compare it between periods and sites for the same species, and avoid
comparing raw rates between species.

### Time of day

Hours are local clock hours of the project time zone. A recording is
split over the hours it covers, so effort is exact for recordings that
start part way through an hour or cross midnight.

## See also

[`pam_plot_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_plot_activity.md),
[`pam_detection_table()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detection_table.md)

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
proc <- suppressMessages(pam_process_detections(ex$cfg))
#> Error: object 'ex' not found
act <- suppressMessages(pam_activity(ex$cfg, by = "hour"))
#> Error in pam_activity(ex$cfg, by = "hour"): could not find function "pam_activity"
as.data.frame(act)[, c("period", "species", "n_detections", "detections_per_hour")]
#> Error: object 'act' not found
# one row per site and day
day <- suppressMessages(pam_activity(ex$cfg, by = "day", by_site = TRUE))
#> Error in pam_activity(ex$cfg, by = "day", by_site = TRUE): could not find function "pam_activity"
head(as.data.frame(day)[, c("site_id", "period", "species", "n_detections")], 4)
#> Error: object 'day' not found
```
