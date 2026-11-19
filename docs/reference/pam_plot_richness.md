# Plot species richness

Plot species richness

## Usage

``` r
pam_plot_richness(x, type = c("accumulation", "sites"))
```

## Arguments

- x:

  The result of
  [`pam_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_richness.md).

- type:

  `"accumulation"` (the default) draws the expected species accumulation
  over sites with the Chao2 estimate as a dashed line; `"sites"` draws
  richness per site, highest first.

## Value

A ggplot object.

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
proc <- suppressMessages(pam_process_detections(ex$cfg))
rich <- suppressMessages(pam_richness(ex$cfg))
p <- pam_plot_richness(rich, "sites")
class(p)
#> [1] "ggplot2::ggplot" "ggplot"          "ggplot2::gg"     "S7_object"      
#> [5] "gg"             
```
