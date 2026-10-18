# Changelog

## pamflow 0.1.0

- First release.
- Stage 1: Audio scanning and QC
  ([`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md)).
- Stage 3: BirdNET batch detection with parallel workers and resume
  support
  ([`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)).
- Stage 4: Detection cleaning, filtering, and merging
  ([`pam_process_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_process_detections.md)).
- Stage 5: Interactive validation app with precision metrics
  ([`pam_validation_draw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_draw.md),
  [`pam_validation_export()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_export.md),
  `pam_validation_app()`,
  [`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md)).
- Stage 6: Occupancy detection histories and covariates
  ([`pam_build_occupancy()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_build_occupancy.md)).
- Stage 8: HTML and Excel reports
  ([`pam_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report.md)).
- Config-driven pipeline — all settings in a single YAML file.
- 134 unit tests, R CMD check clean (0 errors, 0 warnings, 0 notes).
