# Check model input before fitting

Runs a set of consistency checks on the output of
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md):
dimensions, site and occasion matching, the values of the response and
missing values. Use it after editing the input by hand, or to confirm
that input is ready before it is passed to a modelling package.

## Usage

``` r
pam_check_model_input(x, error = TRUE)
```

## Arguments

- x:

  A `pam_model_input`.

- error:

  If `TRUE` (the default), a failed check is an error that names the
  failed checks. If `FALSE`, the table of checks is returned whatever
  the result.

## Value

A data.table with one row per check: `check`, `passed` and `detail`
(invisibly when everything passed).

## Details

The checks are: the response is a numeric array; sites are unique and
match the site covariates (count and names); observation covariates have
the shape of the response; the response holds whole numbers of 0 or more
(0 or 1 for detection / non-detection); every site was surveyed at least
once; observation covariates are present wherever the response is; and,
for seasons, the number of seasons and occasions match the response.

## See also

[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)

## Examples

``` r
counts <- matrix(c(0, 2, 5, 1, 0, 3), nrow = 3, dimnames = list(c("a", "b", "c"), NULL))
x <- pam_model_input(pam_as_count_history(counts))
#> Error in pam_model_input(pam_as_count_history(counts)): could not find function "pam_model_input"
pam_check_model_input(x)
#> Error in pam_check_model_input(x): could not find function "pam_check_model_input"
```
