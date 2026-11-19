# List problems in the deployment table

List problems in the deployment table

## Usage

``` r
pam_check_deployments(dep)
```

## Arguments

- dep:

  Table from
  [`pam_read_deployments()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_deployments.md).

## Value

A data.table `deployment_id`, `grid`, `issue` (empty if none). Issues:
unparseable start, missing/unparseable recovery, recovery before
deployment, assumed recovery time, and overlap with another deployment
of the same grid.

## Examples

``` r
ex <- pam_example_project()
dep <- pam_read_deployments(ex$cfg)
pam_check_deployments(dep)   # no rows: the example deployments are consistent
#> Empty data.table (0 rows and 3 cols): deployment_id,grid,issue
```
