# Define seasons from the occasions of a history

Builds a table of seasons (one per calendar year or month) that cover
the occasions of a history, for use as the `seasons` argument of
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md).
Years or months without any occasion between the first and last are
included, so the spacing of seasons is kept.

## Usage

``` r
pam_define_seasons(history, by = c("year", "month"))
```

## Arguments

- history:

  A `pam_count_history` or `pam_count_histories` that has dates for its
  occasions (as built by
  [`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)).

- by:

  `"year"` (the default) or `"month"`.

## Value

A data frame with `season` (label), `start` and `end` (Dates).

## See also

[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)

## Examples

``` r
dates <- as.Date(c("2025-12-20", "2026-01-05", "2026-03-10"))
counts <- matrix(c(1, 0, 2, 0, 1, 1), nrow = 2, dimnames = list(c("a", "b"), NULL))
hist <- pam_as_count_history(
  counts, occasions = data.frame(occasion = 1:3, bin_start = dates, bin_end = dates))
pam_define_seasons(hist, by = "month")
#>    season      start        end
#> 1 2025-12 2025-12-01 2025-12-31
#> 2 2026-01 2026-01-01 2026-01-31
#> 3 2026-02 2026-02-01 2026-02-28
#> 4 2026-03 2026-03-01 2026-03-31
```
