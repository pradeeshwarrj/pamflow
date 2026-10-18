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
