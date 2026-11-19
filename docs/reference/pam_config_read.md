# Read and validate a pamflow configuration file

Read and validate a pamflow configuration file

## Usage

``` r
pam_config_read(path)
```

## Arguments

- path:

  Path to a YAML config file (required). There is no default: pamflow
  never looks for a configuration in the working directory.

## Value

A named list of class `pam_config`, with all paths resolved against
`paths$project_root`.

## Details

Missing keys fall back to the template defaults
(`system.file("extdata", "config_template.yml", package = "pamflow")`).
A relative `paths$project_root` is resolved against the folder that
holds the config file, not the working directory. The template uses
`".."`, so a config saved as `<project>/config/config.yml` points at
`<project>`.

## Examples

``` r
ex <- pam_example_project()
cfg <- pam_config_read(ex$config)
cfg$birdnet$run_id
#> [1] "run01"
cfg$paths$audio_standardized
#> [1] "C:/Users/ADMIN/AppData/Local/Temp/Rtmps7PvHY/pamflow_example_27a8f7d4cb0/data/standardized"
```
