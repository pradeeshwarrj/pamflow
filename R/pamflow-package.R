#' @keywords internal
#' @import data.table
"_PACKAGE"

# Column names used with data.table's non-standard evaluation
utils::globalVariables(c(
  "file_path", "file_name", "grid", "date_str", "time_str", "start_time",
  "valid_name", "duration_s", "end_time", "file_size_b", "expected_bytes",
  "readable", "truncated", "short", "dup_n", "duplicate", "gap_s",
  "gap_before", "overlap_before", "qc_pass", "deploy_start", "retrieve_end",
  "recorder", "habitat", "deployer", "latitude", "longitude", "deployment_id",
  "in_deployment", "sample_rate", "channels", "bits", "deploy_date",
  "deploy_time", "retrieve_date", "retrieve_time", "deploy_day", "retrieve_day",
  "recovery_time_missing", "overlaps_prev", "n_files", "hours", "modal_duration_s",
  "ok", "verified", "message", "rel", "input", "output", "exp_dur", "exp_sr",
  "exp_ch", "size", "path", "start_s", "end_s", "scientific_name", "common_name",
  "confidence", "species", "recording_start", "detection_datetime",
  "recording_date", "n_detections", "seconds", "i.file_path", "x.recorder",
  "x.latitude", "x.longitude", "x.deployment_id", ".", "reason", "threshold",
  "thr_species", "file_duration_s", "event", "mean_confidence", "n_windows",
  "detection_date", "month_start", "month_end", "n_before", "n_removed", "event_id",
  "band", "band_idx", "sample_id", "round", "clip_file", "spec_file", "clip_start_s",
  "clip_dur_s", "event_offset_s", "event_end_offset_s", "verdict", "true_species",
  "n_pool", "n_reviewed", "n_correct", "n_incorrect", "n_unsure", "n_judged", "precision",
  "ci_low", "ci_high", "N", "predicted", "n_events", "coverage", "precision_est",
  "min_confidence", "reviewed_at", "strategy", "reason", "n_slots", "seg_start", "seg_end",
  "slot_time", "hour", "seg_key", "label", "status", "detected", "tp", "fn", "fp", "tn",
  "n_present", "threshold", "present", "possible", "i.segment_id", "x.scientific_name", "x.confidence",
  "site_id", "start_local", "end_local", "date1", "date2", "midnight", "h1", "h2", "effort_hours", "occasion_date",
  "sufficient", "detected", "julian_date", "total_effort_hours", "n_occasions_surveyed", "threshold_used", "n_sites",
  "n_occasions", "n_sites_detected", "naive_occupancy", "scientific_name", "threshold", "deployment_id", "hour",
  "events", "sites"
))
