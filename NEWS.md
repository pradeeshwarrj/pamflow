# pamflow 0.5.0

## Standalone BirdNET model training (not a workflow stage)
Training your own classifier is a separate tool. No workflow stage calls it and the workflow runs without it; the trained model is used by pointing the `birdnet:` config section at it. `pam_birdnet_setup("training")` creates the training environment.

* **Training app.** `pam_train_app()` is a Shiny app laid out like the Analyzer GUI's training tab: choose the data, set the options, watch live progress and learning curves, repeat a training to see how much the scores vary, compare earlier runs, and copy the config lines for the new model. The interface text lives in `inst/i18n/` (English included; other languages can be added by translating one file).
* `pam_birdnet_train_prepare()`, `pam_birdnet_train()`, `pam_birdnet_train_metrics()` and `pam_birdnet_train_repeat()` run BirdNET-Analyzer's own `birdnet-train` command, with the same defaults and results as the Analyzer GUI (version 2.4.0). Every run keeps a log and a record of what was run.
* **Per-class test results.** With a separate test folder, `pam_birdnet_train()` returns `evaluation`: precision, recall, F1, AUPRC and AUROC for every class plus the macro average, read from the Analyzer's `<output>_evaluation.csv`. The training app shows them on the Results tab (best threshold per class or 0.5) with the confusion counts.

## BirdNET without birdnetR
* **birdnetR is no longer used.** Stage 3 runs the Python `birdnet` package (0.2.x) directly through a small batch script shipped with pamflow (`inst/python/pam_birdnet_predict.py`). Detections are identical to birdnetR's on the pilot data and the run is faster.
* **Own Python environment.** `pam_birdnet_setup()` creates private virtual environments (inference and training) with `uv`; `pam_birdnet_doctor()` checks the machine and the environments.
* **Worker control.** `birdnet$workers` sets the number of worker processes; if unset, half of the physical cores are used. New options: `top_k`, `py_batch_size`, `n_producers`, `sigmoid_sensitivity`, `device`, `python_env`. `batch_size` and `tflite_threads` were birdnetR settings and are ignored.
* **Benchmark.** `pam_birdnet_benchmark()` measures throughput for several worker counts and estimates the time for the whole archive.
* **Clearer errors.** `pam_detect()` now names missing configuration entries.
* **No leftover processes.** Interrupting a run (Esc) stops BirdNET and all its worker processes; `pam_birdnet_cleanup()` stops workers left behind by an earlier crash.


# pamflow 0.4.0

## Stage 00 Data Triage & Standardization
* **Audio Standardization Engine**: Added `pam_standardize()` to process multi-format field audio (WAV, FLAC, MP3) into uniform 48 kHz Mono WAV format while keeping raw audio files strictly read-only.
* **Raven Compass Triage App**: Added `pam_standardization_app()`, an interactive Shiny app with `[Inspect]`, `[Convert]`, and `[Log]` tabs.
* **Automatic Isolation**: Short files (< 60 seconds) or corrupt audio are automatically segregated into `data/isolated/`.
* **Metadata Parsing**: Added `pam_parse_datetime()` and `pam_extract_grid()` to extract timestamps and deployment/sensor IDs directly from filenames.

## Infrastructure, Branding & Documentation
* **Package Logo**: Integrated hexagonal logo (`man/figures/logo.png`) and site favicons.

## Compliance & Maintenance
* Standardized log outputs with strict uppercase log levels (`"INFO"`, `"WARN"`, `"ERROR"`).
* Ensured pure ASCII compliance across all `.R` files and Shiny interfaces.


# pamflow 0.3.0

## Major Features

- **FLAC compatibility**: All 8 pipeline stages now natively support `.flac` files alongside `.wav`.
- **Audio Utilities Module (`R/utils_audio.R`)**: Added `pam_read_audio()`, `pam_audio_info()`, `pam_cut_audio()`, `pam_list_audio()`, and `pam_is_flac()` for unified audio I/O.
- **Stage 1 (Scan)**: Vectorized header reading via `av` and `tuneR`.
- **Stage 2 (Filter)**: Dynamic FFmpeg codec branching (`-c:a flac` vs `-c:a pcm_s16le`).
- **Stage 2b (Soundscape)**: PSOCK worker export env with FLAC decoding.
- **Stage 5 (Validation)**: Format-preserving clip export and on-the-fly FLAC -\> WAV transcoding for Shiny browser playback.

# pamflow 0.2.0

## Major Features

- **Workflow B: Soundscape Analysis** introduced.
- **Stage 2b (Soundscape Indices)**: Added `pam_soundscape_run()` to compute ACI, ADI, AEve, Bio, H, M, and NDSI following Bradfer-Lawrence et al. (2019).
- **Stage 2c (Soundscape Visualizations)**: Added `pam_soundscape_run_vis()` and `pam_soundscape_report()` to generate automated 24-hour diel profiles, Day/Night comparisons, and HTML diagnostic reports.

## Performance & Optimizations

- Implemented 1-minute sub-windowing for high-performance memory safety.
- Optimized audio high-pass filtering (500 Hz) at the sub-window level.
- Added dynamic downsampling (to 24 kHz) for ecoacoustic frequency bounds, increasing processing speed by 10x-15x.
- Checkpointing mechanism (`done.txt`) implemented for crash-resilient resuming.

# pamflow 0.1.0

- First release.
- **Stage 1 (Scan)**: Audio scanning and QC (`pam_scan_audio()`).
- **Stage 2 (Filter)**: High-pass filtering (Optional) (`pam_filter_audio()`).
- **Stage 3 (Detection)**: BirdNET batch detection with parallel workers and resume support (`pam_detect()`).
- **Stage 4 (Process Detection)**: Detection cleaning, filtering, and merging (`pam_process_detections()`).
- **Stage 5 (Validation)**: Interactive validation app with precision metrics (`pam_validation_draw()`, `pam_validation_export()`, `pam_validation_app()`, `pam_validation_metrics()`).
- **Stage 6 (Occupancy detection History)**: Occupancy detection histories and covariates (`pam_build_occupancy()`).
- **Stage 8 (Report)**: HTML and Excel reports (`pam_report()`).
- Config-driven pipeline — all settings in a single YAML file.
- R CMD check clean (0 errors, 0 warnings, 0 notes).
- Tested on pilot data.
