# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `@filter` conditions may use the caller's variables and functions. A name is an emitter property when the emitter has one of that name (`hasproperty`), and otherwise the variable or function of that name where `@filter` is called, so `photons > threshold`, `x ≤ 1.0`, `abs(x) < 1.0`, `!(frame == 2)` and `frame in 1:10` work; each threw an error naming a missing field. Called functions follow the same rule, and operators never are properties. `$name` reads the variable and `$f(x)` calls the caller's function when a property has the same name; each `$expr` is evaluated once, where `@filter` is called, and so is each caller variable the condition names, so the emitter function never captures a caller variable. A property is read where the condition reaches it, as in 0.1.0, so `photons > 100 && z > 0` never reads `z` of an emitter it stops at. Names the condition binds itself (arguments, loop and `let` variables, names it assigns) keep Julia's own scope rules: each starts as the emitter's property or the caller's variable of that name (else `nothing`), and an assignment changes only that binding, never the caller's variable (a name the condition declares `global` is the module's). Other macros in the condition expand first; in a nested `@filter`, a free name follows the outer condition. Keyword names, field names, types in `x::T` and quoted code are not names. A name that is neither a property nor a variable is read with `getproperty`, as before, so a property that `getproperty` computes without `propertynames` listing it is still read, unless a variable of that name is defined where `@filter` is called (names Julia exports, such as `time`, included); that, and a property of the same name as a name the condition binds (read before the condition runs), are the conditions that worked before and can now differ. `e.name` reads the emitter's property, as before, except inside a construct that binds `e`, and a condition that gives `1` or `0` keeps by its truth, as before. The data-set expression is evaluated once (0.1.0 evaluated it up to six times), and the filter allocates less for SMLMCore's emitter types.
- `SCMOSCamera` promotes its arguments to one number type: whole numbers (`offset = 100`, `readnoise = 2`) take the type of the rest, and `Float32` with `Float64` gives `Float64`; each threw an `UndefVarError`, `TypeError` or `MethodError`. A call of one number type gives the same camera as before, whole numbers included; whole-number edges are now computed exactly, and one that does not fit the type throws an `OverflowError` or `InexactError` (they could lose precision or wrap); `IdealCamera`'s whole-number edges are checked the same way. The edges form accepts any vector of edges and any map, a union of number types or offset indices included (values are taken in order). A pixel count below 0 (both cameras) or an empty edge vector (the `SCMOSCamera` edges form) throws an `ArgumentError`; they gave a camera with no pixels or one whose maps could not be checked. The constructors from the fields themselves check nothing, as before.
- `IdealCamera` and `compute_bin_edges` given pixel ranges take a range that starts at 0 or 1 as the whole sensor, as before, and throw an `ArgumentError` for a range that starts anywhere else; such a range (a crop, `101:200`) silently gave a camera at 0 µm. The error says to build a cropped camera from its pixel edges; the conventions page says how positions relate to a crop's edges.
- `IdealCamera` and `SCMOSCamera` with no pixels display; both displays threw a `BoundsError`.
- `filter_roi` logs a warning when a bound is a range other than whole numbers in steps of 1 (`0:2`, `0:1:2`), once per logger (once per Julia session with the default logger): a range stops at its last whole step (`0.0:0.3:1.0` ends at 0.9), and the shortened range cannot be told from one written to end there. Results are unchanged.
- `physical_to_pixel` gives a `Float64` for a coordinate where a `Rational` meets a `Rational` or an integer, as SMLMData 0.7.1 did: the exact value, half pixel included, rounded once to the nearest `Float64`, whatever BigFloat's precision (0.7.1 rounded twice), and `Inf` or `-Inf` for a Rational infinity. 0.1.0 gave Rationals, and a quotient or sum that overflowed threw an `OverflowError`. Other inputs keep the type of `x / pixel_size`, as in 0.1.0.
- `merge_smld` no longer converts `n_frames` and `n_datasets` to `Int`, so counts beyond `typemax(Int)` no longer throw an `InexactError`. Running totals are summed only when renumbering uses them, in `Int` or the counts' wider type (whole numbers held as floats or Rationals are summed as integers), the largest count is found by exact comparison, and both are checked: a sum, a moved number or a result count that does not fit throws an `OverflowError` or `InexactError` instead of wrapping or rounding, as does a float frame that cannot hold its moved value exactly. A moved number is stored in the field's type, or, through a setter, in the property's type.
- `merge_smld` with `adjust_frames` or `adjust_datasets` no longer changes an input emitter whose type has its own `setproperty!` (a frame kept in an array, say): such an emitter is deep-copied and set through its setter, immutable ones included, with both numbers computed before either is set, and a setter that also changes the other number is refused with an `ArgumentError` instead of giving numbers the result does not declare (what a setter stores for its own number is its own, as before). Other renumbered emitters share their object fields with the input, as 0.1.0 documented, and keep fields left unset unset (an emitter with one unset was deep-copied): a mutable one is copied and moved through `e.frame` on the copy, so a getter that fills a field fills the copy's, and an immutable one is rebuilt from its fields, as in 0.1.0. A mutable type with `const` fields and an unset field before a set one is still deep-copied.

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
