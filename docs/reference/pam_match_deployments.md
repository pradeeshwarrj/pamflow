# Attach recorder and coordinates by matching grid and time window

Attach recorder and coordinates by matching grid and time window

## Usage

``` r
pam_match_deployments(master, dep)
```

## Arguments

- master:

  Master audio table with `file_path`, `grid`, `start_time`.

- dep:

  Table from
  [`pam_read_deployments()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_deployments.md).

## Value

`master` with `deployment_id`, `recorder`, `latitude`, `longitude` and
`in_deployment`. Recordings outside every deployment window of their
grid get NA and `in_deployment = FALSE` (not dropped).
