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
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
pool <- suppressMessages(pam_validation_pool(ex$cfg))
bands <- unlist(ex$cfg$validation$bands)
# at most one event per species and confidence band
smp <- pam_validation_sample(pool, "stratified", bands = bands, n_per_cell = 1)
as.data.frame(smp)[, c("species", "confidence", "band")]
#>                                      species confidence      band
#> 1  Ducula nicobarica_Nicobar Imperial-Pigeon       0.71 0.70-1.00
#> 2 Psittacula longicauda_Long-tailed Parakeet       0.74 0.70-1.00
#> 3  Ducula nicobarica_Nicobar Imperial-Pigeon       0.64 0.50-0.70
#> 4         Gracula religiosa_Common Hill Myna       0.31 0.30-0.40
#> 5 Psittacula longicauda_Long-tailed Parakeet       0.66 0.50-0.70
#> 6         Gracula religiosa_Common Hill Myna       0.95 0.70-1.00
#> 7 Psittacula longicauda_Long-tailed Parakeet       0.45 0.40-0.50

# five events at random from the whole pool
rnd <- pam_validation_sample(pool, "random", bands = bands, n = 5, seed = 42)
nrow(rnd)
#> [1] 5
```
