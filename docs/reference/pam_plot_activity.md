# Plot activity patterns

Draws the result of
[`pam_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_activity.md)
with one panel per species: bars for the hour of the day, a line for
days, weeks and months.

## Usage

``` r
pam_plot_activity(activity, species = NULL, relative = FALSE)
```

## Arguments

- activity:

  A pooled table from `pam_activity(by_site = FALSE)`.

- species:

  Optional species (scientific or common name as in the table) to plot;
  `NULL` plots all.

- relative:

  If `TRUE`, plot `relative_activity` (1 = the species' peak) instead of
  detections per recorded hour, so species can be compared by timing.

## Value

A ggplot object.

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
p <- pam_plot_activity(act)
#> Error in pam_plot_activity(act): could not find function "pam_plot_activity"
class(p)
#> Error: object 'p' not found
```
