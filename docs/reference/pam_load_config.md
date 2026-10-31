# Alias for pam_config_read

Alias for pam_config_read

## Usage

``` r
pam_load_config(path = NULL)
```

## Arguments

- path:

  Path to config file.

## Value

pam_config object.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
cfg <- pam_load_config(ex$config)
#> Error in pam_load_config(ex$config): could not find function "pam_load_config"
cfg$filenames$timezone
#> Error: object 'cfg' not found
```
