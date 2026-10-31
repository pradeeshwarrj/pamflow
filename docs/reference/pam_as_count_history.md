# Make a count history from your own counts

Wraps a matrix of counts (sites in rows, occasions in columns) so that
it can be prepared for modeling by
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md).
[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)
builds the same object from the detections of a project; use this
function when the counts come from somewhere else.

## Usage

``` r
pam_as_count_history(
  y,
  site_covariates = NULL,
  effort = NULL,
  day = NULL,
  occasions = NULL,
  species = NA_character_,
  count = "events"
)
```

## Arguments

- y:

  A matrix of whole-number counts, sites in rows and occasions in
  columns, with `NA` where a site was not surveyed. Row names are the
  site identifiers (made up if missing).

- site_covariates:

  Optional data frame of site covariates. With a `site_id` column the
  rows are matched to the sites by name, otherwise there must be one row
  per site in the same order.

- effort:

  Optional matrix (same shape as `y`) of recording hours per site and
  occasion, usable as a detection covariate named `effort`.

- day:

  Optional matrix (same shape as `y`) of days since the first occasion,
  usable as a detection covariate named `day`. By default the occasion
  number minus one.

- occasions:

  Optional data frame describing the occasions, one row per column of
  `y`.

- species:

  Name of the species, for labeling.

- count:

  What the counts are: `"events"` or `"files"` (for labeling).

## Value

An object of class `pam_count_history`: a list with `y`, `effort`,
`day`, `site_covariates`, `occasions`, `species` and `count`.

## See also

[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md),
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)

## Examples

``` r
counts <- matrix(c(0, 2, 5, 1, 0, 3, 4, 0, 2, 1, 1, 0), nrow = 3,
                 dimnames = list(c("site_a", "site_b", "site_c"), NULL))
hist <- pam_as_count_history(counts, species = "Example species")
#> Error in pam_as_count_history(counts, species = "Example species"): could not find function "pam_as_count_history"
hist$y
#> Error in hist$y: object of type 'closure' is not subsettable
```
