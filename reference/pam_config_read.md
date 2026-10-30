# Read and validate a pamflow configuration file

Read and validate a pamflow configuration file

## Usage

``` r
pam_config_read(path = NULL)
```

## Arguments

- path:

  Path to a YAML config file. If missing, looks for "config/config.yml"
  or loads default template.

## Value

A named list of class `pam_config`, with all paths resolved against
`paths$project_root`.

## Details

Missing keys fall back to the template defaults.

## Examples

``` r
ex <- pam_example_project()
cfg <- pam_config_read(ex$config)
cfg$birdnet$run_id
#> [1] "run01"
cfg$paths$audio_standardized
#> [1] "/tmp/Rtmpefifs1/pamflow_example_1c577c81f718/data/standardized"
```
