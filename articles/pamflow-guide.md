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
  min_effort_hours: 2
  min_detections: 10
```

To see every setting, copy the full template and edit it:

``` r
file.copy(system.file("extdata", "config_template.yml", package = "pamflow"),
          "config/config.yml")
```

**Key settings:**

| Setting                      | Meaning                                                        |
|------------------------------|----------------------------------------------------------------|
| `paths.project_root`         | Top-level project folder                                       |
| `filenames.timezone`         | Timezone of file names and deployment dates                    |
| `birdnet.model_dir`          | Folder with your custom BirdNET model                          |
| `birdnet.classifier_name`    | Model file name without `.tflite`                              |
| `birdnet.input`              | `"standardized"` (default) or `"filtered"` audio               |
| `birdnet.run_id`             | Name of this detection run                                     |
| `birdnet.workers`            | Worker processes for BirdNET; `null` = half the physical cores |
| `birdnet.min_confidence`     | Lowest BirdNET score kept (0.3 by default)                     |
| `processing.min_confidence`  | Confidence cut applied when cleaning (0.5 by default)          |
| `occupancy.min_effort_hours` | Min recording hours per day for occupancy                      |
| `occupancy.min_detections`   | Min detections for a species to get a history                  |

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
is one calendar day; days with less recording than
`occupancy.min_effort_hours` are coded NA (not surveyed). Species with
fewer than `occupancy.min_detections` detections get no history.

``` r
occ <- pam_build_occupancy(cfg)
occ$summary
names(occ$histories)
```

**Outputs:** `data/occupancy/run01/detection_history_<species>.csv`,
`occasion_covariates.csv`, `site_covariates.csv`,
`occupancy_summary.csv`.

Fitting occupancy models is not part of pamflow yet (it is planned as
Stage 7). In the meantime the histories can go straight into `unmarked`:

``` r
hist <- occ$histories[[1]]              # the first species
y <- as.matrix(hist[, -1])              # drop the site_id column
rownames(y) <- hist$site_id

umf <- unmarked::unmarkedFrameOccu(y = y)
fm <- unmarked::occu(~ 1 ~ 1, data = umf)
summary(fm)
```

------------------------------------------------------------------------

### Stage 8: Reports

Generates HTML, PDF and Excel reports with effort, detections,
validation and occupancy summaries. The formats come from
`report.formats` in the config (PDF needs a LaTeX installation).

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

| Function                                                                                                    | Stage | Purpose                                 |
|-------------------------------------------------------------------------------------------------------------|-------|-----------------------------------------|
| `pam_config_read(path)`                                                                                     | Setup | Read and validate the config            |
| [`pam_example_project()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_example_project.md)         | Setup | Build a small sample project to try     |
| `pam_birdnet_setup(component)`                                                                              | Setup | Create the BirdNET Python environment   |
| [`pam_birdnet_doctor()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_doctor.md)           | Setup | Check the machine and environments      |
| [`pam_standardization_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_standardization_app.md) | 0     | Standardization and triage app          |
| `pam_standardize(cfg)`                                                                                      | 0     | Standardize raw recordings              |
| `pam_scan_audio(cfg)`                                                                                       | 1     | Scan, QC, deployment matching           |
| `pam_filter_audio(cfg)`                                                                                     | 2     | High-pass filter via FFmpeg             |
| `pam_soundscape_run(cfg)`                                                                                   | 2b    | Soundscape indices                      |
| `pam_soundscape_run_vis(cfg)`                                                                               | 2c    | Soundscape plots and report             |
| `pam_detect(cfg)`                                                                                           | 3     | BirdNET detection (parallel, resumable) |
| `pam_birdnet_benchmark(cfg, workers)`                                                                       | 3     | Measure speed for several worker counts |
| [`pam_birdnet_cleanup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_cleanup.md)         | 3     | Stop leftover BirdNET worker processes  |
| `pam_assemble_detections(cfg)`                                                                              | 3, 4  | Combine detection batches               |
| `pam_process_detections(cfg)`                                                                               | 4     | Clean and merge detections              |
| `pam_validation_draw(cfg, strategy, n)`                                                                     | 5     | Draw a validation sample                |
| `pam_validation_export(cfg)`                                                                                | 5     | Export clips and spectrograms           |
| `pam_validate(cfg)`                                                                                         | 5     | Open the review app                     |
| `pam_validation_report(cfg)`                                                                                | 5     | Precision metrics                       |
| `pam_recall_draw(cfg, n)`                                                                                   | 5b    | Draw ground-truth segments              |
| `pam_recall_export(cfg)`                                                                                    | 5b    | Export segment clips and spectrograms   |
| `pam_annotate(cfg)`                                                                                         | 5b    | Open the annotation app                 |
| `pam_recall_report(cfg)`                                                                                    | 5b    | Recall, precision and F1                |
| `pam_build_occupancy(cfg)`                                                                                  | 6     | Detection histories                     |
| `pam_report(cfg)`                                                                                           | 8     | HTML, PDF and Excel reports             |

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
