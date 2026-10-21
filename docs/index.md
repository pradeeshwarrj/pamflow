# pamflow

**End-to-end Passive Acoustic Monitoring workflow**

`pamflow` takes you from raw field recordings to ecological useful data
— with a single config file and a handful of function calls.

`Workflow A (Species Detection & Occupancy)`: Run BirdNET, clean & merge
detections, perform stratified validation with Shiny, build daily site
occupancy matrices, and compile executive reports.

`Workflow B (Soundscape Analysis)`: Compute core acoustic indices (ACI,
ADI, AEve, Bio, H, M, NDSI) following Bradfer-Lawrence et al. (2019)
with 500 Hz low-stop filtering, 1-minute memory-safe sub-chunking,
24-hour diel profiles, and automated HTML diagnostic reports.

## Features

- **Scan & QC** thousands of WAV files automatically
- **Batch BirdNET detection** with parallel workers and resume support
- **Clean & merge** overlapping detections into events
- **Interactive validation** via Shiny app with precision metrics
- **Occupancy detection histories** (daily 1/0 matrices per site per
  species)
- **Ecoacoustic Soundscape Indices** Dynamic computation of ACI, ADI,
  AEve, Bio, H, M, and NDSI.
- **Soundscape Visualizations & HTML Reports** 24-hour diel profiles,
  Day vs. Night comparisons, sitecovariate tables, and standalone HTML
  reports.

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

processing:
  input: "standardized"
  merge_gap_s: 3
  drop_outside_deployment: true
  min_confidence: 0.4

soundscape:
  enabled: true
  window_mins: 10
  low_stop_hz: 500
  acoustic_indices:
    ACI:
    ADI:
      fmin: 0
      fmax: 24000
      bin_step: 1000
    AEve:
    Bio:
      flim: [2000, 11000]
    H:
    M:
    NDSI:
      anthro_range: [1000, 2000]
      bio_range: [2000, 11000]
  day_hours: [6, 17]
  night_hours: [18, 5]

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

## Workflow A: Detection & Occupancy Pipeline

``` r

library(pamflow)
cfg <- pam_config_read("E:/MyProject/config/config.yaml")

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

# Stage 8: Generate species detection reports
pam_report(cfg)
```

## Workflow B: Soundscape Analysis Pipeline

``` r

library(pamflow)
cfg <- pam_config_read("E:/MyProject/config/config.yaml")

# Stage 1: Scan audio and check deployments
pam_scan_audio(cfg)

# Stage 2b: Calculate soundscape indices (ACI, Bio, NDSI, etc.)
sc_results <- pam_soundscape_run(cfg)

# Stage 2c: Generate 24-hour diel plots, Day/Night comparisons & HTML Report
vis_results <- pam_soundscape_run_vis(cfg)
```

## Pipeline Stages

| Workflow | Stage | Function | What it does |
|----|----|----|----|
| Both | 1 | [`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md) | Inventories audio files, matches to deployments, flags QC issues |
| Both | 2 | [`pam_filter_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_filter_audio.md) | High-pass filter on the QC checked files; can be customized |
| B | 2b | [`pam_soundscape_run()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run.md) | Computes soundscape indices per 10-min window with 500Hz high-pass filter |
| B | 2c | [`pam_soundscape_run_vis()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run_vis.md) | Plots 24-hour diel profiles, Day/Night comparisons, and generates HTML report |
| A | 3 | [`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md) | Runs BirdNET on all files in parallel batches; resumable |
| A | 4 | [`pam_process_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_process_detections.md) | Filters by confidence, deployment window, species; merges overlapping windows |
| A | 5 | [`pam_validation_draw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_draw.md) | Draws a stratified random sample for manual review |
| A | 5 | [`pam_validation_export()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_export.md) | Cuts short WAV clips around each sampled detection |
| A | 5 | `pam_validation_app()` | Shiny app to listen and confirm/reject species |
| A | 5 | [`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md) | Computes precision by species and confidence band |
| A | 6 | [`pam_build_occupancy()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_build_occupancy.md) | Builds daily detection matrices, effort, and site covariates |
| A | 8 | [`pam_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report.md) | Generates HTML report and Excel workbook |

> **Note:** All functions take `cfg` as their only required argument.
> The `run_id` is read from the config file.

## Outputs

``` R
MyProject/
├── data/
│   ├── master_table.csv
│   ├── soundscape/run01/
│   │   ├── soundscape_raw.csv
│   │   ├── soundscape_hourly.csv
│   │   ├── soundscape_diel_summary.csv
│   │   ├── soundscape_site_covariates.csv
│   │   ├── plots/
│   │   │   ├── diel_hourly_aci.png
│   │   │   └── diel_phase_aci.png
│   │   └── reports/
│   │       └── Soundscape_Report_run01.html
│   ├── detections/run01/
│   │   ├── batches/
│   │   └── processed/
│   └── occupancy/run01/
│       ├── detection_matrices/
│       ├── effort.csv
│       └── site_covariates.csv
├── validation/run01/
├── reports/
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
