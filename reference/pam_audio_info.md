# Read Audio File Metadata (WAV or FLAC)

Reads header information (sample rate, duration, channels, bit depth)
for one or more WAV/FLAC files without loading sample data into memory.
Returns a data.table with readable status; errors for individual
unreadable files are caught gracefully and flagged with
`readable = FALSE`.

## Usage

``` r
pam_audio_info(paths)

pam_audio_info_dt(paths)
```

## Arguments

- paths:

  Character vector of file paths.

## Value

A `data.table` with columns `file_path`, `file_size_b`, `sample_rate`,
`channels`, `bits`, `duration_s`, `readable`.

## Examples

``` r
ex <- pam_example_project()
pam_audio_info(ex$files)
#>                                                                                         file_path
#>                                                                                            <char>
#> 1: /tmp/Rtmpefifs1/pamflow_example_1c5713aeb5ad/data/standardized/G0059/G0059_20260405_183000.wav
#> 2: /tmp/Rtmpefifs1/pamflow_example_1c5713aeb5ad/data/standardized/G0059/G0059_20260405_183002.wav
#> 3: /tmp/Rtmpefifs1/pamflow_example_1c5713aeb5ad/data/standardized/G0059/G0059_20260405_183004.wav
#> 4: /tmp/Rtmpefifs1/pamflow_example_1c5713aeb5ad/data/standardized/G0110/G0110_20260406_060000.wav
#> 5: /tmp/Rtmpefifs1/pamflow_example_1c5713aeb5ad/data/standardized/G0110/G0110_20260406_060002.wav
#> 6: /tmp/Rtmpefifs1/pamflow_example_1c5713aeb5ad/data/standardized/G0110/G0110_20260406_060004.wav
#>    file_size_b sample_rate channels  bits duration_s readable
#>          <num>       <int>    <int> <int>      <num>   <lgcl>
#> 1:       32080        8000        1    16          2     TRUE
#> 2:       32080        8000        1    16          2     TRUE
#> 3:       32080        8000        1    16          2     TRUE
#> 4:       32080        8000        1    16          2     TRUE
#> 5:       32080        8000        1    16          2     TRUE
#> 6:       32080        8000        1    16          2     TRUE
```
