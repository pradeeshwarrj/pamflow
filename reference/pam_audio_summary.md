# Summarize the audio master table

Summarize the audio master table

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
res <- suppressMessages(pam_scan_audio(ex$cfg))
summ <- pam_audio_summary(res$master, res$deployments)
summ$overall
#>    n_files n_grids total_hours n_invalid_name n_unreadable n_truncated n_short
#>      <int>   <int>       <num>          <int>        <int>       <int>   <int>
#> 1:       6       2 0.003333333              0            0           0       0
#>    n_duplicate n_gaps n_outside_deployment n_qc_pass
#>          <int>  <int>                <int>     <int>
#> 1:           0      0                    0         6
summ$per_grid
#>      grid n_files       hours median_file_min               first
#>    <char>   <int>       <num>           <num>              <POSc>
#> 1:  G0059       3 0.001666667      0.03333333 2026-04-05 18:30:00
#> 2:  G0110       3 0.001666667      0.03333333 2026-04-06 06:00:00
#>                   last n_gaps n_duplicate n_unreadable n_outside_deployment
#>                 <POSc>  <int>       <int>        <int>                <int>
#> 1: 2026-04-05 18:30:04      0           0            0                    0
#> 2: 2026-04-06 06:00:04      0           0            0                    0
```
