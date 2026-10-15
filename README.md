
<!-- README.md is generated from README.Rmd. Please edit that file -->

<!-- README.md is generated from README.Rmd. Please edit that file -->

# pamflow

<!-- badges: start -->

<!-- badges: end -->

A reproducible workflow for passive acoustic monitoring (PAM) of birds.
Wraps [birdnetR](https://github.com/birdnet-team/birdnetR) and
[birdnetTools](https://github.com/birdnet-team/birdnetTools) behind a
config-driven, resumable pipeline that takes you from raw audio to
occupancy models.

## Pipeline stages

| Stage | Function | Description |
|----|----|----|
| 1 | `pam_standardise()` | Filename parsing, format conversion, deployment join |
| 2 | `pam_clean_filter()` | High/low-pass filtering, noise reduction |
| 3 | `pam_detect()` | BirdNET inference (custom classifiers, GPU/CPU) |
| 4 | `pam_process_detections()` | Deduplication, confidence filtering, species lists |
| 5 | `pam_validate()` | Stratified sampling, manual review, accuracy metrics |
| 6 | `pam_occupancy_prep()` | Detection histories and covariates |
| 7 | `pam_occupancy_fit()` | Single-season and multi-season occupancy models |
| 8 | `pam_report()` | Automated R Markdown report |

## Installation

``` r
# install.packages("remotes")
remotes::install_github("pradeeshwarrj/pamflow")
```

## Quick start

``` r
library(pamflow)

# 1. Create a project skeleton
pam_init_project("my_pam_project")

# 2. Edit the config
#    Open my_pam_project/config/config.yml and set your paths

# 3. Run the full pipeline
cfg <- pam_config_read("my_pam_project/config/config.yml")
pam_run_all(cfg)
```

## Dependencies

- **R ≥ 4.2**
- **Python ≥ 3.9** (managed automatically by `reticulate`)
- System: `sox` (for audio conversion)

## License

MIT © Pradeeshwar RJ
