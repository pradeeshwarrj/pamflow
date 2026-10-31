# Count history of one species: detections per site and occasion

Counts the detections of one species in each site and occasion of a
project and returns them in the form that abundance models need: a
matrix with sites in rows and occasions in columns, `NA` where a site
was not surveyed, and matrices of recording effort and days. This is the
abundance counterpart of the detection histories of Stage 6.

## Usage

``` r
pam_count_history(
  cfg,
  species,
  run_id = cfg$birdnet$run_id,
  bin_days = NULL,
  count = c("events", "files"),
  thresholds = NULL,
  min_effort_hours = NULL,
  site_covariates = NULL
)
```

## Arguments

- cfg:

  A `pam_config` object.

- species:

  The species, given as scientific name, common name or species label
  (any capitalization). It must identify exactly one species.

- run_id:

  Detection run (sub-folder of paths\$detections).

- bin_days:

  Length of an occasion in days. `NULL` uses
  `occupancy$occasion_length_days` (1 if not set).

- count:

  What to count: `"events"` (the default; detected events, which Stage 4
  forms by merging overlapping BirdNET windows) or `"files"` (the number
  of recordings with at least one detection, which cannot exceed the
  number of recordings and is less affected by one animal calling for a
  long time).

- thresholds:

  Optional per-species thresholds (a data frame, or the path of a CSV
  file, with `scientific_name` and `threshold`), for example from
  [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md).

- min_effort_hours:

  Minimum recorded hours for an occasion to count as surveyed; others
  are `NA`. `NULL` uses `occupancy$min_effort_hours` (2 if not set).

- site_covariates:

  Optional data frame of site covariates with a `site_id` column (for
  example habitat or elevation). Every site must have a row.

## Value

An object of class `pam_count_history`: a list with

- `y`: integer matrix of counts (sites x occasions, `NA` = not
  surveyed);

- `effort`: matrix of recorded hours (`NA` where not surveyed);

- `day`: matrix of days since the first occasion;

- `site_covariates`: data frame with `site_id` and your covariates;

- `occasions`: the start and end day of each occasion;

- `species`, `count`: what was counted.

## Details

Sites and occasions follow Stage 6: occasions are blocks of `bin_days`
days starting on the first recorded day, shared by all sites, and only
occasions with recordings at some site appear. The counts are numbers of
detections, not numbers of animals, so models fitted to them give a
relative abundance index. Use
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)
to turn the history into input for abundance or occupancy models.

## See also

[`pam_as_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_as_count_history.md),
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
proc <- suppressMessages(pam_process_detections(ex$cfg))
#> Error: object 'ex' not found
sp <- unique(proc$clean$scientific_name)[1]
#> Error: object 'proc' not found
hist <- suppressMessages(pam_count_history(ex$cfg, species = sp))
#> Error in pam_count_history(ex$cfg, species = sp): could not find function "pam_count_history"
hist$y
#> Error in hist$y: object of type 'closure' is not subsettable
```
