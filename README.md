# pamflow

A reproducible, config-driven R package for end-to-end **passive acoustic
monitoring (PAM)** of birds. Takes standardized field recordings through
quality control, custom BirdNET detection, cleaning, validation, and
occupancy-ready outputs with automated reports.

## Features

- **Resumable**: checkpoint-based processing — crashes don't lose progress
- **Robust**: per-file error isolation — one bad recording never kills the run
- **Parallel**: multi-core BirdNET inference via PSOCK worker clusters
- **Config-driven**: one YAML file controls all settings, no hard-coded paths
- **Validated**: interactive Shiny apps for precision and recall assessment
- **Scalable**: tested on 1,000+ recordings; designed for 100,000+

## Pipeline Stages

| Stage | Function | Description |
|---|---|---|
| 1 | `pam_scan_audio()` | Scan WAV files, QC flags, deployment matching |
| 2 | `pam_filter_audio()` | High-pass filtering via FFmpeg (optional) |
| 3 | `pam_detect()` | BirdNET detection with custom classifier (parallel) |
| 4 | `pam_process_detections()` | Clean, filter, and merge detections into events |
| 5 | `pam_validate()` | Precision validation via interactive Shiny review |
| 5b | `pam_annotate()` | Recall estimation via blind ground-truth annotation |
| 6 | `pam_build_occupancy()` | Detection histories and covariates for occupancy models |
| 8 | `pam_report()` | HTML, PDF, and Excel summary reports |

## Installation

```r
# Install devtools if needed
install.packages("devtools")

# Install pamflow from GitHub
devtools::install_github("pradeeshwarrj/pamflow")

# Install suggested packages as needed
install.packages(c("birdnetR", "rmarkdown", "openxlsx"))

# For PDF reports (one-time setup)
install.packages("tinytex")
tinytex::install_tinytex()
