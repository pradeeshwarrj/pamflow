# Check a training dataset before training

Looks at the folder-per-class layout BirdNET-Analyzer expects and
reports problems early: missing or empty classes, very small classes,
files that are not audio, and a missing non-event class.

## Usage

``` r
pam_birdnet_train_prepare(data_dir, min_clips = 20L, quiet = FALSE)
```

## Arguments

- data_dir:

  Training folder with one sub-folder per class.

- min_clips:

  Classes (other than noise classes) with fewer audio files are flagged.
  A rule of thumb for your own data, not an Analyzer limit.

- quiet:

  If TRUE, do not print the report.

## Value

Invisibly, a list: `classes` (data.frame with `class`, `n_audio`,
`n_other`, `n_subdirs`, `is_noise`), `issues` (character) and `ok` (TRUE
if there are no issues).

## Details

Audio files are counted by extension (wav, flac, mp3, ogg, m4a); clip
length is not inspected. The Analyzer's documentation recommends
3-second clips and a background class named noise, other, background or
silence.

## Examples

``` r
if (FALSE) { # \dontrun{
pam_birdnet_train_prepare("E:/training_clips")
} # }
```
