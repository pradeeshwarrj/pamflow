# Benchmark Stage 3 detection speed at several worker counts

Runs
[`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)
on the same random sample of recordings once per worker count and
reports throughput, scaling efficiency, and an estimate for the whole
archive. Use it to choose `birdnet$workers` for your CPU, and as the
baseline to compare the new backend against.

## Usage

``` r
pam_birdnet_benchmark(
  cfg,
  workers = c(1L, 2L, 4L, 8L),
  n_files = 8L,
  seed = 1L,
  keep_runs = FALSE
)
```

## Arguments

- cfg:

  A `pam_config` object.

- workers:

  Integer vector of worker counts to test. Counts above the number of
  logical cores are dropped with a warning.

- n_files:

  Files per run. Each file takes about a minute for a 60-minute
  recording, so keep this small (default 8).

- seed:

  Seed for the file sample, identical for every run.

- keep_runs:

  If FALSE (default) the temporary detection folders are deleted
  afterwards.

## Value

A data.frame with one row per worker count: `workers`, `n_done`,
`n_failed`, `elapsed_s`, `files_per_hour`, `speedup`, `efficiency` and
`est_hours_full`. Also written to `<logs>/birdnet_benchmark.csv`.

## Details

The timing includes model loading in every worker, which is part of the
real cost of starting a run. Real runs amortize it over many files, so
the full-archive estimate is slightly pessimistic. Run on an otherwise
idle machine.

## Examples

``` r
if (FALSE) { # \dontrun{
cfg <- pam_load_config("config.yml")
pam_birdnet_benchmark(cfg, workers = c(1, 4, 8), n_files = 8)
} # }
```
