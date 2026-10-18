# pamflow 0.1.0

* First release.
* Stage 1: Audio scanning and QC (`pam_scan_audio()`).
* Stage 3: BirdNET batch detection with parallel workers and resume support (`pam_detect()`).
* Stage 4: Detection cleaning, filtering, and merging (`pam_process_detections()`).
* Stage 5: Interactive validation app with precision metrics (`pam_validation_draw()`, `pam_validation_export()`, `pam_validation_app()`, `pam_validation_metrics()`).
* Stage 6: Occupancy detection histories and covariates (`pam_build_occupancy()`).
* Stage 8: HTML and Excel reports (`pam_report()`).
* Config-driven pipeline — all settings in a single YAML file.
* 134 unit tests, R CMD check clean (0 errors, 0 warnings, 0 notes).
