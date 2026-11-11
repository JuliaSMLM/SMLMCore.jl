# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-11

### Changed
- Split SMLMCore from SMLMData.jl 0.7.1 with its git history. Core types and operations stay here; file io (SMITE) moves to SMLMio. SMLMData 0.7.2 and later load SMLMCore and SMLMio and re-export both. Apart from the fixes below, behavior is that of SMLMData 0.7.1.
- Requires Julia 1.10 or later, the current long-term-support release (SMLMData 0.7.1 allowed Julia 1.9).
- SMLMCore cannot be installed together with SMLMData 0.7.1 or earlier.
- Requires StaticArrays 1.9.8 or later; earlier versions do not load on Julia 1.10 beside the current StaticArraysCore.

### Fixed
- `merge_smld` with `adjust_frames` or `adjust_datasets` no longer changes its inputs' emitters; renumbered entries are new emitters, and immutable emitter types can be renumbered.
- `merge_smld` with `adjust_datasets` moves each input's datasets by the earlier inputs' total `n_datasets`, so inputs that hold several datasets no longer share dataset numbers, and the result's `n_datasets` is the inputs' total (it was the number of inputs).
- `cat_smld` and `merge_smld` accept two cameras only when every field is equal, calibration included, so a scalar and a uniform map of the same value no longer combine; the error names the fields that differ.
- `cat_smld` and `merge_smld` with one input return a new SMLD with the metadata keys that a call with several inputs adds; they returned the input itself.
- `physical_to_pixel_index` returns the pixel whose half-open interval holds the position, so `x = 0` is in pixel 1 and a position on a pixel edge is in the pixel that starts there, up to floating-point rounding. It rounded half to even, which put the camera's corner in pixel 0.
- `physical_to_pixel` keeps the input's float type; Float32 positions gave Float64.
- `Adapt.adapt(CuArray, batch)` on an `ROIBatch` moves only `data` and keeps the corners, frame indices and camera on the host; it threw a MethodError.
- `ROIBatch` construction throws an `ArgumentError` for ROIs that are not square and a `DimensionMismatch` for corner or frame vectors of the wrong length, instead of an `AssertionError` from checks that Julia may compile out.
- Editing `api_overview.md` makes the precompile cache stale, so `SMLMCore.api_overview()` and its help entry show the current text.

## SMLMData.jl [0.4.0] - 2025-01-13

### Added
- **SCMOSCamera type** for sCMOS camera support with pixel-dependent calibration parameters
  - `offset`: Dark level in ADU (scalar or per-pixel matrix)
  - `gain`: Conversion gain in e⁻/ADU (scalar or per-pixel matrix)
  - `readnoise`: Read noise in e⁻ rms (scalar or per-pixel matrix)
  - `qe`: Quantum efficiency 0-1 (scalar or per-pixel matrix)
  - Units match camera specification sheets for easy parameterization
  - Supports mixed scalar and matrix parameters for flexible calibration
  - Two constructor forms: `(nx, ny, pixel_size, readnoise; kwargs...)` and `(edges_x, edges_y; kwargs...)`
- Accessor functions for SCMOSCamera parameters: `get_offset`, `get_gain`, `get_readnoise`, `get_qe`, `get_readnoise_var`
- Custom display methods showing parameter types (uniform vs per-pixel)
- Comprehensive test suite with 91 new tests covering:
  - Scalar and matrix parameter construction
  - Type stability (Float32/Float64)
  - Dimension validation
  - Accessor functions
  - Realistic use cases (ORCA-Flash4.0, ORCA-Quest specifications)

### Changed
- Updated type hierarchy documentation to include SCMOSCamera
- Enhanced README.md with SCMOSCamera examples
- Expanded api_overview.md with detailed SCMOSCamera usage patterns
- Version bumped to 0.4.0 (minor version for backward-compatible new feature)

### Notes
- No breaking changes - purely additive feature
- IdealCamera remains the default for Poisson-only noise models
- SCMOSCamera designed for compatibility with future SMLMCamera.jl calibration package

## SMLMData.jl [0.3.1] - Previous releases

See git history for earlier changes.

[Unreleased]: https://github.com/JuliaSMLM/SMLMCore.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JuliaSMLM/SMLMCore.jl/releases/tag/v0.1.0
[0.4.0]: https://github.com/JuliaSMLM/SMLMData.jl/releases/tag/v0.4.0
