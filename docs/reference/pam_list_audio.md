# List WAV files under the standardized audio folder

List WAV files under the standardized audio folder

## Usage

``` r
pam_list_audio(audio_dir)
```

## Arguments

- audio_dir:

  Root folder (searched recursively, so grid sub-folders such as
  `G_0263/` are found).

## Value

Character vector of full paths to `.wav` files (case-insensitive).
