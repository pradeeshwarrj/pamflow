# Validate a pamflow configuration

Validate a pamflow configuration

## Usage

``` r
pam_config_validate(cfg)
```

## Arguments

- cfg:

  A config list.

## Value

`cfg`, invisibly. Aborts with a clear message on invalid values.

## Examples

``` r
ex <- pam_example_project()
pam_config_validate(ex$cfg)          # fine: returns the config invisibly

bad <- ex$cfg
bad$birdnet$min_confidence <- 2      # must be between 0 and 1
res <- try(pam_config_validate(bad), silent = TRUE)
inherits(res, "try-error")
#> [1] TRUE
```
