# Draw a validation round and add it to the sample file

Each call adds a new round to
`<detections>/<run_id>/validation/ validation_samples.csv`. Events drawn
in earlier rounds are never drawn again, so you can start small and add
more later.

## Usage

``` r
pam_validation_draw(
  cfg,
  run_id = cfg$birdnet$run_id,
  strategy = c("stratified", "random", "rare"),
  n = 100L,
  species = NULL,
  n_per_cell = cfg$validation$n_per_cell,
  pool = NULL
)
```

## Arguments

- cfg:

  A `pam_config` object (uses the `validation` section).

- run_id:

  Detection run.

- strategy:

  "stratified", "random" or "rare" (see
  [`pam_validation_sample()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_sample.md)).

- n:

  Events for the "random" strategy.

- species:

  Optional species restriction.

- n_per_cell:

  Events per species x band for "stratified". Defaults to
  `validation$n_per_cell`.

- pool:

  Optional pool from
  [`pam_validation_pool()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_pool.md)
  (computed if NULL).

## Value

Invisibly, the newly added rows.
