# Alias for pam_config_read

Alias for pam_config_read

## Usage

``` r
pam_load_config(path)
```

## Arguments

- path:

  Path to config file (required).

## Value

pam_config object.

## Examples

``` r
ex <- pam_example_project()
cfg <- pam_load_config(ex$config)
cfg$filenames$timezone
#> [1] "Asia/Kolkata"
```
