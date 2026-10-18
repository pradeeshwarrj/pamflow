# Build site-level covariate table

Extracts site metadata from the master table and adds total effort.
Currently includes grid, deployment dates, coordinates (if present), and
total recorded hours.

## Usage

``` r
pam_site_covariates(master, effort)
```

## Arguments

- master:

  A `data.table` with deployment and QC columns.

- effort:

  A `data.table` from `pam_daily_effort`.

## Value

A `data.table` with one row per site.
