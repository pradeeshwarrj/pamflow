# Draw a validation sample from a pool of events

Pure function (no file access). Strategies:

- `"stratified"`: up to `n_per_cell` events per species x confidence
  band; restrict to some species with `species`.

- `"random"`: `n` events drawn at random from the whole pool (or from
  `species`).

- `"rare"`: species with at most `rare_max_events` events in the pool;
  up to `rare_n` events of each.

## Usage

``` r
pam_validation_sample(
  pool,
  strategy = c("stratified", "random", "rare"),
  bands,
  n_per_cell = 25L,
  n = 100L,
  species = NULL,
  rare_max_events = 30L,
  rare_n = 50L,
  seed = 1L,
  exclude_ids = character()
)
```

## Arguments

- pool:

  Events from
  [`pam_validation_pool()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_pool.md).

- strategy:

  One of "stratified", "random", "rare".

- bands:

  Increasing confidence band edges.

- n_per_cell, n, rare_max_events, rare_n:

  See above.

- species:

  Optional names (scientific, common or "Scientific_Common").

- seed:

  Random seed.

- exclude_ids:

  `event_id`s already sampled; never drawn again.

## Value

A data.table: the sampled rows with `band_idx` and `band`.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
pool <- suppressMessages(pam_validation_pool(ex$cfg))
#> Error: object 'ex' not found
bands <- unlist(ex$cfg$validation$bands)
#> Error: object 'ex' not found
# at most one event per species and confidence band
smp <- pam_validation_sample(pool, "stratified", bands = bands, n_per_cell = 1)
#> Error: object 'pool' not found
as.data.frame(smp)[, c("species", "confidence", "band")]
#> Error: object 'smp' not found

# five events at random from the whole pool
rnd <- pam_validation_sample(pool, "random", bands = bands, n = 5, seed = 42)
#> Error: object 'pool' not found
nrow(rnd)
#> Error: object 'rnd' not found
```
