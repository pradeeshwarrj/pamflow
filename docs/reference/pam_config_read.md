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
#> Error in pam_example_project(): could not find function "pam_example_project"
cfg <- pam_config_read(ex$config)
#> Error: object 'ex' not found
cfg$birdnet$run_id
#> Error: object 'cfg' not found
cfg$paths$audio_standardized
#> Error: object 'cfg' not found
```
