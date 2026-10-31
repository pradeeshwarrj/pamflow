# Read and clean the deployment sheet

Read and clean the deployment sheet

## Usage

``` r
pam_read_deployments(cfg)
```

## Arguments

- cfg:

  A `pam_config` object. Uses `paths$deployment_sheet`, the
  `deployments` settings and `filenames$timezone`.

## Value

A data.table with the configured columns plus `deploy_start`,
`retrieve_end` (POSIXct, local time) and `recovery_time_missing`. `grid`
is converted to the filename format (0059 -\> "G0059").

## Details

Columns are matched by position (`deployments$columns`); everything is
read as text so leading zeros survive. Repairs applied (and nothing
else): "/" and "." date separators become "-", "." in times becomes ":",
seconds are dropped, a blank recovery time becomes
`deployments$default_recovery_time`, and a recovery year before 2000
(e.g. 15-04-0206) is replaced by the deployment year. Rows that still
can't be parsed get NA and are listed by
[`pam_check_deployments()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_check_deployments.md).

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
dep <- pam_read_deployments(ex$cfg)
#> Error: object 'ex' not found
as.data.frame(dep)[, c("deployment_id", "grid", "deploy_start", "retrieve_end")]
#> Error: object 'dep' not found
```
