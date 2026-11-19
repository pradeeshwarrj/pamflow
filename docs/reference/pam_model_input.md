# Prepare a count history as input for abundance and occupancy models

Turns a count history into the pieces that site-occupancy and abundance
models use: the response `y` (sites by occasions), the site covariates
`siteCovs` and the observation covariates `obsCovs`. It handles one
species or several, and one season or several. pamflow does not fit
these models; use the prepared input with the package you prefer, such
as `unmarked`, `ubms` or `spOccupancy`.

## Usage

``` r
pam_model_input(
  history,
  binary = FALSE,
  standardize = FALSE,
  drop_unsurveyed = TRUE,
  seasons = NULL,
  season_covariates = NULL,
  dir = NULL
)
```

## Arguments

- history:

  A `pam_count_history` from
  [`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)
  or
  [`pam_as_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_as_count_history.md),
  or a `pam_count_histories` from
  [`pam_count_histories()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_histories.md).

- binary:

  If `FALSE` (the default), `y` holds the counts, as used by N-mixture
  (abundance) models. If `TRUE`, `y` is detection (1) or non-detection
  (0), as used by occupancy and Royle-Nichols models.

- standardize:

  If `TRUE`, numeric covariates are centered and scaled (mean 0,
  standard deviation 1), which helps models converge. The center and
  scale are returned in `scaling` so that new data can be treated the
  same way. Default `FALSE`: covariates are returned as they are.

- drop_unsurveyed:

  If `TRUE` (the default), sites with no surveyed occasion are left out
  of every piece, because model functions cannot use them.

- seasons:

  Optional data frame with the columns `season` (a name), `start` and
  `end` (Dates) that groups the occasions into seasons (primary periods)
  for multi-season models; see
  [`pam_define_seasons()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_define_seasons.md).
  An occasion belongs to the season that contains its first day.
  Occasions outside every season are left out; seasons with fewer
  occasions than the longest are padded with `NA`.

- season_covariates:

  Optional data frame with a `season` column and one column per
  covariate that changes between seasons but not between sites (for
  example rainfall or year); needs `seasons`.

- dir:

  Optional folder. If given, the pieces are also written there as CSV
  files, for use outside R. Nothing is written by default.

## Value

An object of class `pam_model_input`. For one species and no seasons it
is a list with

- `y`: integer matrix, sites in rows and occasions in columns, `NA`
  where a site was not surveyed;

- `siteCovs`: data frame of site covariates, one row per site (row names
  are the site identifiers); `NULL` if there are none;

- `obsCovs`: named list of matrices shaped like `y`: `effort` (recorded
  hours, when the history has it) and `day` (days since the first
  occasion);

- `site_ids`, `species`, `count`, `binary`;

- `scaling`: center and scale of every standardized covariate.

With several species, `y` is an array (species, sites, occasions) and
`species` lists the species. With `seasons`, the list also has

- `y_array`: sites x seasons x occasions within season (with a leading
  species dimension for several species); `y` is then the wide matrix
  sites x (seasons \* occasions) for one species, and `NULL` for
  several;

- `obsCovs` (wide matrices) and `obsCovs_array` (arrays), shaped like
  `y` and `y_array`;

- `num_primary` (number of seasons), `n_secondary` (occasions per
  season, including padding), `seasons` (with the number of occasions
  found) and `occasion_map` (which original occasion went where);

- with `season_covariates`: `yearlySiteCovs` (data frame, one row per
  site and season, sites first) and `yearlySiteCovs_matrices` (sites x
  seasons).

The layout of `y` is stored in `attr(x, "layout")`;
[`pam_check_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_check_model_input.md)
uses it.

## Details

### Using the result with unmarked or ubms

Both build their data frames from these pieces:

    x <- pam_model_input(history)
    umf <- unmarked::unmarkedFramePCount(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs)
    fit <- unmarked::pcount(~ effort ~ canopy, data = umf, K = 100)

    x <- pam_model_input(history, binary = TRUE)
    umf <- unmarked::unmarkedFrameOccu(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs)
    fit <- unmarked::occu(~ effort ~ canopy, data = umf)

    # several seasons
    x <- pam_model_input(history, binary = TRUE, seasons = pam_define_seasons(history))
    umf <- unmarked::unmarkedMultFrame(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs,
                                       numPrimary = x$num_primary)

The detection formula (before the second `~`) may use the observation
covariates `effort` and `day` and any site covariate; the other formula
uses site covariates. `ubms` takes the same `unmarkedFrame*` objects.

### Using the result with spOccupancy

`spOccupancy` expects a list with the response, the occupancy covariates
and the detection covariates, which are the same pieces under other
names (check the argument names against its documentation):

    x <- pam_model_input(history, binary = TRUE)          # one species
    data <- list(y = x$y, occ.covs = x$siteCovs, det.covs = x$obsCovs,
                 coords = coords)   # coords: your site coordinates, same row order

    x <- pam_model_input(histories, binary = TRUE)        # several species
    data <- list(y = x$y, occ.covs = x$siteCovs, det.covs = x$obsCovs, coords = coords)

For several species `y` has the species first (species x sites x
occasions). With seasons use `y_array` and `obsCovs_array`. `x$site_ids`
gives the site order.

### About counts

Counts are numbers of detections, not numbers of animals. A model fitted
to them gives a relative abundance index, not a population size.
N-mixture models also slow down when counts are large (the upper bound
`K` must exceed the highest count), so `count = "files"` in
[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)
or shorter occasions are often better than raw event counts.

Site covariates with missing values cannot be used by model functions; a
warning names them.

## See also

[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md),
[`pam_count_histories()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_histories.md),
[`pam_define_seasons()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_define_seasons.md),
[`pam_check_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_check_model_input.md)

## Examples

``` r
counts <- matrix(c(0, 2, 5, 1, 0, 3, 4, 0, 2, 1, 1, 0), nrow = 3,
                 dimnames = list(c("site_a", "site_b", "site_c"), NULL))
hist <- pam_as_count_history(counts, site_covariates = data.frame(canopy = c(0.2, 0.5, 0.9)),
                             effort = matrix(24, 3, 4), species = "Example species")
x <- pam_model_input(hist)
x$y
#>        1 2 3 4
#> site_a 0 1 4 1
#> site_b 2 0 0 1
#> site_c 5 3 2 0
x$siteCovs
#>        canopy
#> site_a    0.2
#> site_b    0.5
#> site_c    0.9
names(x$obsCovs)
#> [1] "effort" "day"   
# detection / non-detection instead of counts, covariates standardized
pam_model_input(hist, binary = TRUE, standardize = TRUE)$y
#>        1 2 3 4
#> site_a 0 1 1 1
#> site_b 1 0 0 1
#> site_c 1 1 1 0
```
