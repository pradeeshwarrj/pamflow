# Build a detection history matrix for one species

Build a detection history matrix for one species

## Usage

``` r
pam_detection_matrix(events, effort, threshold = 0.5)
```

## Arguments

- events:

  A `data.table` of detections for one species with columns `site_id`,
  `occasion_date`, `confidence`.

- effort:

  A `data.table` from `pam_daily_effort`.

- threshold:

  Numeric. Minimum confidence for a detection to count.

## Value

A wide `data.table`: rows = sites, columns = site_id + one per occasion
date. Values: 1, 0, or NA.
