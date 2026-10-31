# Package index

## Configuration

- [`pam_config_read()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md)
  : Read and validate a pamflow configuration file
- [`pam_config_validate()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_validate.md)
  : Validate a pamflow configuration
- [`pam_load_config()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_load_config.md)
  : Alias for pam_config_read

## Example project

A small synthetic project (audio, deployment sheet, config) used by the
examples in this reference.

- [`pam_example_project()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_example_project.md)
  : Create a small example project to try pamflow on

## Audio Utilities (WAV + FLAC)

- [`utils_audio`](https://pradeeshwarrj.github.io/pamflow/reference/utils_audio.md)
  : Audio I/O Utilities (WAV + FLAC)
- [`pam_audio_exts()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_exts.md)
  : Supported Audio File Extensions
- [`pam_audio_pattern()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_pattern.md)
  : Regex Pattern Matching Supported Audio Files
- [`pam_is_flac()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_is_flac.md)
  : Check if a File is a FLAC File
- [`pam_read_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_audio.md)
  : Read Audio File as a tuneR Wave Object (WAV or FLAC)
- [`pam_cut_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_cut_audio.md)
  : Cut Audio Clip Preserving Source Format

## Stage 0 — Standardization & Triage

- [`pam_standardize()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_standardize.md)
  : Standardize Raw PAM Audio Files (Stage 00 Engine)
- [`pam_standardization_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_standardization_app.md)
  : Launch PAM Standardization & Data Triage Shiny App
- [`pam_inspect_raw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_inspect_raw.md)
  : Inspect Raw Audio Directory
- [`pam_parse_datetime()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_parse_datetime.md)
  : Parse Datetime from Audio Filename or Metadata
- [`pam_extract_grid()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_extract_grid.md)
  : Extract Grid, Recorder, or Site Identifier from Filename

## Stage 1 — Scan & QC

- [`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md)
  : Stage 1: scan standardized audio and build the master metadata table
- [`pam_audio_info()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_info.md)
  [`pam_audio_info_dt()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_info.md)
  : Read Audio File Metadata (WAV or FLAC)
- [`pam_audio_summary()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_summary.md)
  : Summarise the audio master table
- [`pam_list_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_list_audio.md)
  : List Audio Files in a Directory (WAV + FLAC)
- [`pam_parse_filenames()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_parse_filenames.md)
  : Parse grid and start time from recording filenames
- [`pam_read_deployments()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_deployments.md)
  : Read and clean the deployment sheet
- [`pam_match_deployments()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_match_deployments.md)
  : Attach recorder and coordinates by matching grid and time window
- [`pam_check_deployments()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_check_deployments.md)
  : List problems in the deployment table
- [`pam_add_qc()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_add_qc.md)
  : Add QC flags to a master audio table

## Stage 2 — Filter

- [`pam_filter_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_filter_audio.md)
  : Stage 2: high-pass filter all QC-passed recordings
- [`pam_filter_one()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_filter_one.md)
  : Filter one audio file with FFmpeg (WAV or FLAC)
- [`pam_highpass_filter_string()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_highpass_filter_string.md)
  : Build the FFmpeg filter string for a Butterworth high-pass

## Stage 2b — Soundscape Indices

- [`soundscape`](https://pradeeshwarrj.github.io/pamflow/reference/soundscape.md)
  : Stage 2b: Soundscape Analysis (Indices & Summaries)
- [`pam_soundscape_run()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run.md)
  : Run Stage 2b Soundscape Analysis Pipeline
- [`pam_soundscape_one()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_one.md)
  : Compute Ecoacoustic Soundscape Indices for a Single Audio File
- [`pam_soundscape_batch()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_batch.md)
  : Batch Process Audio Files for Soundscape Indices
- [`pam_soundscape_summarise()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_summarise.md)
  : Summarize Soundscape Indices into Hourly, Diel, and Site Covariate
  Metrics
- [`to_scalar_num()`](https://pradeeshwarrj.github.io/pamflow/reference/to_scalar_num.md)
  : Safely Extract a Single Numeric Value from Soundecology/Seewave
  Returns

## Stage 2c — Soundscape Visualizations & Reports

- [`soundscape_vis`](https://pradeeshwarrj.github.io/pamflow/reference/soundscape_vis.md)
  : Stage 2c: Soundscape Visualization & Diagnostics
- [`pam_soundscape_run_vis()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run_vis.md)
  : Run Stage 2c Soundscape Visualization Pipeline
- [`pam_soundscape_plot_diel()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_plot_diel.md)
  : Plot 24-Hour Diel Curves for Acoustic Indices
- [`pam_soundscape_plot_phase()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_plot_phase.md)
  : Plot Day vs. Night Comparisons for Acoustic Indices
- [`pam_soundscape_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_report.md)
  : Generate HTML Soundscape Diagnostic Report

## Stage 3 — Detect

- [`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)
  : Stage 3: run the custom BirdNET classifier on all QC-passed
  recordings
- [`pam_assemble_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_assemble_detections.md)
  : Assemble raw detection batches into one detections table
- [`pam_pending_batches()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_pending_batches.md)
  : Split pending work into batches, skipping completed items

## Stage 4 — Process

- [`pam_process_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_process_detections.md)
  : Stage 4: clean the detections of a run
- [`pam_clean_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_clean_detections.md)
  : Apply the cleaning rules to a detections table

## Stage 5 — Validate

- [`pam_validate()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validate.md)
  : Open the validation app
- [`pam_validation_draw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_draw.md)
  : Draw a validation round and add it to the sample file
- [`pam_validation_export()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_export.md)
  : Export audio clips and spectrograms for the sampled events (WAV +
  FLAC)
- [`pam_validation_sample()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_sample.md)
  : Draw a validation sample from a pool of events
- [`pam_validation_import()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_import.md)
  : Join the reviewed verdicts to the sample table
- [`pam_validation_pool()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_pool.md)
  : Build the pool of candidate events for validation
- [`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md)
  : Precision by species and confidence band, and by confidence
  threshold
- [`pam_validation_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_report.md)
  : Validation report: precision tables written to disk
- [`pam_annotate()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_annotate.md)
  : Open the ground-truth annotation app

## Stage 5b — Recall

- [`pam_recall_draw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_draw.md)
  : Draw a round of random segments for ground-truth annotation
- [`pam_recall_export()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_export.md)
  : Export audio and spectrograms for the ground-truth segments
- [`pam_recall_frame()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_frame.md)
  : All possible annotation segments of the recordings
- [`pam_recall_sample()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_sample.md)
  : Simple random sample of segments
- [`pam_recall_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_metrics.md)
  : Segment-level recall, precision and F1 against ground truth
- [`pam_recall_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_report.md)
  : Recall report for a detection run

## Stage 6 — Occupancy

- [`pam_build_occupancy()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_build_occupancy.md)
  : Build occupancy detection histories for all qualifying species
- [`pam_site_id()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_site_id.md)
  : Build site identifiers from the audio master table
- [`pam_daily_effort()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_daily_effort.md)
  : Calculate daily recording effort per site
- [`pam_detection_matrix()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detection_matrix.md)
  : Build a detection history matrix for one species
- [`pam_occasion_covariates()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_occasion_covariates.md)
  : Build occasion-level covariate table
- [`pam_site_covariates()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_site_covariates.md)
  : Build site-level covariate table

## Ecological products

Per-species thresholds and a site, time-bin and species table with
recording effort; activity patterns and richness.

- [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md)
  : Choose a confidence threshold for each species from the validation
  results
- [`pam_detection_table()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detection_table.md)
  : Table of detections and recording effort per site, time bin and
  species
- [`pam_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_activity.md)
  : Activity patterns: detections per recorded hour
- [`pam_plot_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_plot_activity.md)
  : Plot activity patterns
- [`pam_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_richness.md)
  : Species richness and diversity per site and occasion
- [`pam_plot_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_plot_richness.md)
  : Plot species richness

## Stage 7 — Input for occupancy and abundance models

Count histories per species and site, covariates, seasons, and input
ready for unmarked, ubms or spOccupancy. pamflow prepares the data; it
does not fit the models.

- [`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)
  : Count history of one species: detections per site and occasion
- [`pam_count_histories()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_histories.md)
  : Count histories of many species at once
- [`pam_as_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_as_count_history.md)
  : Make a count history from your own counts
- [`pam_add_site_covariates()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_add_site_covariates.md)
  : Add site covariates to a count history
- [`pam_define_seasons()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_define_seasons.md)
  : Define seasons from the occasions of a history
- [`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)
  : Prepare a count history as input for abundance and occupancy models
- [`pam_check_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_check_model_input.md)
  : Check model input before fitting

## Stage 8 — Reports

- [`pam_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report.md)
  : Generate PAM workflow reports
- [`pam_report_data()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report_data.md)
  : Gather report data from all completed stages
- [`pam_report_excel()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report_excel.md)
  : Write summary tables to an Excel workbook

## Standalone tool — BirdNET model training (not a workflow stage)

Train your own BirdNET classifier from R or in a point-and-click app.
Nothing in the workflow calls these functions; the trained model is used
by pointing the `birdnet:` section of the config at it.

- [`pam_train_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_train_app.md)
  : Launch the BirdNET classifier training app

- [`pam_birdnet_train_prepare()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_prepare.md)
  : Check a training dataset before training

- [`pam_birdnet_train()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train.md)
  : Train a custom BirdNET classifier from R

- [`pam_birdnet_train_repeat()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_repeat.md)
  : Train the same classifier several times and summarise the metrics

- [`pam_birdnet_train_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_metrics.md)
  :

  Read training metrics from a `birdnet-train` log

## BirdNET environment & benchmark

- [`pam_birdnet_setup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_setup.md)
  : Create a private Python environment for BirdNET
- [`pam_birdnet_doctor()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_doctor.md)
  : Check the machine and Python environments needed for BirdNET
- [`pam_birdnet_cleanup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_cleanup.md)
  : Stop BirdNET worker processes that were left behind
- [`pam_birdnet_benchmark()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_benchmark.md)
  : Benchmark Stage 3 detection speed at several worker counts

## Utilities

- [`pam_audio_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_history.md)
  : Follow audio files through the workflow
- [`pam_log()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_log.md)
  : Write a timestamped log line to a per-stage log file
- [`pam_run_stage()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_run_stage.md)
  : Run a workflow stage with logging and error isolation
- [`pam_checkpoint_read()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_checkpoint_read.md)
  : Read the set of already-processed item IDs
- [`pam_checkpoint_add()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_checkpoint_add.md)
  : Record items as completed
- [`pam_check_ffmpeg()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_check_ffmpeg.md)
  : Check that FFmpeg is installed and supports the filter chain
- [`pam_wilson_ci()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_wilson_ci.md)
  : Wilson score confidence interval for a proportion
