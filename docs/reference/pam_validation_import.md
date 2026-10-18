# Join the reviewed verdicts to the sample table

Join the reviewed verdicts to the sample table

## Usage

``` r
pam_validation_import(cfg, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run.

## Value

A data.table: one row per reviewed sample, with `verdict` ("correct",
"incorrect", "unsure"), `true_species`, `note`, `reviewer`,
`reviewed_at` added to the sample columns.
