# Wilson score confidence interval for a proportion

Wilson score confidence interval for a proportion

## Usage

``` r
pam_wilson_ci(x, n, conf = 0.95)
```

## Arguments

- x:

  Number of successes (vector).

- n:

  Number of trials (vector, same length).

- conf:

  Confidence level.

## Value

A data.table with `low` and `high` (NA where `n` is 0).

## Examples

``` r
pam_wilson_ci(c(18, 5), c(25, 5))
#>          low      high
#>        <num>     <num>
#> 1: 0.5242339 0.8571615
#> 2: 0.5655175 1.0000000
```
