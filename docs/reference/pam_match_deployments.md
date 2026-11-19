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

## Examples

``` r
ex <- pam_example_project()
cfg <- ex$cfg
master <- pam_parse_filenames(ex$files, cfg$filenames$pattern, cfg$filenames$timezone)
master <- pam_match_deployments(master, pam_read_deployments(cfg))
as.data.frame(master)[, c("file_name", "deployment_id", "recorder", "in_deployment")]
#>                   file_name deployment_id recorder in_deployment
#> 1 G0059_20260405_183000.wav             1    SW010          TRUE
#> 2 G0059_20260405_183002.wav             1    SW010          TRUE
#> 3 G0059_20260405_183004.wav             1    SW010          TRUE
#> 4 G0110_20260406_060000.wav             2    SW012          TRUE
#> 5 G0110_20260406_060002.wav             2    SW012          TRUE
#> 6 G0110_20260406_060004.wav             2    SW012          TRUE
```
