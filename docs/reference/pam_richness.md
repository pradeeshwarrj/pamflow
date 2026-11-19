# Species richness and diversity per site and occasion

Turns the cleaned detections into species richness and diversity: for
every site and time bin, for every site over the whole survey, and
across sites (species accumulation and an estimate of how many species
were missed). The site table can be joined to habitat covariates by
`site_id` to study how richness varies with the environment.

## Usage

``` r
pam_richness(
  cfg,
  run_id = cfg$birdnet$run_id,
  bin_days = NULL,
  min_events = 1,
  abundance = c("counts", "presence"),
  q = c(1, 2),
  thresholds = NULL,
  species = NULL,
  min_effort_hours = NULL,
  write = FALSE
)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run (sub-folder of paths\$detections).

- bin_days:

  Length of a time bin in days. `NULL` uses
  `occupancy$occasion_length_days` (1 if not set).

- min_events:

  A species counts as present in a site and bin only when it has at
  least this many events there (a whole number, default 1). A higher
  number removes species known only from a lone, possibly false,
  detection, at the cost of missing rare species.

- abundance:

  How species are weighted in the Hill numbers: `"counts"` (the default;
  the number of events, an activity-based measure) or `"presence"`
  (every present species weighs the same, so only occurrence matters).

- q:

  Orders of the Hill numbers to compute besides richness (default 1 and
  2). Richness is the Hill number of order 0 and is always returned.

- thresholds:

  Optional per-species thresholds (a data frame, or the path of a CSV
  file, with `scientific_name` and `threshold`), for example from
  [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md).

- species:

  Optional species to keep (scientific names, common names or species
  labels). `NULL` keeps all.

- min_effort_hours:

  Minimum recorded hours for a bin to count as surveyed. `NULL` uses
  `occupancy$min_effort_hours` (2 if not set).

- write:

  If `TRUE`, also save the four tables to `<outputs>/<run_id>/` as
  `richness_occasions.csv`, `richness_sites.csv`,
  `species_accumulation.csv` and `richness_estimates.csv`.

## Value

A list of class `pam_richness`:

- `occasions`: one row per site and bin: `richness`, `hill_q<q>`
  columns, `n_events` (events of the species counted as present),
  `effort_hours`, `n_days`, `sufficient`. Bins below the minimum effort
  are kept and flagged.

- `sites`: one row per site, using only surveyed bins: `richness`,
  `hill_q<q>`, `n_events`, `n_occasions_surveyed`, `effort_hours`.

- `accumulation`: the expected number of species (`richness`) for
  `n_sites` = 1 to the number of surveyed sites.

- `estimates`: one row with the observed richness, the Chao2 estimate of
  the total and `completeness` (observed divided by estimated).

- `settings`: the choices that were used.

## Details

### Hill numbers

Hill numbers describe diversity as an effective number of species. Order
1 is the number of equally common species that gives the same Shannon
diversity, and order 2 the same for the Simpson index; larger orders
give more weight to the dominant species. With `abundance = "counts"` a
loud, vocal species weighs more than a quiet one, so the numbers
describe the acoustic community; use `"presence"` when only occurrence
matters. A bin with no species has richness 0 and `NA` for the other
orders.

### Accumulation and the estimate

Sites are the sampling units. `accumulation` is the exact expected
number of species found in `n` randomly chosen surveyed sites
(sample-based rarefaction), so curves from different projects can be
compared at the same number of sites. The Chao2 estimate uses how many
species were found in only one or two sites to estimate how many remain
undetected; treat it as a lower bound. A species with a false-positive
detection counts as present, so validated thresholds and `min_events`
matter for all of these numbers.

## See also

[`pam_plot_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_plot_richness.md),
[`pam_detection_table()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detection_table.md)

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
proc <- suppressMessages(pam_process_detections(ex$cfg))
rich <- suppressMessages(pam_richness(ex$cfg))
as.data.frame(rich$sites)[, c("site_id", "richness", "hill_q1", "hill_q2")]
#>   site_id richness  hill_q1  hill_q2
#> 1   G0059        2 1.960132 1.923077
#> 2   G0110        3 2.871746 2.777778
rich$estimates
#>    n_sites observed singletons doubletons chao2 completeness
#>      <int>    <int>      <int>      <int> <num>        <num>
#> 1:       2        3          1          2 3.125         0.96
# count a species only when it has at least two events in a bin
strict <- suppressMessages(pam_richness(ex$cfg, min_events = 2))
strict$sites$richness
#> [1] 2 2
```
