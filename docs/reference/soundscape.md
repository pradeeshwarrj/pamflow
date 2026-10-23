# Stage 2b: Soundscape Analysis (Indices & Summaries)

Implementation of ecoacoustic soundscape indices following
Bradfer-Lawrence et al. (2019) guidelines. Computes core acoustic
indices with 1-minute sub-windowing, checkpointing, multi-core parallel
processing, and timezone-aware hourly/diel summarization. Supports WAV
and FLAC via
[`pam_read_audio`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_audio.md)
/
[`pam_list_audio`](https://pradeeshwarrj.github.io/pamflow/reference/pam_list_audio.md).
