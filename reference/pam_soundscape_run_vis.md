# Run Stage 2c Soundscape Visualization Pipeline

Takes parsed config and optional previous Stage 2b results, loads
soundscape summary tables, exports diagnostic diel plots, and generates
an HTML report.

## Usage

``` r
pam_soundscape_run_vis(cfg, sc_results = NULL, generate_report = TRUE)
```

## Arguments

- cfg:

  List. Parsed configuration structure from
  [`pam_config_read`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- sc_results:

  List. Optional return object from
  [`pam_soundscape_run`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run.md).

- generate_report:

  Logical. If TRUE, compiles an HTML diagnostic report.

## Value

A named list of generated ggplot objects.
