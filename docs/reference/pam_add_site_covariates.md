# Add site covariates to a count history

Attaches covariates, such as habitat or elevation, to histories that
were built without them. Rows are matched to the sites by name, so the
order of your table does not matter.

## Usage

``` r
pam_add_site_covariates(x, covariates, replace = FALSE)
```

## Arguments

- x:

  A `pam_count_history` or `pam_count_histories`.

- covariates:

  A data frame with a `site_id` column and one column per covariate.
  Every site of `x` needs a row; extra rows are ignored. Without a
  `site_id` column the table needs one row per site, in the order of the
  sites.

- replace:

  If `FALSE` (the default), a covariate that is already present is an
  error; if `TRUE`, it is replaced.

## Value

`x` with the covariates added.

## See also

[`pam_as_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_as_count_history.md),
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)

## Examples

``` r
counts <- matrix(c(0, 2, 5, 1, 0, 3), nrow = 3,
                 dimnames = list(c("site_a", "site_b", "site_c"), NULL))
hist <- pam_as_count_history(counts, species = "Example species")
covs <- data.frame(site_id = c("site_c", "site_a", "site_b"), canopy = c(0.9, 0.2, 0.5))
pam_add_site_covariates(hist, covs)$site_covariates
#>   site_id canopy
#> 1  site_a    0.2
#> 2  site_b    0.5
#> 3  site_c    0.9
```
