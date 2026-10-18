# Read and validate a pamflow configuration file

Read and validate a pamflow configuration file

## Usage

``` r
pam_config_read(path)
```

## Arguments

- path:

  Path to a YAML config file.

## Value

A named list of class `pam_config`, with all paths resolved against
`paths$project_root`.

## Details

Missing keys fall back to the template defaults.

## Examples

``` r
if (FALSE) { # \dontrun{
cfg <- pam_config_read("config/config.yml")
} # }
```
