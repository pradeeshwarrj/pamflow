# Summarise Soundscape Indices by Hour and Diel Phase

Summarise Soundscape Indices by Hour and Diel Phase

## Usage

``` r
pam_soundscape_summarise(cfg, raw_dt = NULL)
```

## Arguments

- cfg:

  Config list or path to YAML config file.

- raw_dt:

  Optional data.table of raw soundscape results. If NULL, loaded from
  disk.

## Value

List of data.tables containing hourly and diel site-level summaries.
