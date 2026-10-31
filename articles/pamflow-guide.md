# PAM Workflow Guide

## 1. What Is `pamflow`?

`pamflow` is an R package that automates the pipeline for **passive
acoustic monitoring (PAM)** of birds (or any vocalizing animal). You
point it at a folder of field recordings and a spreadsheet of deployment
dates, and it can:

1.  Standardize raw recorder dumps into one clean folder structure
    (Stage 0)
2.  Read and quality-check every audio file and match it to its
    deployment (Stage 1)
3.  Optionally filter out low-frequency noise (Stage 2)
4.  Run a custom BirdNET classifier to detect species (Stage 3)
5.  Clean the raw detections: remove false positives, merge overlapping
    calls (Stage 4)
6.  Let you validate detector accuracy (precision, Stage 5) and estimate
    recall against annotated ground truth (Stage 5b)
7.  Build occupancy detection histories ready for statistical modelling
    (Stage 6)
8.  Generate HTML, PDF and Excel reports (Stage 8)

A second, independent workflow computes **soundscape indices** (ACI,
ADI, AEve, Bio, H, M, NDSI) with diel plots and an HTML report (Stages
2b and 2c). Training your own BirdNET classifier is a separate,
standalone tool (see the appendix).

Everything is **resumable** (if it crashes, it picks up where it left
off), **reproducible** (one config file controls the settings), and
**robust** (one bad file never kills the whole run).

------------------------------------------------------------------------

## 2. Who Is It For?

- **Ecologists** running acoustic surveys with autonomous recording
  units (ARUs)
- **Conservation biologists** monitoring bird communities across sites
- **Graduate students** who need a repeatable pipeline from raw
  recordings to occupancy models
- **Anyone** with a folder of `.wav` or `.flac` files and a deployment
  spreadsheet

You need basic familiarity with R and RStudio. No Python or command-line
experience is required: the package sets up and runs its own private
Python environment for BirdNET.

------------------------------------------------------------------------

## 3. What You Need Before Starting

### Hardware

- A Windows, Mac, or Linux computer (tested on Windows 11)
- At least 16 GB RAM (32 GB recommended for large datasets)
- Enough disk space for your recordings plus filtered copies (if
  filtering)
- BirdNET runs on the CPU. There is no GPU support on native Windows.

### Software

- **R** (\>= 4.3) and **RStudio**
- **FFmpeg** (free audio tool), needed for the filter stage and for
  exporting validation clips and spectrograms: `winget install ffmpeg`
  on Windows, `brew install ffmpeg` on Mac
- **uv** (creates the Python environment BirdNET runs in):
  `winget install --id astral-sh.uv` on Windows, see
  <https://docs.astral.sh/uv/> for other systems
- A **custom BirdNET classifier** (a `.tflite` model file and a
  `_Labels.txt` file). If you do not have one, the standalone training
  tool can make it (see the appendix).

### Data

- **Audio files**: `.wav` or `.flac` files, organized in subfolders (one
  folder per site/grid) and named with a consistent pattern such as
  `G0059_20260410_081553.wav` (grid, date, time). If your recorders name
  files differently, Stage 0 can rename and sort them for you.
- **Deployment spreadsheet**: a CSV with one row per deployment (see
  section 5.2).

------------------------------------------------------------------------

## 4. Installation

``` r
# Install devtools if you don't have it
install.packages("devtools")

# Install pamflow from GitHub
devtools::install_github("pradeeshwarrj/pamflow")

# Install additional suggested packages as needed
install.packages(c("rmarkdown", "openxlsx", "tinytex"))
tinytex::install_tinytex()  # only if you want PDF reports

# Create the Python environment BirdNET runs in (once; downloads TensorFlow, a few minutes)
library(pamflow)
pam_birdnet_setup("inference")
pam_birdnet_doctor()        # checks everything is in place
```

### Try it with the example project

Before using your own recordings, you can try the stages on a tiny
synthetic project.
[`pam_example_project()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_example_project.md)
builds one in a temporary folder (six short recordings, a deployment
sheet, a config and a small detections file) and needs no FFmpeg, Python
or internet connection.

``` r
library(pamflow)

ex <- pam_example_project()             # created in a temporary folder
res <- pam_scan_audio(ex$cfg)           # Stage 1: scan the recordings
res$summary$overall

out <- pam_process_detections(ex$cfg)   # Stage 4: clean the example detections
out$steps

act <- pam_activity(ex$cfg)             # activity by hour of day
rich <- pam_richness(ex$cfg)            # richness and diversity per site
rich$sites
```

`ex$root` is the project folder, so you can see what each stage writes.
Every help page has an example that uses this project (try
[`?pam_scan_audio`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md)).

------------------------------------------------------------------------

## 5. Project Setup

### 5.1 Create a project folder

Create a folder on your computer to hold all inputs and outputs. pamflow
creates the other folders (`data/standardized/`, `data/detections/`,
`data/occupancy/`, `logs/`, `reports/`, …) as the stages run:

    E:/my_pam_project/
    ├── data/
    │   └── raw/                   <- recorder dumps, untouched (Stage 0 input)
    ├── metadata/
    │   └── deployments.csv        <- your deployment spreadsheet
    ├── models/
    │   └── custom_classifier/     <- your .tflite model and _Labels.txt
    └── config/
        └── config.yml             <- your settings file

If your recordings are already named `G0059_20260410_081553.wav` and
sorted into one folder per grid, put them in `data/standardized/G0059/`
and skip Stage 0.

### 5.2 Create the deployment spreadsheet

One row per deployment. Columns are read **by position**, so keep this
order. Give dates as `dd-mm-yyyy` and times as `hh:mm`, and the grid as
a number (`59` becomes the grid `G0059`):

``` csv
deployment_id,recorder,grid,habitat,deployer,latitude,longitude,deploy_date,deploy_time,retrieve_date,retrieve_time
13,SW010,59,Forest,Asha,7.01,93.82,05-04-2026,18:30,08-04-2026,16:00
7,SW012,110,Plantation,Ravi,7.05,93.85,01-04-2026,06:00,10-04-2026,18:00
```

[`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md)
reports problems it finds in this sheet (a missing recovery date,
overlapping deployments of one grid, and so on) in
`outputs/deployment_issues.csv`.

### 5.3 Create the config file

Create `config/config.yml`. You only need to set what differs from the
defaults: every setting you leave out falls back to the template that
ships with pamflow. A minimal example:

``` yaml
paths:
  project_root: "E:/my_pam_project"      # all other paths are relative to this folder

filenames:
  timezone: "Asia/Kolkata"               # timezone of the file names and deployment dates

birdnet:
  run_id: "run01"
  model_dir: "models/custom_classifier"
  classifier_name: "CustomClassifier"    # files: <name>.tflite and <name>_Labels.txt
  min_confidence: 0.3
  workers: null                          # null = half of the physical cores

processing:
  min_confidence: 0.5

occupancy:
  run_id: "run01"
  occasion_length_days: 1
  min_effort_hours: 2
  min_detections: 10
```

To see every setting, copy the full template and edit it:

``` r
file.copy(system.file("extdata", "config_template.yml", package = "pamflow"),
          "config/config.yml")
```

**Key settings:**

| Setting                              | Meaning                                                                                                                                       |
|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| `paths.project_root`                 | Top-level project folder                                                                                                                      |
| `filenames.timezone`                 | Timezone of file names and deployment dates                                                                                                   |
| `birdnet.model_dir`                  | Folder with your custom BirdNET model                                                                                                         |
| `birdnet.classifier_name`            | Model file name without `.tflite`                                                                                                             |
| `birdnet.input`                      | `"standardized"` (default) or `"filtered"` audio                                                                                              |
| `birdnet.run_id`                     | Name of this detection run                                                                                                                    |
| `birdnet.workers`                    | Worker processes for BirdNET; `null` = half the physical cores                                                                                |
| `birdnet.min_confidence`             | Lowest BirdNET score kept (0.3 by default)                                                                                                    |
| `processing.min_confidence`          | Confidence cut applied when cleaning (0.5 by default)                                                                                         |
| `processing.species_thresholds_file` | CSV of per-species thresholds (see [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md)) |
| `occupancy.occasion_length_days`     | Days per occasion; also the default time bin of the Stage 7 and ecological functions                                                          |
| `occupancy.min_effort_hours`         | Min recording hours in an occasion for it to count as surveyed                                                                                |
| `occupancy.min_detections`           | Min detections for a species to get a history                                                                                                 |

------------------------------------------------------------------------

## 6. The Workflow: Stage by Stage

All stage functions take the configuration as their first argument. The
detection run is named by `birdnet$run_id` in the config; the functions
that work on a run take an optional `run_id` argument that defaults to
that value.

``` r
library(pamflow)
cfg <- pam_config_read("E:/my_pam_project/config/config.yml")
```

### Stage 0: Standardize Raw Recordings (Optional)

Raw recorder dumps are often messy: mixed formats, voice memos, field
notes, inconsistent file names. Stage 0 sorts them into one clean
structure and never changes the originals. It reads grid and time from
the file names, converts audio to FLAC or WAV at a common sample rate,
and sets voice memos (shorter than 60 s), non-audio files and unreadable
files aside in `data/isolated/`.

``` r
pam_standardization_app()   # point-and-click: Inspect, Convert and Log tabs

# or from code; dry_run = TRUE only plans what would happen
plan <- pam_standardize(cfg, dry_run = TRUE)
table(plan$action)
pam_standardize(cfg)
```

**Outputs:** `data/standardized/G0059/...`, `data/isolated/`, and
`standardization_log.csv`.

------------------------------------------------------------------------

### Stage 1: Scan Audio and Quality Control

Reads every `.wav` and `.flac` header, parses file names, matches
recordings to deployments, and flags quality issues (truncated files,
gaps, duplicates, recordings outside any deployment).

``` r
res <- pam_scan_audio(cfg)
res$summary$overall
```

**Outputs:** `metadata/audio_master.csv`,
`outputs/audio_summary_per_grid.csv`, `outputs/deployment_issues.csv`.
Header reading is cached, so a re-run only reads new files.

------------------------------------------------------------------------

### Stage 2: High-Pass Filter (Optional)

Applies a Butterworth high-pass filter via FFmpeg. Writes filtered
copies to a separate folder; originals are never modified. Skip it if
your classifier was trained on unfiltered audio. To detect on the
filtered copies, set `birdnet.input: "filtered"`.

``` r
pam_filter_audio(cfg)
```

**Outputs:** `data/filtered/` (mirrored folder tree). Resumable.

------------------------------------------------------------------------

### Stage 3: BirdNET Detection

Runs your custom classifier on every QC-passed recording, using several
worker processes. Resumable: if it crashes or you press Esc, rerunning
picks up where it stopped. BirdNET runs on the CPU in pamflow’s own
Python environment (created once with `pam_birdnet_setup("inference")`).

``` r
pam_detect(cfg)

# Quick test on a subset, in a separate run:
cfg_test <- cfg
cfg_test$birdnet$run_id <- "test"
pam_detect(cfg_test, sample_n = 20, seed = 42)
```

**How many workers?** Each worker holds its own copy of the model, so
more workers use more memory and cores. Keep `birdnet.workers` below
your physical core count so the computer stays usable. To measure what
is fastest on your machine and estimate the time for your whole archive:

``` r
pam_birdnet_benchmark(cfg, workers = c(2, 4, 8), n_files = 8)
```

If a run is interrupted and Python worker processes are left behind,
[`pam_birdnet_cleanup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_cleanup.md)
stops them.

**Outputs:** `data/detections/run01/batches/batch_*.csv`,
`file_results.csv`, `done.txt` (the checkpoint) and `run_settings_*.yml`
(the settings and BirdNET version used). `pam_assemble_detections(cfg)`
combines the batches into `detections.csv`; Stage 4 does this for you.

------------------------------------------------------------------------

### Stage 4: Clean Detections

Applies the rules in a fixed order: invalid values, files not in the
master table, windows past the end of a recording, outside the
deployment, species whitelist and blacklist, date range, species season,
confidence threshold (global or per species), and finally merges
overlapping windows into events. Every removed detection is kept with
the reason.

``` r
result <- pam_process_detections(cfg)
result$steps                 # what each rule removed
head(result$removed)
```

**Outputs:** `data/detections/run01/processed/detections_clean.csv`,
`removed_detections.csv`, `processing_steps.csv`.

------------------------------------------------------------------------

### Stage 5: Validation (Precision)

Draws a sample of detected events, exports a clip and spectrogram for
each, opens a Shiny app for you to review them, and calculates precision
per species and confidence band. The sample can be stratified (the
default), random, or restricted to rare species or chosen species. Each
call adds a new round and never repeats an event.

``` r
pam_validation_draw(cfg)                                 # stratified
pam_validation_draw(cfg, strategy = "random", n = 100)   # or a random round
pam_validation_export(cfg)                               # clips and spectrograms (needs FFmpeg)
pam_validate(cfg)                                        # opens the review app in your browser
pam_validation_report(cfg)
```

**Outputs** (in `data/detections/run01/validation/`):
`validation_samples.csv`, `validation_results.csv`, `clips/`,
`spectrograms/`, `precision_by_cell.csv`, `precision_by_threshold.csv`,
`confusion_incorrect.csv`.

------------------------------------------------------------------------

### Stage 5b: Ground Truth and Recall

Reviewing detections can only estimate precision. To estimate recall you
need recordings annotated independently of the detector. The package
draws random segments (60 s by default), you annotate them without
seeing the detections, and it calculates recall, precision and F1 at
several confidence thresholds.

``` r
pam_recall_draw(cfg, n = 20)     # draw 20 random segments
pam_recall_export(cfg)           # clips and spectrograms (needs FFmpeg)
pam_annotate(cfg)                # opens the annotation app in your browser
pam_recall_report(cfg)
```

**Outputs:** `data/validation/ground_truth/recall_segments.csv`,
`recall_annotations.csv`, and
`data/detections/run01/validation/recall_by_species_threshold.csv`.

------------------------------------------------------------------------

### Stage 6: Occupancy Detection Histories

Converts cleaned detections into wide-format matrices (sites x
occasions) with 1, 0 and NA values, one matrix per species. An occasion
is a block of `occupancy.occasion_length_days` days (default 1, one
calendar day), starting on the first recorded day and the same for every
site; occasions with less recording than `occupancy.min_effort_hours` in
total are coded NA (not surveyed). Species with fewer than
`occupancy.min_detections` detections get no history.

``` r
occ <- pam_build_occupancy(cfg)
occ$summary
names(occ$histories)
```

**Outputs:** `data/occupancy/run01/detection_history_<species>.csv`,
`occasion_covariates.csv`, `site_covariates.csv`,
`occupancy_summary.csv`.

pamflow does not fit occupancy models. The histories can go straight
into `unmarked`, or you can use Stage 7 below, which also handles
covariates, several species and several seasons:

``` r
hist <- occ$histories[[1]]              # the first species
y <- as.matrix(hist[, -1])              # drop the site_id column
rownames(y) <- hist$site_id

umf <- unmarked::unmarkedFrameOccu(y = y)
fm <- unmarked::occu(~ 1 ~ 1, data = umf)
summary(fm)
```

------------------------------------------------------------------------

### Stage 7: Input for Occupancy and Abundance Models

pamflow does **not** fit occupancy or abundance models. Stage 7 prepares
the input for the packages that do (`unmarked`, `ubms`, `spOccupancy` or
any other) and checks that it is consistent, so you can fit the models
yourself.

**1. A count history for one species.** Counts the detections of a
species in every site and occasion (a block of
`occupancy.occasion_length_days` days). The result has the counts, with
`NA` where a site was not surveyed, and matching matrices of recording
effort and days.

``` r
hist <- pam_count_history(cfg, species = "Gracula religiosa")
hist$y                                  # sites x occasions
hist$effort                             # recorded hours, same shape

# count recordings with a detection instead of detected events
hist_files <- pam_count_history(cfg, species = "Gracula religiosa", count = "files")
```

`species` can be a scientific name, a common name or the species label,
and must identify one species. Use `thresholds =` to apply per-species
thresholds (see the next section) and `min_effort_hours` to set how much
recording makes an occasion count as surveyed.

**2. Site covariates.** Attach habitat, elevation or any other site
covariate, either when you build the history (`site_covariates =`) or
later. Rows are matched by `site_id`, so the order of your table does
not matter, and every site needs a row.

``` r
covs <- read.csv("metadata/site_covariates_habitat.csv")   # needs a site_id column
hist <- pam_add_site_covariates(hist, covs)
```

**3. Model input.**
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)
turns the history into the three pieces that the modelling packages use:
the response `y`, the site covariates `siteCovs` and the observation
covariates `obsCovs` (`effort` and `day`).

``` r
x <- pam_model_input(hist)                          # counts, for abundance models
x <- pam_model_input(hist, binary = TRUE)           # detection / non-detection, for occupancy
x <- pam_model_input(hist, binary = TRUE, standardize = TRUE)   # covariates centred and scaled
pam_check_model_input(x)                            # dimensions, sites, values, missing data
```

Standardising keeps the centre and scale in `x$scaling`. Sites that were
never surveyed are left out (with a message). `dir = "path"` also writes
the pieces as CSV files for use outside R.

**4. Several species.**
[`pam_count_histories()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_histories.md)
builds the histories of all species (or those you name) in one pass, on
the same sites and occasions.
[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)
then gives `y` as a species x site x occasion array, the layout of
multi-species models.

``` r
hists <- pam_count_histories(cfg)                   # or species = c("...", "...")
x <- pam_model_input(hists, binary = TRUE)
dim(x$y)
```

**5. Several seasons.** For multi-season models, group the occasions
into seasons (primary periods).
[`pam_define_seasons()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_define_seasons.md)
makes one season per year or month; or give your own table with
`season`, `start` and `end` (dates). An occasion belongs to the season
that contains its first day. Seasonal covariates (for example rainfall)
go in `season_covariates`.

``` r
seasons <- pam_define_seasons(hist, by = "year")
x <- pam_model_input(hist, binary = TRUE, seasons = seasons,
                     season_covariates = data.frame(season = c("2025", "2026"),
                                                    rain = c(1210, 980)))
x$y                # sites x (seasons * occasions), for unmarked and ubms
x$y_array          # sites x seasons x occasions, for spOccupancy
x$num_primary      # number of seasons
```

Seasons with fewer occasions than the longest are padded with `NA`, and
seasons without any occasion are kept as `NA` so that the spacing is
right.

**6. Fit the model with your package.**

``` r
# unmarked: occupancy
x <- pam_model_input(hist, binary = TRUE)
umf <- unmarked::unmarkedFrameOccu(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs)
fit <- unmarked::occu(~ effort ~ canopy, data = umf)

# unmarked: N-mixture abundance index
x <- pam_model_input(hist)
umf <- unmarked::unmarkedFramePCount(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs)
fit <- unmarked::pcount(~ effort ~ canopy, data = umf, K = 100)

# spOccupancy: the same pieces under other names
data <- list(y = x$y, occ.covs = x$siteCovs, det.covs = x$obsCovs, coords = coords)
```

`ubms` uses the same `unmarkedFrame*` objects as `unmarked`. Check the
argument names in each package’s documentation.

**Counts are not animals.** The counts are numbers of detected events or
recordings. A model fitted to them gives a *relative abundance index*
for comparing sites, habitats and years for one species; it is not a
population size, and indices of different species cannot be compared.
N-mixture models also become slow and unstable when counts are large
(the upper bound `K` must exceed the highest count), so
`count = "files"` or shorter occasions are often better than raw event
counts.

------------------------------------------------------------------------

### Beyond Occupancy: Thresholds, Activity and Richness

The cleaned detections can answer more questions than occupancy. These
functions work on the Stage 4 output and use the recording effort, so
sites and periods that were recorded for different lengths of time can
be compared.

**Species thresholds.** BirdNET is more reliable for some species than
for others, so one confidence cut-off for all species is rarely right.
[`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md)
reads the Stage 5 validation and gives each species its own threshold:
the lowest confidence whose estimated precision is within a tolerance
(0.05) of that species’ own best, so no precision target is needed.
Species with too little validation get the global threshold (the
`reason` column says why), and you can override any species.

``` r
thr <- pam_species_thresholds(cfg)                       # one row per species
thr <- pam_species_thresholds(cfg, manual = data.frame(
  scientific_name = "Gracula religiosa", threshold = 0.8))
pam_species_thresholds(cfg, write = TRUE)                # saves species_thresholds.csv
```

Set `processing.species_thresholds_file` in the config to that file to
make Stages 4 and 6 use it, or pass `thresholds = thr` to the functions
below.

**Detections and effort per site, time bin and species.**
[`pam_detection_table()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detection_table.md)
is the base table for these products: detections, recordings with a
detection, recording hours and detections per hour, with zeros where a
species was not detected. The bin length defaults to
`occupancy.occasion_length_days`; use `bin_days = 7` for weeks.

``` r
tab <- pam_detection_table(cfg, bin_days = 7)
```

**Activity patterns.**
[`pam_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_activity.md)
gives detections per recorded hour by hour of the day, day, week or
month, pooled over sites or per site, for daily (diel) and seasonal
patterns. A recording that starts part way through an hour or crosses
midnight is split over the hours it covers.

``` r
act <- pam_activity(cfg, by = "hour")                    # diel pattern
act_week <- pam_activity(cfg, by = "week", by_site = TRUE)
pam_plot_activity(act)
pam_plot_activity(act, species = "Gracula religiosa", relative = TRUE)
```

The rate is an activity index: it depends on how often animals call, not
only on how many there are, so compare it between periods and sites for
the same species rather than between species.

**Richness and diversity.**
[`pam_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_richness.md)
gives species richness and Hill numbers for every site and time bin and
for every site over the whole survey, the expected species accumulation
over sites, and the Chao2 estimate of how many species were missed. The
site table can be joined to habitat covariates by `site_id`.

``` r
rich <- pam_richness(cfg)
rich$sites                  # richness and Hill numbers per site
rich$estimates              # observed richness, Chao2 estimate, completeness
pam_plot_richness(rich)     # accumulation curve
pam_plot_richness(rich, "sites")

# count a species only with at least 3 events in a bin; weight species equally
rich3 <- pam_richness(cfg, min_events = 3, abundance = "presence")
```

`min_events` removes species known only from a lone, possibly false,
detection, at the cost of missing rare species. With
`abundance = "counts"` (the default) the Hill numbers weight species by
their event counts, so they describe the acoustic community; use
`"presence"` when only occurrence matters. Species that are false
positives count as present in all of these numbers, so validated
thresholds matter.

------------------------------------------------------------------------

### Stage 8: Reports

Generates HTML, PDF and Excel reports with effort, detections, species
richness and diversity, activity patterns, validation (with the species
thresholds, when saved) and occupancy summaries. A section is left out
when its inputs are not there. The formats come from `report.formats` in
the config (PDF needs a LaTeX installation).

``` r
files <- pam_report(cfg)
files

pam_report(cfg, formats = "html")      # only the HTML report
```

------------------------------------------------------------------------

## 7. Soundscape Analysis (Workflow B)

The soundscape workflow is independent of BirdNET. After Stages 0 and 1,
it computes acoustic indices for each window of each recording, then
summarizes them by hour of day and by day and night, and draws the
plots.

``` r
sc <- pam_soundscape_run(cfg)            # Stage 2b: indices per 10-minute window
vis <- pam_soundscape_run_vis(cfg)       # Stage 2c: diel plots, day/night comparison, HTML report
```

The settings are in the `soundscape` section of the config: the window
length, the 500 Hz low-stop filter, which indices to compute and their
frequency ranges, and the day and night hours. This needs the
`soundecology` package.

**Outputs:** `data/soundscape/run01/` with `soundscape_raw.csv`,
`soundscape_hourly.csv`, `soundscape_diel_summary.csv`,
`soundscape_site_covariates.csv`, `plots/` and a standalone HTML report.

------------------------------------------------------------------------

## 8. Complete Function Reference

| Function                                                                                                    | Stage | Purpose                                      |
|-------------------------------------------------------------------------------------------------------------|-------|----------------------------------------------|
| `pam_config_read(path)`                                                                                     | Setup | Read and validate the config                 |
| [`pam_example_project()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_example_project.md)         | Setup | Build a small sample project to try          |
| `pam_birdnet_setup(component)`                                                                              | Setup | Create the BirdNET Python environment        |
| [`pam_birdnet_doctor()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_doctor.md)           | Setup | Check the machine and environments           |
| [`pam_standardization_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_standardization_app.md) | 0     | Standardization and triage app               |
| `pam_standardize(cfg)`                                                                                      | 0     | Standardize raw recordings                   |
| `pam_scan_audio(cfg)`                                                                                       | 1     | Scan, QC, deployment matching                |
| `pam_filter_audio(cfg)`                                                                                     | 2     | High-pass filter via FFmpeg                  |
| `pam_soundscape_run(cfg)`                                                                                   | 2b    | Soundscape indices                           |
| `pam_soundscape_run_vis(cfg)`                                                                               | 2c    | Soundscape plots and report                  |
| `pam_detect(cfg)`                                                                                           | 3     | BirdNET detection (parallel, resumable)      |
| `pam_birdnet_benchmark(cfg, workers)`                                                                       | 3     | Measure speed for several worker counts      |
| [`pam_birdnet_cleanup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_cleanup.md)         | 3     | Stop leftover BirdNET worker processes       |
| `pam_assemble_detections(cfg)`                                                                              | 3, 4  | Combine detection batches                    |
| `pam_process_detections(cfg)`                                                                               | 4     | Clean and merge detections                   |
| `pam_validation_draw(cfg, strategy, n)`                                                                     | 5     | Draw a validation sample                     |
| `pam_validation_export(cfg)`                                                                                | 5     | Export clips and spectrograms                |
| `pam_validate(cfg)`                                                                                         | 5     | Open the review app                          |
| `pam_validation_report(cfg)`                                                                                | 5     | Precision metrics                            |
| `pam_recall_draw(cfg, n)`                                                                                   | 5b    | Draw ground-truth segments                   |
| `pam_recall_export(cfg)`                                                                                    | 5b    | Export segment clips and spectrograms        |
| `pam_annotate(cfg)`                                                                                         | 5b    | Open the annotation app                      |
| `pam_recall_report(cfg)`                                                                                    | 5b    | Recall, precision and F1                     |
| `pam_build_occupancy(cfg)`                                                                                  | 6     | Detection histories                          |
| `pam_count_history(cfg, species)`                                                                           | 7     | Counts of one species by site and occasion   |
| `pam_count_histories(cfg)`                                                                                  | 7     | Counts of many species on a shared grid      |
| `pam_as_count_history(y)`                                                                                   | 7     | Use your own counts                          |
| `pam_add_site_covariates(x, covs)`                                                                          | 7     | Attach site covariates by site               |
| `pam_define_seasons(x)`                                                                                     | 7     | Seasons by year or month                     |
| `pam_model_input(x)`                                                                                        | 7     | Input for unmarked, ubms or spOccupancy      |
| `pam_check_model_input(x)`                                                                                  | 7     | Check the input before fitting               |
| `pam_species_thresholds(cfg)`                                                                               | Eco   | One confidence threshold per species         |
| `pam_detection_table(cfg)`                                                                                  | Eco   | Detections and effort per site, bin, species |
| `pam_activity(cfg)`                                                                                         | Eco   | Detections per recorded hour, by period      |
| `pam_plot_activity(act)`                                                                                    | Eco   | Plot activity patterns                       |
| `pam_richness(cfg)`                                                                                         | Eco   | Richness, Hill numbers, accumulation, Chao2  |
| `pam_plot_richness(rich)`                                                                                   | Eco   | Plot richness                                |
| `pam_report(cfg)`                                                                                           | 8     | HTML, PDF and Excel reports                  |
| `pam_audio_history(cfg)`                                                                                    | Any   | Follow audio files across the stages         |

Every function has a help page with an example you can run on
[`pam_example_project()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_example_project.md).

------------------------------------------------------------------------

## 9. Typical Workflow

``` r
library(pamflow)
cfg <- pam_config_read("E:/my_pam_project/config/config.yml")

pam_standardize(cfg)               # Stage 0 (skip if your audio is already standardized)
pam_scan_audio(cfg)                # Stage 1
pam_detect(cfg)                    # Stage 3
pam_process_detections(cfg)        # Stage 4

pam_validation_draw(cfg)           # Stage 5
pam_validation_export(cfg)
pam_validate(cfg)
pam_validation_report(cfg)

occ <- pam_build_occupancy(cfg)    # Stage 6
occ$summary

hist <- pam_count_history(cfg, species = "Gracula religiosa")   # Stage 7
x <- pam_model_input(hist, binary = TRUE)   # input for unmarked, ubms, spOccupancy

act <- pam_activity(cfg)           # activity patterns
rich <- pam_richness(cfg)          # richness and diversity

pam_report(cfg)                    # Stage 8
```

------------------------------------------------------------------------

## 10. Frequently Asked Questions

**Q: Can I resume a crashed detection run?** Yes. Rerun
`pam_detect(cfg)`. It reads the checkpoint and skips completed files. If
you pressed Esc or the computer crashed and Python processes are still
running, call
[`pam_birdnet_cleanup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_cleanup.md)
first.

**Q: How do I change the confidence threshold?** Edit
`processing.min_confidence` in your config (or give per-species
thresholds in a CSV, see `processing.species_thresholds_file`) and rerun
Stage 4. No need to rerun Stage 3.

**Q: Does pamflow fit occupancy or abundance models?** No. It prepares
the input (Stage 7) and checks it; you fit the models with `unmarked`,
`ubms`, `spOccupancy` or another package. This keeps pamflow free of
modelling dependencies and lets you choose the model.

**Q: How do I use per-species confidence thresholds?** Run
`pam_species_thresholds(cfg, write = TRUE)` after validation, then set
`processing.species_thresholds_file` to the saved file and rerun Stage
4, or pass `thresholds =` to
[`pam_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_activity.md),
[`pam_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_richness.md)
or
[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md).

**Q: How do I see what happened to one recording?**
`pam_audio_history(cfg, file = "G0059_20260405_183000.wav")` lists what
each stage recorded about it.

**Q: Can I add more species to the model later?** Yes. Replace the model
files (or train a new classifier, see the appendix), set a new
`birdnet.run_id` in the config, and rerun Stage 3.

**Q: What if my file names don’t match the default pattern?** Either let
Stage 0 rename them, or change `filenames.pattern` in the config using
named capture groups: `(?<grid>...)`, `(?<date>...)`, `(?<time>...)`.

**Q: My deployment sheet gives an error or odd dates.** Check the column
order and the `dd-mm-yyyy` and `hh:mm` formats (section 5.2), and write
the grid as a number. `outputs/deployment_issues.csv` lists the rows
that could not be read.

**Q: How much disk space do I need?** Original audio, plus filtered
copies (if filtering), plus the detection CSVs. For 1 TB of audio,
budget about 2.1 TB in total.

**Q: Can I use a GPU?** Not on native Windows: TensorFlow no longer
supports it there, so BirdNET runs on the CPU.

**Q: Can I run this on a Mac or Linux?** Yes. Install FFmpeg and `uv`
with your package manager (for example `brew install ffmpeg uv`).

------------------------------------------------------------------------

## Appendix: Training a custom BirdNET classifier (standalone, optional)

Training is **not part of the workflow**. No stage calls it and the
workflow does not need it; it only produces the model files that Stage 3
uses.

``` r
# Once: create the training environment (downloads BirdNET-Analyzer and TensorFlow)
pam_birdnet_setup("training")

pam_train_app()                         # point-and-click, like the Analyzer GUI

# or from code
pam_birdnet_train_prepare("E:/clips")   # checks classes and file counts
res <- pam_birdnet_train("E:/clips", "E:/models/MyModel", test_data = "E:/clips_test")
res$evaluation$classes                  # per-class precision, recall, F1, AUPRC, AUROC
```

The training folder has one sub-folder of audio clips per class (plus a
background class such as `noise`). With a separate `test_data` folder
you get per-class results; without one, scores come from clips held out
of the training folder and are optimistic.
[`pam_birdnet_train_repeat()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_repeat.md)
trains the same classifier several times to show how much the scores
vary.

To use the trained model, point the config at it:

``` yaml
birdnet:
  model_dir: "E:/models"
  classifier_name: "MyModel"
```

| Function                                                                                                        | Purpose                                        |
|-----------------------------------------------------------------------------------------------------------------|------------------------------------------------|
| [`pam_train_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_train_app.md)                         | Training app (progress, curves, results, runs) |
| [`pam_birdnet_train_prepare()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_prepare.md) | Check a training folder before training        |
| [`pam_birdnet_train()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train.md)                 | Train one classifier                           |
| [`pam_birdnet_train_repeat()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_repeat.md)   | Train several times and summarise the scores   |
| [`pam_birdnet_train_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_metrics.md) | Read the scores from a training log            |
