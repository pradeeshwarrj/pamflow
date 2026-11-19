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
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
proc <- suppressMessages(pam_process_detections(ex$cfg))
act <- suppressMessages(pam_activity(ex$cfg, by = "hour"))
p <- pam_plot_activity(act)
class(p)
#> [1] "ggplot2::ggplot" "ggplot"          "ggplot2::gg"     "S7_object"      
#> [5] "gg"             
```
