# Helper to Safely Extract Scalar Numerical Values from Soundecology Returns

Tries named candidates first; if none match, falls back to the first
numeric element found anywhere in the list. This is robust against
soundecology changing its return element names between versions.

## Usage

``` r
get_soundeco_val(res, candidates)
```

## Arguments

- res:

  A list returned by a soundecology function.

- candidates:

  Character vector of preferred element names.

## Value

A length-1 numeric, or NA_real\_.
