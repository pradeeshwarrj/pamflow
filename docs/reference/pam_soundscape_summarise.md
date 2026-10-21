# Summarize Soundscape Indices into Hourly, Diel, and Site Covariate Metrics

Summarize Soundscape Indices into Hourly, Diel, and Site Covariate
Metrics

## Usage

``` r
pam_soundscape_summarise(raw_dt, master_dt, cfg = NULL)
```

## Arguments

- raw_dt:

  `data.table`. Raw window soundscape indices.

- master_dt:

  `data.table`. Master metadata from Stage 1.

- cfg:

  List. Parsed configuration structure.

## Value

A named list containing `hourly`, `diel`, and `site_covariates`.
