# Build the FFmpeg filter string for a Butterworth high-pass

FFmpeg's `highpass` filter supports only 2 poles per instance, so higher
orders are built as a cascade of second-order sections, each with the Q
value that yields a true Butterworth response (maximally flat passband,
-3 dB at the cutoff). Four identical sections would NOT give this: the
cutoff would sit near -12 dB.

## Usage

``` r
pam_highpass_filter_string(cutoff_hz = 250, order = 8L)
```

## Arguments

- cutoff_hz:

  Cutoff frequency in Hz (-3 dB point).

- order:

  Even filter order. 8 = 48 dB/octave.

## Value

A single character string for `ffmpeg -af`.

## Examples

``` r
pam_highpass_filter_string(250, 8)
#> [1] "highpass=f=250:p=2:t=q:w=0.509796:r=f64,highpass=f=250:p=2:t=q:w=0.601345:r=f64,highpass=f=250:p=2:t=q:w=0.899976:r=f64,highpass=f=250:p=2:t=q:w=2.562915:r=f64"
```
