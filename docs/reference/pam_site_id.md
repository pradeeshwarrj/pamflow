# Build site identifiers from the audio master table

Grids with a single deployment use the grid name alone (e.g. `"G1180"`).
Grids with multiple deployments get `"G0272_dep3"` to keep them
distinct.

## Usage

``` r
pam_site_id(master)
```

## Arguments

- master:

  A `data.table` with at least columns `grid` and `deployment_id`.

## Value

The input table (modified by reference) with a `site_id` column.
