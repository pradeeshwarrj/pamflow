# Calculate daily recording effort per site

Splits recordings that cross midnight into two rows and sums hours per
site per calendar day. Days below `min_effort_h` are flagged as
insufficient.

## Usage

``` r
pam_daily_effort(master, tz = "Asia/Kolkata", min_effort_h = 2)
```

## Arguments

- master:

  A `data.table` with columns `site_id`, `start_time` (POSIXct),
  `duration_s`, `qc_pass`, `in_deployment`.

- tz:

  Character. Timezone for calendar dates.

- min_effort_h:

  Numeric. Minimum recording hours for an occasion to count as surveyed.

## Value

A `data.table` with columns `site_id`, `occasion_date` (Date),
`effort_hours`, `sufficient`.
