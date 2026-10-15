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
  "recording_date", "n_detections", "seconds",
  "i.file_path", "x.recorder", "x.latitude", "x.longitude", "x.deployment_id", "."
))
