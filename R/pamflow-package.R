#' @keywords internal
#' @import data.table
"_PACKAGE"

# Column names used with data.table's non-standard evaluation
utils::globalVariables(c(
  ".", ".N", "..det_cols", "..have", "ACI", "ADI", "AEve", "Bio", "H", "M", "NDSI", "N",
  "action", "annotated", "annotation", "audio_format", "audio_path", "band", "band_idx",
  "bidx", "bit_depth", "bits", "category", "channels", "ci_high", "ci_low", "clip_dur_s",
  "clip_file", "clip_start_s", "common_name", "confidence", "confidence_bin", "correct",
  "coverage", "date1", "date2", "date_str", "deploy_date", "deploy_day", "deploy_start",
  "deploy_time", "deployment_id", "deployer", "dest_path", "detected", "detection_date",
  "detection_datetime", "diel_phase", "diel_summary", "dup_n", "duplicate", "duration_s",
  "effort_hours", "end_datetime", "end_local", "end_offset_s", "end_s", "end_time", "event",
  "event_end_offset_s", "event_id", "event_offset_s", "events", "exp_ch", "exp_dur", "exp_sr",
  "expected_bytes", "ext", "failure_reason", "feature", "file_duration_s", "file_name",
  "file_path", "file_size_b", "file_size_mb", "filename", "fn", "fp", "gap_before", "gap_s",
  "grid", "h1", "h2", "habitat", "head", "hour", "hours", "hours_effort", "i.file_path",
  "i.segment_id", "in_deployment", "input", "is_audio", "judge", "julian_date", "keep",
  "label", "latitude", "longitude", "match_status", "mean_confidence", "message", "metric",
  "midnight", "min_confidence", "modal_duration_s", "month_end", "month_start", "n",
  "n_before", "n_correct", "n_detections", "n_events", "n_files", "n_incorrect", "n_judged",
  "n_occasions", "n_occasions_surveyed", "n_pool", "n_present", "n_removed", "n_reviewed",
  "n_sites", "n_sites_detected", "n_slots", "n_windows", "n_windows_in", "naive_occupancy",
  "ok", "occasion", "occasion_date", "output", "overlap_before", "overlaps_prev",
  "pam_load_config", "parsed_datetime", "path", "pct", "possible", "pred_species", "predicted",
  "precision", "precision_est", "present", "qc_pass", "readable", "reason", "recorder",
  "recording_date", "recording_datetime", "recording_start", "recovery_time_missing",
  "rel", "rel_path", "req", "retrieve_date", "retrieve_day", "retrieve_end", "retrieve_time",
  "reviewed_at", "round", "sample_id", "sample_rate", "sampled", "scientific_name", "seconds",
  "seg_end", "seg_key", "seg_start", "segment_id", "seq_num", "short", "site", "site_id",
  "size", "slot_time", "source_path", "species", "species_code", "spec_file", "start_datetime",
  "start_local", "start_s", "start_time", "status", "status_msg", "strategy", "stratum",
  "stratum_size", "suff_effort", "sufficient", "thr_species", "threshold", "threshold_used",
  "time_str", "total_effort_hours", "tp", "tn", "true_species", "truncated", "valid_name",
  "value", "value.var", "verdict", "verified", "weight", "x.confidence", "x.deployment_id",
  "x.latitude", "x.longitude", "x.recorder", "x.scientific_name"
))
