# Summarise the audio master table

Summarise the audio master table

## Usage

``` r
pam_audio_summary(master, dep = NULL)
```

## Arguments

- master:

  Output of `pam_scan_audio()$master`.

- dep:

  Optional deployment table, to report grids/deployments with no match.

## Value

A list: `overall` (one-row data.table), `per_grid` (data.table),
`grids_without_deployment`, `deployments_without_audio`.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
summ <- pam_audio_summary(res$master, res$deployments)
#> Error: object 'res' not found
summ$overall
#> Error: object 'summ' not found
summ$per_grid
#> Error: object 'summ' not found
```
