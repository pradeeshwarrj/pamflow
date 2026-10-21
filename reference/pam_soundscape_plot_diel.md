# Plot 24-Hour Diel Curves for Acoustic Indices

Generates line plots showing index values across 0-23 hours grouped by
grid site.

## Usage

``` r
pam_soundscape_plot_diel(hourly_dt, indices = NULL, out_dir = NULL, cfg = NULL)
```

## Arguments

- hourly_dt:

  `data.table`. Hourly summary from
  [`pam_soundscape_summarise`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_summarise.md).

- indices:

  Character vector. Acoustic indices to plot (e.g. `c("aci", "bio")`).
  If NULL, auto-detects available indices in `hourly_dt`.

- out_dir:

  Character. Optional output directory to save plot images.

- cfg:

  List. Optional configuration structure.

## Value

A list of ggplot objects.
