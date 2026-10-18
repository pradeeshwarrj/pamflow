# Build occasion-level covariate table

Produces effort (hours) and Julian date (days since the first occasion
in the dataset) for each site-occasion.

## Usage

``` r
pam_occasion_covariates(effort)
```

## Arguments

- effort:

  A `data.table` from `pam_daily_effort`.

## Value

A `data.table` with columns `site_id`, `occasion_date`, `effort_hours`,
`sufficient`, `julian_date`.
