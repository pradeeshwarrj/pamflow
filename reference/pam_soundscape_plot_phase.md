# Plot Day vs. Night Comparisons for Acoustic Indices

Generates bar plots comparing mean values between Day and Night phases
per grid site.

## Usage

``` r
pam_soundscape_plot_phase(diel_dt, indices = NULL, out_dir = NULL, cfg = NULL)
```

## Arguments

- diel_dt:

  `data.table`. Diel summary from
  [`pam_soundscape_summarise`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_summarise.md).

- indices:

  Character vector. Acoustic indices to plot. If NULL, auto-detects.

- out_dir:

  Character. Optional output directory to save plot images.

- cfg:

  List. Optional configuration structure.

## Value

A list of ggplot objects.
