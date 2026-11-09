# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Split SMLMCore from SMLMData.jl 0.7.1 with its git history. Core types and operations stay here; file io (SMITE) moves to SMLMio. SMLMData 0.7.2 and later loads SMLMCore and SMLMio and re-exports both. Apart from the fixes below, behavior is that of SMLMData 0.7.1.

### Fixed
- `merge_smld` with `adjust_frames` or `adjust_datasets` no longer changes the frame and dataset numbers of the input emitters (they were shared with the result and renumbered in place, so a second merge shifted them again, and an emitter listed twice in one input was shifted twice). Each renumbered entry is now a new emitter with only the requested numbers changed: a mutable emitter is copied field by field and set through `setproperty!` (fields holding arrays or other objects stay shared with the input; an emitter with a field left undefined is deep-copied instead), and an immutable emitter is rebuilt from its fields without calling its constructor (fields its constructor left unset stay unset). Immutable emitter types, including ones with a `frame` field and no `dataset` field, can now be renumbered.
- `merge_smld` with `adjust_datasets` moves each input's datasets by the earlier inputs' total `n_datasets` and sets `n_datasets` to the total. It moved each input by 1 and set `n_datasets` to the number of inputs, so inputs holding several datasets shared dataset numbers.
- `cat_smld` and `merge_smld` treat two cameras as the same only when every field is equal, calibration included. Two sCMOS cameras with the same pixels but different offset, gain, read noise or QE were accepted as one camera, and the result kept the first camera's calibration. A call that merged such cameras now throws; so does one that merges a scalar calibration with a uniform map of the same value. Numbers, arrays, dictionaries, tuples, immutable structs and wrapped cameras compare by value (NaN equals NaN, -0.0 equals 0.0); any other object in a camera field, such as a mutable handle, compares with its own `==`, so a camera type that holds one merges with a separately built copy only if that object's type defines `==`. A plain-bits field that a camera's constructor leaves unset holds whatever was in memory, so it can make two otherwise equal cameras differ. The error now names the input and the camera fields that differ (or the two camera types). A camera type without `pixel_edges_x` and `pixel_edges_y` fields (a camera that wraps another) made `cat_smld` and `merge_smld` throw a FieldError; it is now compared like any other.

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

[Unreleased]: https://github.com/JuliaSMLM/SMLMCore.jl/commits/main
[0.4.0]: https://github.com/JuliaSMLM/SMLMData.jl/releases/tag/v0.4.0
