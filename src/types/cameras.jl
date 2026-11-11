"""
    AbstractCamera

Supertype of all camera types. A camera gives the pixel geometry of the full image.

A concrete camera type has the fields `pixel_edges_x` and `pixel_edges_y`: the pixel edges in µm,
increasing, `N + 1` of them for `N` pixels, starting at the camera's top-left corner, `(0, 0)`.
Pixels need not be uniform. Constructors do not check that the edges increase from 0;
`physical_to_pixel*`, the uniform-pixel formulas and `IdealCamera`'s display assume it.
[Pixels and coordinates](@ref) gives the convention.
"""
abstract type AbstractCamera end

# Edges of `length(centers)` pixels of width `pixel_size` (µm), the first at 0, in the type of
# `pixel_size`. Only the length of `centers` is used.
function compute_edges_1d(centers::AbstractUnitRange, pixel_size::T) where T<:Real
    n_centers = length(centers)
    edges = Vector{T}(undef, n_centers + 1)
    
    # First edge starts at 0
    edges[1] = zero(T)
    
    # Each subsequent edge is one pixel_size further
    for i in 1:n_centers
        edges[i + 1] = T(i) * pixel_size
    end
    
    return edges
end

"""
    compute_bin_edges(centers_x, centers_y, pixel_size) -> (edges_x, edges_y)

Return the pixel edges in x and y (µm) of `length(centers_x)` × `length(centers_y)` pixels of
`pixel_size` µm, the first edge at 0.

`pixel_size` is a number (square pixels) or a tuple `(size_x, size_y)` (rectangular pixels).
Only the lengths of `centers_x` and `centers_y` (`AbstractUnitRange`s) are used. Each edge
vector has the type of its pixel size.

# Example
```jldoctest
julia> compute_bin_edges(1:3, 1:2, (0.5, 0.25))
([0.0, 0.5, 1.0, 1.5], [0.0, 0.25, 0.5])
```
"""
function compute_bin_edges(centers_x::AbstractUnitRange, centers_y::AbstractUnitRange, pixel_size::T) where T
    edges_x = compute_edges_1d(centers_x, pixel_size)
    edges_y = compute_edges_1d(centers_y, pixel_size)
    return edges_x, edges_y
end

function compute_bin_edges(centers_x::AbstractUnitRange, centers_y::AbstractUnitRange, pixel_size::Tuple{Real, Real})
    edges_x = compute_edges_1d(centers_x, pixel_size[1])
    edges_y = compute_edges_1d(centers_y, pixel_size[2])
    return edges_x, edges_y
end

"""
    IdealCamera{T} <: AbstractCamera

A camera with a regular pixel grid and Poisson noise only, defined by its pixel edges.

# Fields
- `pixel_edges_x::Vector{T}`: pixel edges in x (µm), from 0, one more than the number of pixels
- `pixel_edges_y::Vector{T}`: pixel edges in y (µm), from 0, one more than the number of pixels

Pixel `(x, y) = (col, row)` is centered at `((col - 0.5)·Δx, (row - 0.5)·Δy)` µm, where `Δx` and
`Δy` are the pixel sizes; see [Pixels and coordinates](@ref).

# Constructors
- `IdealCamera(nx, ny, pixel_size)`: `nx` × `ny` pixels of `pixel_size` µm at the sample.
  `pixel_size` is a number (square pixels) or a tuple `(size_x, size_y)` of one type
  (rectangular pixels); `T` is its type.
- `IdealCamera(pixel_centers_x, pixel_centers_y, pixel_size)`: the same, with the pixel counts
  given as `AbstractUnitRange`s. Only their lengths are used; the edges always start at 0, so
  `101:612` gives the same camera as `1:512`.
- `IdealCamera(pixel_edges_x, pixel_edges_y)`: from the edges themselves (µm, `Vector{T}`).

# Example
```jldoctest
julia> cam = IdealCamera(512, 512, 0.1)
IdealCamera{Float64} with:
  Dimensions: 512 × 512 pixels
  Pixel size: 0.1 μm
  Field of view: 51.2 × 51.2 μm

julia> cam.pixel_edges_x[1:3]
3-element Vector{Float64}:
 0.0
 0.1
 0.2
```

# See also
[`SCMOSCamera`](@ref), [`get_pixel_centers`](@ref)
"""
struct IdealCamera{T} <: AbstractCamera
    pixel_edges_x::Vector{T}  # pixel edges in x
    pixel_edges_y::Vector{T}  # pixel edges in y
end

function IdealCamera(pixel_centers_x::AbstractUnitRange, 
                    pixel_centers_y::AbstractUnitRange, 
                    pixel_size::T) where T<:Real
    edges_x, edges_y = compute_bin_edges(pixel_centers_x, pixel_centers_y, pixel_size)
    return IdealCamera{T}(edges_x, edges_y)
end

function IdealCamera(pixel_centers_x::AbstractUnitRange,
                    pixel_centers_y::AbstractUnitRange,
                    pixel_size::Tuple{T, T}) where T<:Real
    edges_x = compute_edges_1d(pixel_centers_x, pixel_size[1])
    edges_y = compute_edges_1d(pixel_centers_y, pixel_size[2])
    return IdealCamera{T}(edges_x, edges_y)
end

function IdealCamera(n_pixels_x::Integer, n_pixels_y::Integer, pixel_size::T) where T<:Real
    pixel_centers_x = 1:n_pixels_x
    pixel_centers_y = 1:n_pixels_y
    return IdealCamera(pixel_centers_x, pixel_centers_y, pixel_size)
end

function IdealCamera(n_pixels_x::Integer, n_pixels_y::Integer, pixel_size::Tuple{T, T}) where T<:Real
    pixel_centers_x = 1:n_pixels_x
    pixel_centers_y = 1:n_pixels_y
    return IdealCamera(pixel_centers_x, pixel_centers_y, pixel_size)
end


# Standard show method (used in arrays and collections)
function Base.show(io::IO, camera::IdealCamera{T}) where T
    n_pixels_x = length(camera.pixel_edges_x) - 1
    n_pixels_y = length(camera.pixel_edges_y) - 1
    pixel_size_x = round(camera.pixel_edges_x[2] - camera.pixel_edges_x[1], digits=4)
    pixel_size_y = round(camera.pixel_edges_y[2] - camera.pixel_edges_y[1], digits=4)
    
    if pixel_size_x ≈ pixel_size_y
        print(io, "IdealCamera{$T}($(n_pixels_x)×$(n_pixels_y), $(pixel_size_x)μm)")
    else
        print(io, "IdealCamera{$T}($(n_pixels_x)×$(n_pixels_y), $(pixel_size_x)×$(pixel_size_y)μm)")
    end
end

# Detailed show method (used at REPL and when explicitly showing)
function Base.show(io::IO, ::MIME"text/plain", camera::IdealCamera{T}) where T
    n_pixels_x = length(camera.pixel_edges_x) - 1
    n_pixels_y = length(camera.pixel_edges_y) - 1
    pixel_size_x = round(camera.pixel_edges_x[2] - camera.pixel_edges_x[1], digits=4)
    pixel_size_y = round(camera.pixel_edges_y[2] - camera.pixel_edges_y[1], digits=4)
    
    x_size = round(camera.pixel_edges_x[end] - camera.pixel_edges_x[1], digits=2)
    y_size = round(camera.pixel_edges_y[end] - camera.pixel_edges_y[1], digits=2)
    
    println(io, "IdealCamera{$T} with:")
    println(io, "  Dimensions: $(n_pixels_x) × $(n_pixels_y) pixels")
    
    if pixel_size_x ≈ pixel_size_y
        println(io, "  Pixel size: $(pixel_size_x) μm")
    else
        println(io, "  Pixel size: $(pixel_size_x) × $(pixel_size_y) μm")
    end
    
    print(io, "  Field of view: $(x_size) × $(y_size) μm")
end

"""
    SCMOSCamera{T<:Real} <: AbstractCamera

An sCMOS camera: the pixel geometry and the calibration of each pixel, in the units of a
camera's specification sheet.

# Fields
- `pixel_edges_x::Vector{T}`, `pixel_edges_y::Vector{T}`: pixel edges (µm), as for
  [`IdealCamera`](@ref)
- `offset::Union{T, Matrix{T}}`: dark level (ADU)
- `gain::Union{T, Matrix{T}}`: conversion gain (e⁻/ADU)
- `readnoise::Union{T, Matrix{T}}`: read noise (e⁻ rms)
- `qe::Union{T, Matrix{T}}`: quantum efficiency (0 to 1)

Each calibration field is a scalar, the same for every pixel, or a map of size `(ny, nx)` indexed
`[row, col] = [y, x]`, the same order as the camera image. A square sensor's map cannot be
checked for orientation: a transposed map is accepted silently. [sCMOS calibration](@ref) gives
the signal chain these parameters describe.

# Constructors
- `SCMOSCamera(nx, ny, pixel_size, readnoise; offset=zero(T), gain=one(T), qe=one(T))`: `nx` ×
  `ny` pixels of `pixel_size` µm at the sample, a number or a tuple `(size_x, size_y)`.
- `SCMOSCamera(pixel_edges_x, pixel_edges_y; readnoise, offset=zero(T), gain=one(T), qe=one(T))`:
  from pixel edges (µm, `Vector{T}`), which need not be uniform; `readnoise` is required.

`pixel_size` (or the edges), `readnoise`, `offset`, `gain` and `qe` share one number type `T`,
the type of `pixel_size`: write `offset = 100.0`, not `100`, and pass maps as `Matrix{T}`. A call
that mixes number types fails: with an `UndefVarError` (`T` not defined) when scalars of
different types are passed positionally, a `MethodError` for a map of another element type, and
a `TypeError` for a keyword. A map of the wrong size throws a `DimensionMismatch`.

# Example
A 2048 × 2048 sensor of 6.5 µm pixels behind a 100× objective has pixels of 0.065 µm at the
sample:
```jldoctest
julia> SCMOSCamera(2048, 2048, 0.065, 1.6; offset = 100.0, gain = 0.46, qe = 0.72)
SCMOSCamera{Float64} with:
  Dimensions: 2048 × 2048 pixels
  Pixel size: 0.065 μm
  Offset: uniform
  Gain: uniform
  Read noise: uniform
  QE: uniform
```

A read-noise map for a sensor of 512 columns and 256 rows has size `(256, 512)`:
```jldoctest
julia> readnoise_map = fill(1.6, 256, 512);

julia> cam = SCMOSCamera(512, 256, 0.1, readnoise_map; offset = 100.0, gain = 0.5);

julia> size(cam.readnoise), cam.offset
((256, 512), 100.0)
```

# See also
[`IdealCamera`](@ref)
"""
struct SCMOSCamera{T<:Real} <: AbstractCamera
    pixel_edges_x::Vector{T}
    pixel_edges_y::Vector{T}
    offset::Union{T, Matrix{T}}
    gain::Union{T, Matrix{T}}
    readnoise::Union{T, Matrix{T}}
    qe::Union{T, Matrix{T}}
end

function SCMOSCamera(
    nx::Integer,
    ny::Integer,
    pixel_size::Union{T, Tuple{T,T}},
    readnoise::Union{T, Matrix{T}};
    offset::Union{T, Matrix{T}} = zero(T),
    gain::Union{T, Matrix{T}} = one(T),
    qe::Union{T, Matrix{T}} = one(T)
) where T<:Real

    # Compute pixel edges
    if pixel_size isa Tuple
        edges_x = collect(range(zero(T), nx * pixel_size[1], length=nx+1))
        edges_y = collect(range(zero(T), ny * pixel_size[2], length=ny+1))
    else
        edges_x = collect(range(zero(T), nx * pixel_size, length=nx+1))
        edges_y = collect(range(zero(T), ny * pixel_size, length=ny+1))
    end

    # Validate dimensions
    _validate_camera_param(offset, nx, ny, "offset")
    _validate_camera_param(gain, nx, ny, "gain")
    _validate_camera_param(readnoise, nx, ny, "readnoise")
    _validate_camera_param(qe, nx, ny, "qe")

    return SCMOSCamera{T}(edges_x, edges_y, offset, gain, readnoise, qe)
end

function SCMOSCamera(
    pixel_edges_x::Vector{T},
    pixel_edges_y::Vector{T};
    readnoise::Union{T, Matrix{T}},
    offset::Union{T, Matrix{T}} = zero(T),
    gain::Union{T, Matrix{T}} = one(T),
    qe::Union{T, Matrix{T}} = one(T)
) where T<:Real

    nx = length(pixel_edges_x) - 1
    ny = length(pixel_edges_y) - 1

    # Validate dimensions
    _validate_camera_param(offset, nx, ny, "offset")
    _validate_camera_param(gain, nx, ny, "gain")
    _validate_camera_param(readnoise, nx, ny, "readnoise")
    _validate_camera_param(qe, nx, ny, "qe")

    return SCMOSCamera{T}(pixel_edges_x, pixel_edges_y, offset, gain, readnoise, qe)
end

# Validation helper
# Matrix parameters use Julia standard (row, col) = (y, x) convention
# So for a camera with nx columns and ny rows, matrices should be (ny, nx)
function _validate_camera_param(param::AbstractMatrix, nx, ny, name)
    size(param) == (ny, nx) ||
        throw(DimensionMismatch("$name size $(size(param)) must match ($ny, $nx) [rows, cols]"))
end
_validate_camera_param(param::Real, nx, ny, name) = nothing

# Display methods
function Base.show(io::IO, cam::SCMOSCamera{T}) where T
    nx = length(cam.pixel_edges_x) - 1
    ny = length(cam.pixel_edges_y) - 1
    px = round(cam.pixel_edges_x[2] - cam.pixel_edges_x[1], digits=4)
    py = round(cam.pixel_edges_y[2] - cam.pixel_edges_y[1], digits=4)

    psize_str = px ≈ py ? "$(px)μm" : "$(px)×$(py)μm"
    print(io, "SCMOSCamera{$T}($(nx)×$(ny), $(psize_str))")
end

function Base.show(io::IO, ::MIME"text/plain", cam::SCMOSCamera{T}) where T
    nx = length(cam.pixel_edges_x) - 1
    ny = length(cam.pixel_edges_y) - 1
    px = round(cam.pixel_edges_x[2] - cam.pixel_edges_x[1], digits=4)
    py = round(cam.pixel_edges_y[2] - cam.pixel_edges_y[1], digits=4)

    println(io, "SCMOSCamera{$T} with:")
    println(io, "  Dimensions: $(nx) × $(ny) pixels")

    if px ≈ py
        println(io, "  Pixel size: $(px) μm")
    else
        println(io, "  Pixel size: $(px) × $(py) μm")
    end

    # Show parameter types (scalar vs matrix)
    offset_type = cam.offset isa T ? "uniform" : "per-pixel"
    gain_type = cam.gain isa T ? "uniform" : "per-pixel"
    readnoise_type = cam.readnoise isa T ? "uniform" : "per-pixel"
    qe_type = cam.qe isa T ? "uniform" : "per-pixel"

    println(io, "  Offset: $(offset_type)")
    println(io, "  Gain: $(gain_type)")
    println(io, "  Read noise: $(readnoise_type)")
    print(io, "  QE: $(qe_type)")
end

