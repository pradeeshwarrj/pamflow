# Generate HTML Soundscape Diagnostic Report

Compiles an HTML diagnostic report summarizing soundscape indices, site
covariates, and diel visualizations using the template at
`inst/rmd/soundscape_report.Rmd`.

## Usage

``` r
pam_soundscape_report(cfg, sc_results = NULL, vis_results = NULL)
```

## Arguments

- cfg:

  List. Parsed configuration structure from
  [`pam_config_read`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- sc_results:

  List. Optional return object from
  [`pam_soundscape_run`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run.md).

- vis_results:

  List. Return object from
  [`pam_soundscape_plot_diel`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_plot_diel.md)
  /
  [`pam_soundscape_plot_phase`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_plot_phase.md).

## Value

Character. Path to the generated HTML report file.
