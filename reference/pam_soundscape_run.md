# Run Stage 2b Soundscape Analysis Pipeline

Run Stage 2b Soundscape Analysis Pipeline

## Usage

``` r
pam_soundscape_run(cfg, test_n = NULL)
```

## Arguments

- cfg:

  List. Parsed configuration structure from
  [`pam_config_read`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- test_n:

  Integer. Optional. Process only this many files (for tests).

## Value

A named list containing `raw`, `hourly`, `diel`, and `site_covariates`.
