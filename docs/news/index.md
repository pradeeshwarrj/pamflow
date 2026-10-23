# Changelog

## pamflow 0.3.0

### Major Features

- **FLAC compatibility**: All 8 pipeline stages now natively support
  `.flac` files alongside `.wav`.
- **Audio Utilities Module (`R/utils_audio.R`)**: Added
  [`pam_read_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_audio.md),
  [`pam_audio_info()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_info.md),
  [`pam_cut_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_cut_audio.md),
  [`pam_list_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_list_audio.md),
  and
  [`pam_is_flac()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_is_flac.md)
  for unified audio I/O.
- **Stage 1 (Scan)**: Vectorized header reading via `av` and `tuneR`.
- **Stage 2 (Filter)**: Dynamic FFmpeg codec branching (`-c:a flac` vs
  `-c:a pcm_s16le`).
- **Stage 2b (Soundscape)**: PSOCK worker export env with FLAC decoding.
- **Stage 5 (Validation)**: Format-preserving clip export and on-the-fly
  FLAC -\> WAV transcoding for Shiny browser playback.

## pamflow 0.2.0

### Major Features

- **Workflow B: Soundscape Analysis** introduced.
- **Stage 2b (Soundscape Indices)**: Added
  [`pam_soundscape_run()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run.md)
  to compute ACI, ADI, AEve, Bio, H, M, and NDSI following
  Bradfer-Lawrence et al. (2019).
- **Stage 2c (Soundscape Visualizations)**: Added
  [`pam_soundscape_run_vis()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run_vis.md)
  and
  [`pam_soundscape_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_report.md)
  to generate automated 24-hour diel profiles, Day/Night comparisons,
  and HTML diagnostic reports.

### Performance & Optimizations

- Implemented 1-minute sub-windowing for high-performance memory safety.
- Optimized audio high-pass filtering (500 Hz) at the sub-window level.
- Added dynamic downsampling (to 24 kHz) for ecoacoustic frequency
  bounds, increasing processing speed by 10x-15x.
- Checkpointing mechanism (`done.txt`) implemented for crash-resilient
  resuming.

## pamflow 0.1.0

- First release.
- **Stage 1 (Scan)**: Audio scanning and QC
  ([`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md)).
- **Stage 2 (Filter)**: High-pass filtering (Optional)
  ([`pam_filter_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_filter_audio.md)).
- **Stage 3 (Detection)**: BirdNET batch detection with parallel workers
  and resume support
  ([`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)).
- **Stage 4 (Process Detection)**: Detection cleaning, filtering, and
  merging
  ([`pam_process_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_process_detections.md)).
- **Stage 5 (Validation)**: Interactive validation app with precision
  metrics
  ([`pam_validation_draw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_draw.md),
  [`pam_validation_export()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_export.md),
  `pam_validation_app()`,
  [`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md)).
- **Stage 6 (Occupancy detection History)**: Occupancy detection
  histories and covariates
  ([`pam_build_occupancy()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_build_occupancy.md)).
- **Stage 8 (Report)**: HTML and Excel reports
  ([`pam_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report.md)).
- Config-driven pipeline — all settings in a single YAML file.
- R CMD check clean (0 errors, 0 warnings, 0 notes).
- Tested on pilot data.
