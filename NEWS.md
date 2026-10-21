# pamflow 0.2.0

## Major Features
* **Workflow B: Soundscape Analysis** introduced.
* **Stage 2b (Soundscape Indices)**: Added `pam_soundscape_run()` to compute ACI, ADI, AEve, Bio, H, M, and NDSI following Bradfer-Lawrence et al. (2019).
* **Stage 2c (Soundscape Visualizations)**: Added `pam_soundscape_run_vis()` and `pam_soundscape_report()` to generate automated 24-hour diel profiles, Day/Night comparisons, and HTML diagnostic reports.

## Performance & Optimizations
* Implemented 1-minute sub-windowing for high-performance memory safety.
* Optimized audio high-pass filtering (500 Hz) at the sub-window level.
* Added dynamic downsampling (to 24 kHz) for ecoacoustic frequency bounds, increasing processing speed by 10x-15x.
* Checkpointing mechanism (`done.txt`) implemented for crash-resilient resuming.

# pamflow 0.1.0

* First release.
* Stage 1: Audio scanning and QC (`pam_scan_audio()`).
* Stage 2: High-pass filtering (Optional) (`pam_filter_audio()`).
* Stage 3: BirdNET batch detection with parallel workers and resume support (`pam_detect()`).
* Stage 4: Detection cleaning, filtering, and merging (`pam_process_detections()`).
* Stage 5: Interactive validation app with precision metrics (`pam_validation_draw()`, `pam_validation_export()`, `pam_validation_app()`, `pam_validation_metrics()`).
* Stage 6: Occupancy detection histories and covariates (`pam_build_occupancy()`).
* Stage 8: HTML and Excel reports (`pam_report()`).
* Config-driven pipeline — all settings in a single YAML file.
* 134 unit tests, R CMD check clean (0 errors, 0 warnings, 0 notes).

