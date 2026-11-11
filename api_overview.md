# SMLMCore.jl API Overview

SMLMCore defines the data types of single molecule localization microscopy (SMLM) in Julia:
emitters (localizations), cameras, ROI batches and SMLD containers, with coordinate conversions,
filters, and functions that combine data sets. This overview is a compact reference for people
and for AI assistants writing code against the package: the types, how to build them, the main
functions, and the mistakes to avoid. `SMLMCore.api_overview()` returns it as a `String`. The
full documentation, with a tutorial and the conventions page, is at
https://JuliaSMLM.github.io/SMLMCore.jl/stable/.

## Where it fits

SMLMCore holds the types that the JuliaSMLM packages share. SMLMData 0.7.2 and later load
SMLMCore and re-export its names, so packages that depend on those versions of SMLMData, and
their users, get SMLMCore's types without loading it. GaussMLE re-exports `ROIBatch`,
`SingleROI`, `IdealCamera`, `SCMOSCamera` and `@filter`, SMLMBoxer re-exports `ROIBatch` and
`SingleROI`, and SMLMAnalysis re-exports `IdealCamera` and `SCMOSCamera`. A package that needs
only the types depends on SMLMCore directly. File reading and writing (SMITE `.mat`) is in
[SMLMio](https://github.com/JuliaSMLM/SMLMio.jl).

## Installation

```julia
using Pkg
Pkg.add("SMLMCore")
```

An environment that holds SMLMData 0.7.1 or earlier, directly or through a package that depends
on it (GaussMLE, SMLMSim, SMLMBoxer, SMLMAnalysis and others), cannot add SMLMCore, because
those versions define the same types: Pkg reports unsatisfiable requirements for SMLMData.

## Conventions

- Lengths are in µm. In an `Emitter2D` or `Emitter3D`, `photons` are the photons from the
  emitter that reach the camera in the frame, before QE.
- In the fit types, `photons` and `bg` are the fitted signal and background in the units of the
  data the fitter received: photons for data in photons (an `IdealCamera`, or an `SCMOSCamera`
  with `qe = 1`). A fitter that converts `SCMOSCamera` data with `(ADU - offset) * gain`, as
  GaussMLE does, reports photoelectrons (photons × `qe`).
- `pixel_size` is the size of a pixel at the sample (the sensor pixel divided by the
  magnification), in µm.
- The origin, `(0, 0)` µm, is the camera's top-left corner. x runs along the columns and y down
  the rows.
- Pixels are labeled `(x, y) = (col, row)`, numbered from 1; arrays are indexed `[row, col]`.
  With uniform pixels, pixel `(col, row)` is centered at `((col - 0.5)·Δx, (row - 0.5)·Δy)` µm.
  In pixel coordinates the top-left pixel's center is `(1, 1)` and the camera's corner is
  `(0.5, 0.5)`.
- Images and per-pixel arrays are indexed `[row, col] = [y, x]`. An sCMOS calibration map has
  size `(ny, nx)`; ROI data are `[row, col]` (`SingleROI`) or `[row, col, roi]` (`ROIBatch`). A
  square sensor's map cannot be checked for orientation, so a transposed map is accepted
  silently.
- An ROI's corner is the camera pixel `(x, y) = (col, row)` of its top-left pixel. ROI pixel
  `data[row, col, k]` is camera pixel `(x_corners[k] + col - 1, y_corners[k] + row - 1)`.
  ROI data are in the camera's raw units (ADU for an `SCMOSCamera`).
- Frame and dataset numbers start at 1.
- `σ_x`, `σ_y` and `σ_z` are standard deviations (µm); `σ_xy`, `σ_xz` and `σ_yz` are
  covariances (µm²).

The conventions page states these in full:
https://JuliaSMLM.github.io/SMLMCore.jl/stable/guide/conventions/.

## Type Hierarchy

```
AbstractEmitter                   # Base for all emitter types
├── Emitter2D{T}                  # 2D position and photons
├── Emitter3D{T}                  # 3D position and photons
├── Emitter2DFit{T}               # 2D fit results with uncertainties
└── Emitter3DFit{T}               # 3D fit results with uncertainties

AbstractCamera                    # Base for all camera types
├── IdealCamera{T}                # Regular pixel grid (Poisson noise only)
└── SCMOSCamera{T}                # sCMOS camera with per-pixel calibration

ROI batch types                   # For batched ROI processing
├── SingleROI{T}                  # One ROI with its corner and frame
└── ROIBatch{T,N,A,C}             # A batch of ROIs from one camera

AbstractSMLD                      # Base for data containers
└── BasicSMLD{T,E}                # General-purpose container

AbstractSMLMConfig                # Supertype of algorithm configuration structs
AbstractSMLMInfo                  # Supertype of algorithm result-information structs
```

`SMLD` is an alias of `AbstractSMLD`, kept for code written against SMLMData.

## Type Definitions

The fields of each concrete type, as defined in `src/` (a test compares this listing with the
code). The constructors are in the next section.

```julia
mutable struct Emitter2D{T} <: AbstractEmitter
    x::T             # µm
    y::T             # µm
    photons::T       # photons that reach the camera in the frame, before QE
end

mutable struct Emitter3D{T} <: AbstractEmitter
    x::T             # µm
    y::T             # µm
    z::T             # µm, axial
    photons::T       # photons that reach the camera in the frame, before QE
end

mutable struct Emitter2DFit{T} <: AbstractEmitter
    x::T             # µm
    y::T             # µm
    photons::T       # fitted signal, in the units of the data the fitter received
    bg::T            # fitted background per pixel, in the same units
    σ_x::T           # standard deviation of x, µm
    σ_y::T           # standard deviation of y, µm
    σ_xy::T          # covariance of x and y, µm² (0 = axis-aligned)
    σ_photons::T     # standard deviation of photons
    σ_bg::T          # standard deviation of bg
    frame::Int       # 1-based
    dataset::Int     # 1-based
    track_id::Int    # 0 = unlinked
    id::Int          # 0 = not set
end

mutable struct Emitter3DFit{T} <: AbstractEmitter
    x::T             # µm
    y::T             # µm
    z::T             # µm
    photons::T       # fitted signal, in the units of the data the fitter received
    bg::T            # fitted background per pixel, in the same units
    σ_x::T           # standard deviation of x, µm
    σ_y::T           # standard deviation of y, µm
    σ_z::T           # standard deviation of z, µm
    σ_xy::T          # covariance of x and y, µm²
    σ_xz::T          # covariance of x and z, µm²
    σ_yz::T          # covariance of y and z, µm²
    σ_photons::T     # standard deviation of photons
    σ_bg::T          # standard deviation of bg
    frame::Int       # 1-based
    dataset::Int     # 1-based
    track_id::Int    # 0 = unlinked
    id::Int          # 0 = not set
end

struct IdealCamera{T} <: AbstractCamera
    pixel_edges_x::Vector{T}   # µm, from 0, one more than the number of pixels
    pixel_edges_y::Vector{T}   # µm, from 0, one more than the number of pixels
end

struct SCMOSCamera{T<:Real} <: AbstractCamera
    pixel_edges_x::Vector{T}         # µm
    pixel_edges_y::Vector{T}         # µm
    offset::Union{T, Matrix{T}}      # ADU; a scalar or a (ny, nx) map
    gain::Union{T, Matrix{T}}        # e⁻/ADU
    readnoise::Union{T, Matrix{T}}   # e⁻ rms
    qe::Union{T, Matrix{T}}          # 0 to 1
end

struct SingleROI{T}
    data::Matrix{T}              # [y, x], the camera's raw units
    corner::SVector{2,Int32}     # (column, row) of the ROI's top-left pixel, 1-based
    frame_idx::Int32             # 1-based
end

struct ROIBatch{T,N,A<:AbstractArray{T,N},C<:AbstractCamera}
    data::A                      # (roi_size, roi_size, n_rois), [y, x, roi]
    x_corners::Vector{Int32}     # camera column of each ROI's top-left pixel, 1-based
    y_corners::Vector{Int32}     # camera row of each ROI's top-left pixel, 1-based
    frame_indices::Vector{Int32} # 1-based
    camera::C                    # the camera of the full image
    roi_size::Int                # pixels
end

struct BasicSMLD{T,E<:AbstractEmitter} <: AbstractSMLD
    emitters::Vector{E}
    camera::AbstractCamera
    n_frames::Int
    n_datasets::Int
    metadata::Dict{String,Any}
end
```

## Constructing Values

### Emitters

```julia
using SMLMCore

e2d = Emitter2D{Float64}(1.5, 2.3, 1000.0)          # x, y (µm), photons
e3d = Emitter3D{Float64}(1.5, 2.3, -0.5, 1000.0)    # x, y, z (µm), photons

# Fit results: x, y, photons, bg, σ_x, σ_y, σ_photons, σ_bg, then keywords
fit2d = Emitter2DFit{Float64}(1.5, 2.3, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0;
    σ_xy = 0.005, frame = 5, dataset = 1, track_id = 2, id = 42)
fit3d = Emitter3DFit{Float64}(1.5, 2.3, -0.5, 1000.0, 10.0, 0.01, 0.01, 0.02, 50.0, 2.0;
    σ_xy = 0.005, σ_xz = 0.002, σ_yz = 0.003, frame = 5)
```

The keyword constructors need their positional values already of type `T`: write `1000.0`,
not `1000`. Keyword defaults: `σ_xy = σ_xz = σ_yz = 0`, `frame = 1`, `dataset = 1`,
`track_id = 0`, `id = 0`.

### Cameras

```julia
cam = IdealCamera(512, 512, 0.1)                # 512 × 512 pixels of 0.1 µm
cam_rect = IdealCamera(512, 256, (0.1, 0.12))   # rectangular pixels, (size_x, size_y)

# sCMOS: readnoise is required; offset, gain and qe default to 0, 1 and 1
cam_scmos = SCMOSCamera(512, 512, 0.1, 1.6)     # 1.6 e⁻ rms, the same for every pixel

# A 2048 × 2048 sensor of 6.5 µm pixels behind a 100× objective: 0.065 µm at the sample
cam_spec = SCMOSCamera(2048, 2048, 0.065, 1.6; offset = 100.0, gain = 0.46, qe = 0.72)

# Per-pixel maps have size (ny, nx) and the number type of pixel_size
readnoise_map = 1.6 .+ 0.2 .* rand(512, 512)
qe_map = fill(0.8, 512, 512)
cam_maps = SCMOSCamera(512, 512, 0.1, readnoise_map; offset = 100.0, gain = 0.5, qe = qe_map)
```

- `IdealCamera(1:512, 1:512, 0.1)` gives the same camera as `IdealCamera(512, 512, 0.1)`: only
  the ranges' lengths are used, and the edges always start at 0.
- In an `SCMOSCamera` call, `pixel_size`, `readnoise`, `offset`, `gain` and `qe` share one
  number type, the type of `pixel_size`. A call that mixes number types fails: with an
  `UndefVarError` (`T` not defined) when scalars of different types are passed positionally, a
  `MethodError` for a map of another element type, and a `TypeError` for a keyword. Convert the
  values first, and write `offset = 100.0`, not `100`.
- `SCMOSCamera(pixel_edges_x, pixel_edges_y; readnoise, offset, gain, qe)` builds a camera from
  its pixel edges (µm), which need not be uniform.

### ROI Batches

```julia
camera = IdealCamera(512, 512, 0.1)
data = rand(Float32, 11, 11, 100)              # 100 ROIs of 11 × 11 pixels, [y, x, roi]
x_corners = rand(Int32(1):Int32(500), 100)     # camera column of each ROI's top-left pixel
y_corners = rand(Int32(1):Int32(500), 100)     # camera row
frame_indices = rand(Int32(1):Int32(50), 100)
batch = ROIBatch(data, x_corners, y_corners, frame_indices, camera)

# From single ROIs: SingleROI{T} converts a tuple corner and an integer frame
rois = [SingleROI{Float32}(rand(Float32, 11, 11), (10i, 10i), i) for i in 1:100]
batch2 = ROIBatch(rois, camera)

roi = batch[5]                          # a SingleROI
n_rois = length(batch)                  # 100
frames = [r.frame_idx for r in batch]   # iterating gives the ROIs in order
```

The corner and frame vectors may hold any integer type; they are converted to `Int32`. ROIs
must be square (else an `ArgumentError`), and each vector needs one entry per ROI (else a
`DimensionMismatch`).

On a GPU, only `data` moves; the corners, frame indices and camera stay on the host. Indexing
and iteration need `data` on the host; use `Adapt.adapt(Array, batch_gpu)` first:

```julia
using Adapt, CUDA          # both must be added to the environment: Pkg.add(["Adapt", "CUDA"])
batch_gpu = Adapt.adapt(CuArray, batch)
batch_host = Adapt.adapt(Array, batch_gpu)   # before batch_host[k] or iterating
```

Typical workflow:
1. SMLMBoxer extracts ROIs into an `ROIBatch`.
2. `smld, info = GaussMLE.fit(batch)` fits them and returns a `BasicSMLD`.

### SMLD Containers

```julia
emitters = [
    Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0; frame = 1),
    Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.03, 0.03, 60.0, 2.0; frame = 2),
]
smld = BasicSMLD(emitters, cam, 2, 1)    # 2 frames, 1 dataset

# metadata must be a Dict{String,Any}
smld_meta = BasicSMLD(emitters, cam, 2, 1,
    Dict{String,Any}("exposure_time" => 0.1, "sample" => "test"))

n_emitters = length(smld)    # number of emitters
for e in smld                # iterating an SMLD iterates its emitters
    println("Emitter at ($(e.x), $(e.y)) µm with $(e.photons) photons")
end
```

`BasicSMLD{T,E}`'s `T` is the element type of the camera's pixel edges, not of the emitters.
A plain `Dict("exposure_time" => 0.1)` is a `Dict{String,Float64}` and has no matching method.

## Core Functions

### Accessing the API Overview

```julia
overview_text = SMLMCore.api_overview()   # this overview as a String; not exported
```

### Coordinate Conversions

```julia
pixel_to_physical(1, 1, 0.1)             # (0.05, 0.05): the center of pixel (1, 1), µm
physical_to_pixel(0.05, 0.25, 0.1)       # (1.0, 3.0): pixel coordinates (column, row)
physical_to_pixel_index(0.0, 0.0, 0.1)   # (1, 1): the pixel that holds the position
centers_x, centers_y = get_pixel_centers(cam)               # every pixel center, µm
edges_x, edges_y = compute_bin_edges(1:512, 1:512, 0.1)    # pixel edges, µm, from 0
```

- `pixel_to_physical`, `physical_to_pixel` and `physical_to_pixel_index` take one scalar pixel
  size: square pixels with the edges at 0. `get_pixel_centers` works for any camera.
- `physical_to_pixel_index` returns the pixel that holds the position: along each axis, pixel
  `n` covers `[(n - 1)·pixel_size, n·pixel_size)`, up to floating-point rounding (a position
  computed as `(n - 1) * pixel_size` can fall in pixel `n - 1`). It does not check bounds.
- `pixel_to_physical` returns `pixel_size`'s type, so `pixel_size` must be a float.

### Filtering Operations

```julia
bright = @filter(smld, photons > 1000)                     # select bright emitters
precise = @filter(smld, σ_x < 0.02 && σ_y < 0.02)          # select precise localizations
inside = @filter(smld, 0.5 <= x <= 2.0 && frame in (1, 2)) # chained comparison, tuple

frame_2 = filter_frames(smld, 2)              # one frame
early_frames = filter_frames(smld, 1:10)      # a range of frames
some_frames = filter_frames(smld, [1, 3, 5])  # a vector of frames

region = filter_roi(smld, (0.0, 2.0), (1.0, 3.0))   # x and y bounds, µm, inclusive
# 3D emitters: filter_roi(smld3d, (0.0, 2.0), (1.0, 3.0), (-0.5, 0.5))

# A threshold held in a variable: filter the emitters directly
threshold = 1000.0
bright2 = BasicSMLD(filter(e -> e.photons > threshold, smld.emitters), smld.camera,
                    smld.n_frames, smld.n_datasets, copy(smld.metadata))
```

- In `@filter`, every name in the condition is read as an emitter property, except the
  operators `<`, `>`, `<=`, `>=`, `==`, `!=`, `in` and `∈`, and `&&` and `||`. A condition
  therefore holds only property names, number literals and tuples. It cannot use a variable
  (`photons > threshold` reads `e.threshold`), a function (`abs(x)`), arithmetic (`x + y`), `!`,
  a range (`frame in 1:10`) or `≤` and `≥`; each throws an error that names the missing field
  (a `FieldError` from Julia 1.12, an `ErrorException` before).
- Properties: `x`, `y`, `z` (3D), `photons`; for the fit types also `bg`, `σ_x`, `σ_y`, `σ_z`,
  `σ_xy`, `σ_xz` and `σ_yz` (3D), `σ_photons`, `σ_bg`, `frame`, `dataset`, `track_id`, `id`.
- `filter_frames` needs a `frame` field (`Emitter2DFit`, `Emitter3DFit`); `Emitter2D` and
  `Emitter3D` throw an error that names the missing field.
- `filter_roi` bounds are inclusive. A range's smallest and largest elements are the bounds, so
  `0.0:0.3:1.0` stops at 0.9; prefer tuples. The 2D form needs 2D emitters and the 3D form 3D
  emitters.

```julia
# Spatial dimension: what the type declares (SMLMCore's emitter types declare 2 or 3), else 3
# if an emitter has a property z and 2 if not. A collection takes its element type's
# declaration, else the dimension all its elements share; nothing when they disagree, or when
# it is empty and its element type declares none. Works for emitter types from other packages.
emitter_ndims(smld)                                 # 2
emitter_ndims(Emitter3DFit{Float64})                # 3
emitter_ndims(SMLMCore.AbstractEmitter[e2d, e3d])   # nothing: mixed 2D/3D
```

### SMLD Operations

```julia
smld_a = BasicSMLD([Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0;
                    frame = 3)], cam, 10, 1)
smld_b = BasicSMLD([Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0;
                    frame = 3)], cam, 10, 1)

# Concatenate, keeping every frame and dataset number
combined = cat_smld(smld_a, smld_b)
combined = cat_smld([smld_a, smld_b])

# Merge: without renumbering, the same emitters as cat_smld
merged = merge_smld(smld_a, smld_b)

# Each input's frames after the earlier inputs' frames: frames 3 and 13, n_frames 20
by_frame = merge_smld([smld_a, smld_b]; adjust_frames = true)

# Each input's datasets after the earlier inputs' datasets: datasets 1 and 2
by_dataset = merge_smld([smld_a, smld_b]; adjust_datasets = true)
```

- Both functions require the same camera (the same type and equal values in every field,
  calibration included) and the same emitter type.
- Renumbering moves each input by the earlier inputs' total `n_frames` (or `n_datasets`), and
  needs a `frame` (or `dataset`) property; `Emitter2D` and `Emitter3D` have neither. The inputs
  are never modified.
- Metadata is a copy of the first input's, plus `"concatenated_from"` (`cat_smld`) or
  `"merged_from"`, `"frame_adjustment"` and `"dataset_adjustment"` (`merge_smld`). The other
  inputs' metadata are dropped.
- With one input, the result is a new SMLD with those keys; an empty vector throws an
  `ErrorException`.

### Working with SMLD Objects

```julia
n_emitters = length(smld)                  # number of emitters
xs = [e.x for e in smld]                   # iterate over emitters
show(stdout, smld)                         # compact view
show(stdout, MIME("text/plain"), smld)     # detailed view
```

## Complete Example

```julia
using SMLMCore

# 1. A camera of 512 × 512 pixels, each 0.1 µm at the sample
cam = IdealCamera(512, 512, 0.1)

# 2. Emitters: fitted localizations (positions in µm)
emitters = [
    # Emitter at (1.0, 2.0) µm with high precision
    Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0),

    # Bright emitter at (3.0, 4.0) µm
    Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0),

    # Dimmer emitter at (5.0, 6.0) µm with lower precision
    Emitter2DFit{Float64}(5.0, 6.0, 800.0, 9.0, 0.03, 0.03, 40.0, 1.5)
]

# 3. An SMLD container that holds them
smld = BasicSMLD(
    emitters,                              # Vector of emitters
    cam,                                   # Camera geometry
    1,                                     # Number of frames
    1,                                     # Number of datasets
    Dict{String,Any}("sample" => "Test")   # Metadata
)

# 4. Select bright emitters (a new SMLD)
bright = @filter(smld, photons > 900)

# 5. Select a region: x ∈ [0, 4] µm, y ∈ [1, 5] µm
roi = filter_roi(bright, (0.0, 4.0), (1.0, 5.0))

# 6. Examine the results
println("Original dataset: $(length(smld)) emitters")
println("After filtering by brightness: $(length(bright)) emitters")
println("After ROI selection: $(length(roi)) emitters")

# 7. Access individual emitters
for (i, emitter) in enumerate(roi)
    println("Emitter $i: position=($(emitter.x), $(emitter.y)) μm, photons=$(emitter.photons)")
end

# Output:
# Original dataset: 3 emitters
# After filtering by brightness: 2 emitters
# After ROI selection: 2 emitters
# Emitter 1: position=(1.0, 2.0) μm, photons=1000.0
# Emitter 2: position=(3.0, 4.0) μm, photons=1200.0
```

## Common Pitfalls and Important Notes

### Coordinates
- **Positions are always in µm**, not nanometers or pixels, and `pixel_size` is the pixel's
  size at the sample.
- **Pixel indices, frame numbers and dataset numbers start at 1.**
- The origin `(0, 0)` is the **top-left corner** of the camera; x is the column and y the row.
- Per-pixel maps and ROI data are indexed `[row, col] = [y, x]`. A transposed map on a square
  sensor raises no error.

### Types
- The emitter keyword constructors need their positional values already of type `T`.
- `SCMOSCamera` arguments share one number type. A call that mixes number types fails: with an
  `UndefVarError` (`T` not defined) when scalars of different types are passed positionally, a
  `MethodError` for a map of another element type, and a `TypeError` for a keyword.
- `BasicSMLD` infers `T` from the camera's pixel edges, and its metadata must be a
  `Dict{String,Any}`.

### Filtering
- `@filter`, `filter_roi` and `filter_frames` return a new SMLD with a new emitter vector, but
  its emitters are the input's own mutable objects: setting `bright.emitters[1].photons = 0`
  changes `smld` as well. `deepcopy` the result before changing emitters in place. `cat_smld`
  and `merge_smld` share emitters with their inputs in the same way, except renumbered ones.
- A variable in an `@filter` condition is read as an emitter property; filter
  `smld.emitters` with `filter` instead.
- Applying an ROI filter of the wrong dimension, or `filter_frames` to emitters without a
  `frame` field, throws an error.

### Common Mistakes

```julia
# WRONG: pixel units instead of µm
emitter = Emitter2D{Float64}(100.0, 200.0, 1000.0)   # likely pixel coordinates

# CORRECT: positions in µm
emitter = Emitter2D{Float64}(10.0, 20.0, 1000.0)

# PITFALL: filtered and concatenated SMLDs share emitter objects with their inputs
bright = @filter(smld, photons > 1000)
bright.emitters[1].photons = 0.0   # also changes smld's emitter
safe = deepcopy(bright)            # change this one instead
```
