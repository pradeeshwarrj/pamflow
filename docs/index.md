# pamflow

**End-to-end Passive Acoustic Monitoring workflow for BirdNET**

`pamflow` takes you from raw field recordings to validated detection
histories and reports — with a single config file and a handful of
function calls.

## Features

- **Scan & QC** thousands of WAV files automatically
- **Batch BirdNET detection** with parallel workers and resume support
- **Clean & merge** overlapping detections into events
- **Interactive validation** via Shiny app with precision metrics
- **Occupancy detection histories** (daily 1/0 matrices per site per
  species)
- **HTML & Excel reports** summarising the full pipeline

## Prerequisites

| Software | Version | Notes                       |
|----------|---------|-----------------------------|
| R        | ≥ 4.3   | 64-bit                      |
| Python   | ≥ 3.9   | Required by BirdNET         |
| FFmpeg   | any     | Required for audio clipping |
| birdnetR | latest  | BirdNET model wrapper       |

Verify in R:

``` r

R.version.string           # ≥ 4.3
reticulate::py_available() # TRUE
system("ffmpeg -version")  # prints version
```

## Installation

``` r

# Install devtools if needed
install.packages("devtools")

# Install pamflow
devtools::install_github("pradeeshwarrj/pamflow")

# Install birdnetR
devtools::install_github("birdnet-team/birdnetR")
```

## Quick Start

### 1. Set up your project folder

``` R
MyProject/
├── audio/                  # WAV files in subfolders by grid
│   ├── G0059/
│   └── G0110/
├── metadata/
│   └── deployments.csv     # one row per deployment
├── config/
│   └── config.yml          # pipeline settings
└── ground_truth/           # optional, for recall estimation
```

### 2. Create `metadata/deployments.csv`

``` csv
grid,recorder,deployment_id,start_datetime,end_datetime
G0059,SW010,13,05-04-2026 18:30,08-04-2026 16:00
G0110,SW012,7,01-04-2026 06:00,10-04-2026 18:00
```

### 3. Create `config/config.yml`

``` yaml
project_name: "My PAM Project"
run_id: "run01"

paths:
  project_root: "E:/MyProject"
  audio: "audio"
  metadata: "metadata"
  deployments_file: "deployments.csv"
  detections: "data/detections"
  logs: "logs"
  reports: "reports"

birdnet:
  model: "BirdNET_GLOBAL_6K_V2.4_Model_FP32.tflite"
  labels: "BirdNet_v2_custom_Labels.txt"
  chunk_length_s: 3
  overlap_s: 0
  min_confidence: 0.5
  workers: 4
  run_id: "run01"

processing:
  input: "standardized"
  merge_gap_s: 3
  drop_outside_deployment: true
  min_confidence: 0.4

occupancy:
  occasion_length_days: 1
  min_effort_hours: 2
  min_detections: 5
  timezone: "Asia/Kolkata"

report:
  title: "PAM Report"
  format: "html"
```

### 4. Run the pipeline

``` r

library(pamflow)
cfg <- pam_config_read("E:/MyProject/config/config.yml")

# Stage 1: Scan audio and check deployments
pam_scan_audio(cfg)

# Stage 3: Run BirdNET detection (parallel, resumable)
pam_detect(cfg)

# Stage 4: Clean, filter, and merge detections
pam_process_detections(cfg)

# Stage 5: Validate a sample of detections
pam_validation_draw(cfg)
pam_validation_export(cfg)
pam_validation_app(cfg)          # opens Shiny app in browser

# After closing the app:
val  <- pam_validation_import(cfg)
pool <- pam_validation_pool(cfg)
pam_validation_metrics(val, pool, bands = c(0.5, 0.6, 0.7, 0.8, 0.9))

# Stage 6: Build occupancy detection histories
pam_build_occupancy(cfg)

# Stage 8: Generate reports
pam_report(cfg)
```

## Pipeline Stages

| Stage | Function | What it does |
|----|----|----|
| 1 | [`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md) | Inventories audio files, matches to deployments, flags QC issues |
| 3 | [`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md) | Runs BirdNET on all files in parallel batches; resumable |
| 4 | [`pam_process_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_process_detections.md) | Filters by confidence, deployment window, species; merges overlapping windows |
| 5 | [`pam_validation_draw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_draw.md) | Draws a stratified random sample for manual review |
| 5 | [`pam_validation_export()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_export.md) | Cuts short WAV clips around each sampled detection |
| 5 | `pam_validation_app()` | Shiny app to listen and confirm/reject species |
| 5 | [`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md) | Computes precision by species and confidence band |
| 6 | [`pam_build_occupancy()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_build_occupancy.md) | Builds daily detection matrices, effort, and site covariates |
| 8 | [`pam_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report.md) | Generates HTML report and Excel workbook |

> **Note:** All functions take `cfg` as their only required argument.
> The `run_id` is read from the config file.

## Outputs

``` R
MyProject/
├── data/
│   ├── master_table.csv
│   ├── detections/run01/
│   │   ├── batches/              # raw BirdNET output
│   │   └── processed/
│   │       ├── detections_clean.csv
│   │       ├── removed_detections.csv
│   │       └── processing_steps.csv
│   └── occupancy/run01/
│       ├── detection_matrices/
│       ├── effort.csv
│       └── site_covariates.csv
├── validation/run01/
│   ├── clips/
│   └── annotations.csv
├── reports/
│   ├── report_run01.html
│   └── report_run01.xlsx
└── logs/
```

## Configuration Reference

| Section | Key | Default | Description |
|----|----|----|----|
| `birdnet` | `workers` | 4 | Number of parallel CPU cores |
| `birdnet` | `min_confidence` | 0.5 | Minimum BirdNET score to keep |
| `birdnet` | `chunk_length_s` | 3 | Audio chunk length in seconds |
| `processing` | `input` | `"standardized"` | Use raw (`"standardized"`) or filtered audio |
| `processing` | `merge_gap_s` | 3 | Gap (seconds) for merging overlapping detections |
| `processing` | `drop_outside_deployment` | `true` | Remove detections outside deployment windows |
| `occupancy` | `occasion_length_days` | 1 | Days per sampling occasion |
| `occupancy` | `min_effort_hours` | 2 | Minimum recording hours per occasion |
| `occupancy` | `min_detections` | 5 | Minimum total detections to include a species |
| `occupancy` | `timezone` | `"Asia/Kolkata"` | Timezone for day boundaries |

## Resumability

If
[`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)
is interrupted (power loss, crash, etc.), simply run it again. It checks
for completed batches and picks up where it left off.

## License

MIT
