"""
    AbstractCamera

Supertype of all camera types. A camera gives the pixel geometry of the full image.

A concrete camera type has the fields `pixel_edges_x` and `pixel_edges_y`: the pixel edges in µm,
increasing, `N + 1` of them for `N` pixels, starting at the camera's top-left corner, `(0, 0)`.
Pixels need not be uniform. Constructors do not check that the edges increase from 0;
`physical_to_pixel*` and the uniform-pixel formulas assume it, and the cameras' displays assume
uniform pixels (they report the first pixel's width). A camera of a crop of the sensor is the
exception: its edges start at the crop's corner in sensor µm, so for uniform square pixels
`physical_to_pixel*` give sensor pixel numbers for it. [Pixels and coordinates](@ref) gives the
convention.
"""
abstract type AbstractCamera end

# Pixel counts must not be negative: `1:-1` would silently give a camera with no pixels.
_check_count(nx, ny) = (nx >= 0 && ny >= 0) ||
    throw(ArgumentError("a camera needs pixel counts of 0 or more, not ($nx, $ny)"))

# Edges of `length(centers)` pixels of width `pixel_size` (µm), the first at 0, in the type of
# `pixel_size`. `centers` numbers a whole sensor's pixels from 0 or from 1; any other start
# would be a crop, whose edges do not start at 0, so it is refused.
function compute_edges_1d(centers::AbstractUnitRange, pixel_size::T) where T<:Real
    first(centers) in (0, 1) || throw(ArgumentError(
        "pixel range $centers starts at $(first(centers)): a pixel range numbers a whole " *
        "sensor's pixels from 0 or from 1, and its edges start at 0 µm. For a cropped camera, " *
        "pass the crop's pixel edges in µm: IdealCamera(pixel_edges_x, pixel_edges_y)"))
    n_centers = length(centers)
    edges = Vector{T}(undef, n_centers + 1)

    # First edge starts at 0
    edges[1] = zero(T)

    # Each subsequent edge is one pixel_size further; whole-number edges are checked, so one that
    # does not fit `T` throws instead of wrapping
    for i in 1:n_centers
        edges[i + 1] = T <: Integer ? Base.checked_mul(T(i), pixel_size) : T(i) * pixel_size
    end

    return edges
end

"""
    compute_bin_edges(centers_x, centers_y, pixel_size) -> (edges_x, edges_y)

Return the pixel edges in x and y (µm) of `length(centers_x)` × `length(centers_y)` pixels of
`pixel_size` µm, the first edge at 0.

`pixel_size` is a number (square pixels) or a tuple `(size_x, size_y)` (rectangular pixels).
`centers_x` and `centers_y` (`AbstractUnitRange`s) number a whole sensor's pixels from 0 or
from 1, so `0:2` and `1:3` give the same edges; a range that starts anywhere else throws an
`ArgumentError`. Each edge vector has the type of its pixel size.

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
- `pixel_edges_x::Vector{T}`: pixel edges in x (µm), one more than the number of pixels; from 0
  for a whole sensor, from the crop's corner for a crop
- `pixel_edges_y::Vector{T}`: pixel edges in y (µm), likewise

Pixel `(x, y) = (col, row)` is centered at `(x0 + (col - 0.5)·Δx, y0 + (row - 0.5)·Δy)` µm,
where `Δx` and `Δy` are the pixel sizes and `(x0, y0)` the first edges (0 for a whole sensor,
the crop's corner for a crop); see [Pixels and coordinates](@ref).

# Constructors
- `IdealCamera(nx, ny, pixel_size)`: `nx` × `ny` pixels of `pixel_size` µm at the sample.
  `pixel_size` is a number (square pixels) or a tuple `(size_x, size_y)` of one type
  (rectangular pixels); `T` is its type.
- `IdealCamera(pixel_centers_x, pixel_centers_y, pixel_size)`: the same, with the whole
  sensor's pixels numbered by `AbstractUnitRange`s from 0 or from 1, so `0:511` and `1:512`
  give the same camera as `512`. A range that starts anywhere else throws an `ArgumentError`:
  a camera's edges start at 0, so a crop such as `101:612` is not a range camera.
- `IdealCamera(pixel_edges_x, pixel_edges_y)`: from the edges themselves (µm, `Vector{T}`).
  A cropped camera is built this way, from the crop's edges; `physical_to_pixel*` assume edges
  from 0 (see [Pixels and coordinates](@ref)).

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
    _check_count(n_pixels_x, n_pixels_y)
    pixel_centers_x = 1:n_pixels_x
    pixel_centers_y = 1:n_pixels_y
    return IdealCamera(pixel_centers_x, pixel_centers_y, pixel_size)
end

function IdealCamera(n_pixels_x::Integer, n_pixels_y::Integer, pixel_size::Tuple{T, T}) where T<:Real
    _check_count(n_pixels_x, n_pixels_y)
    pixel_centers_x = 1:n_pixels_x
    pixel_centers_y = 1:n_pixels_y
    return IdealCamera(pixel_centers_x, pixel_centers_y, pixel_size)
end


# For display: the pixel count along one side, the first pixel's width (cameras are shown as
# uniform; `nothing` for a side with no pixels), the side's extent, and the pixel size as text.
_shown_count(edges) = max(length(edges) - 1, 0)
_shown_width(edges) = length(edges) < 2 ? nothing : round(edges[2] - edges[1], digits=4)
_shown_extent(edges) = length(edges) < 2 ? 0 : round(edges[end] - edges[1], digits=2)
function _shown_pixel_size(px, py, sep, none)
    (px === nothing || py === nothing) && return none
    return px ≈ py ? "$(px)$(sep)μm" : "$(px)$(sep)×$(sep)$(py)$(sep)μm"
end

# Standard show method (used in arrays and collections)
function Base.show(io::IO, camera::IdealCamera{T}) where T
    nx, ny = _shown_count(camera.pixel_edges_x), _shown_count(camera.pixel_edges_y)
    psize = _shown_pixel_size(_shown_width(camera.pixel_edges_x), _shown_width(camera.pixel_edges_y),
                              "", "no pixels")
    print(io, "IdealCamera{$T}($(nx)×$(ny), $(psize))")
end

# Detailed show method (used at REPL and when explicitly showing)
function Base.show(io::IO, ::MIME"text/plain", camera::IdealCamera{T}) where T
    nx, ny = _shown_count(camera.pixel_edges_x), _shown_count(camera.pixel_edges_y)
    psize = _shown_pixel_size(_shown_width(camera.pixel_edges_x), _shown_width(camera.pixel_edges_y),
                              " ", "none (no pixels)")
    x_size, y_size = _shown_extent(camera.pixel_edges_x), _shown_extent(camera.pixel_edges_y)

    println(io, "IdealCamera{$T} with:")
    println(io, "  Dimensions: $(nx) × $(ny) pixels")
    println(io, "  Pixel size: $(psize)")
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
- `SCMOSCamera(nx, ny, pixel_size, readnoise; offset=0, gain=1, qe=1)`: `nx` × `ny` pixels of
  `pixel_size` µm at the sample, a number or a tuple `(size_x, size_y)`.
- `SCMOSCamera(pixel_edges_x, pixel_edges_y; readnoise, offset=0, gain=1, qe=1)`: from pixel
  edges (µm, vectors), which need not be uniform; `readnoise` is required.

Each calibration value is a number or a map (a matrix). The camera's number type `T` is the
promoted type of the numbers given: the pixel size (or the edges), `readnoise`, and `offset`,
`gain` and `qe` when they are passed (a map counts by its element type). All `Float32` gives
`SCMOSCamera{Float32}`; whole numbers take the type of the rest (`offset = 100` with a `Float64`
pixel size gives `100.0`); a mix of `Float32` and `Float64` gives `Float64`. Every value is
converted to `T`, and a map that is already a `Matrix{T}` is stored as given, not copied. A map
of the wrong size throws a `DimensionMismatch`.

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

# A calibration value of an sCMOS camera: one number for every pixel, or a map of size (ny, nx).
const _SCMOSParam = Union{Real, AbstractMatrix{<:Real}}

# The number type a constructor argument brings to the camera's `T`; an argument not given
# (`nothing`) brings none.
_camera_eltype(x::Real) = typeof(x)
_camera_eltype(x::Tuple{Real, Real}) = promote_type(typeof(x[1]), typeof(x[2]))
_camera_eltype(x::AbstractArray{<:Real}) = _number_type(eltype(x))
_camera_eltype(::Nothing) = Union{}
# An element type that is a union of number types (`Union{Float32,Float64}`) brings their
# promotion.
_number_type(T::Type) = T isa Union ? promote_type(Base.uniontypes(T)...) : T

# Uniform edges `0, p, 2p, ..., n·p` in `T`: whole numbers exactly, with a check that each fits;
# floats as a range, as in 0.1.0.
function _uniform_edges(::Type{T}, n::Integer, p) where {T}
    T <: Integer && return T[Base.checked_mul(convert(T, i), p) for i in 0:n]
    return collect(T, range(zero(T), n * p, length = n + 1))
end

# A vector or map as a `Vector{T}` or `Matrix{T}`, its values in order whatever its indices
# (an offset array, say); one that already is one is kept as given.
_as_vector(::Type{T}, v::Vector{T}) where {T} = v
_as_vector(::Type{T}, v::AbstractVector) where {T} = copyto!(Vector{T}(undef, length(v)), v)
_as_matrix(::Type{T}, m::Matrix{T}) where {T} = m
_as_matrix(::Type{T}, m::AbstractMatrix) where {T} = copyto!(Matrix{T}(undef, size(m)), m)

# A calibration value converted to the camera's `T`; `default` when not given.
_camera_param(::Type{T}, x::Real, default) where {T} = convert(T, x)
_camera_param(::Type{T}, x::AbstractMatrix{<:Real}, default) where {T} = _as_matrix(T, x)
_camera_param(::Type{T}, ::Nothing, default) where {T} = convert(T, default)

# Pixel size in x and y, in the camera's `T`.
_pixel_sizes(::Type{T}, p::Real) where {T} = (convert(T, p), convert(T, p))
_pixel_sizes(::Type{T}, p::Tuple{Real, Real}) where {T} = (convert(T, p[1]), convert(T, p[2]))

function SCMOSCamera(
    nx::Integer,
    ny::Integer,
    pixel_size::Union{Real, Tuple{Real, Real}},
    readnoise::_SCMOSParam;
    offset::Union{_SCMOSParam, Nothing} = nothing,
    gain::Union{_SCMOSParam, Nothing} = nothing,
    qe::Union{_SCMOSParam, Nothing} = nothing
)
    T = promote_type(_camera_eltype(pixel_size), _camera_eltype(readnoise),
                     _camera_eltype(offset), _camera_eltype(gain), _camera_eltype(qe))
    _check_count(nx, ny)
    px, py = _pixel_sizes(T, pixel_size)
    # In `T` itself, so whole-number pixel sizes give whole-number edges, as in 0.1.0
    return _scmos_camera(T, _uniform_edges(T, nx, px), _uniform_edges(T, ny, py),
                         readnoise, offset, gain, qe)
end

function SCMOSCamera(
    pixel_edges_x::AbstractVector{<:Real},
    pixel_edges_y::AbstractVector{<:Real};
    readnoise::_SCMOSParam,
    offset::Union{_SCMOSParam, Nothing} = nothing,
    gain::Union{_SCMOSParam, Nothing} = nothing,
    qe::Union{_SCMOSParam, Nothing} = nothing
)
    T = promote_type(_camera_eltype(pixel_edges_x), _camera_eltype(pixel_edges_y),
                     _camera_eltype(readnoise), _camera_eltype(offset), _camera_eltype(gain),
                     _camera_eltype(qe))
    return _scmos_camera(T, _as_vector(T, pixel_edges_x), _as_vector(T, pixel_edges_y),
                         readnoise, offset, gain, qe)
end

# Check the maps' sizes against the edges and build the camera in `T`.
function _scmos_camera(::Type{T}, edges_x::Vector{T}, edges_y::Vector{T},
                       readnoise, offset, gain, qe) where {T}
    (isempty(edges_x) || isempty(edges_y)) &&
        throw(ArgumentError("a camera needs at least one pixel edge on each side (N + 1 for N pixels)"))
    nx = length(edges_x) - 1
    ny = length(edges_y) - 1
    _validate_camera_param(offset, nx, ny, "offset")
    _validate_camera_param(gain, nx, ny, "gain")
    _validate_camera_param(readnoise, nx, ny, "readnoise")
    _validate_camera_param(qe, nx, ny, "qe")
    return SCMOSCamera{T}(edges_x, edges_y,
                          _camera_param(T, offset, 0), _camera_param(T, gain, 1),
                          _camera_param(T, readnoise, 0), _camera_param(T, qe, 1))
end

# Validation helper
# Matrix parameters use Julia standard (row, col) = (y, x) convention
# So for a camera with nx columns and ny rows, matrices should be (ny, nx)
function _validate_camera_param(param::AbstractMatrix, nx, ny, name)
    size(param) == (ny, nx) ||
        throw(DimensionMismatch("$name size $(size(param)) must match ($ny, $nx) [rows, cols]"))
end
_validate_camera_param(param::Union{Real, Nothing}, nx, ny, name) = nothing

# Display methods
function Base.show(io::IO, cam::SCMOSCamera{T}) where T
    nx, ny = _shown_count(cam.pixel_edges_x), _shown_count(cam.pixel_edges_y)
    psize = _shown_pixel_size(_shown_width(cam.pixel_edges_x), _shown_width(cam.pixel_edges_y),
                              "", "no pixels")
    print(io, "SCMOSCamera{$T}($(nx)×$(ny), $(psize))")
end

function Base.show(io::IO, ::MIME"text/plain", cam::SCMOSCamera{T}) where T
    nx, ny = _shown_count(cam.pixel_edges_x), _shown_count(cam.pixel_edges_y)
    psize = _shown_pixel_size(_shown_width(cam.pixel_edges_x), _shown_width(cam.pixel_edges_y),
                              " ", "none (no pixels)")

    println(io, "SCMOSCamera{$T} with:")
    println(io, "  Dimensions: $(nx) × $(ny) pixels")
    println(io, "  Pixel size: $(psize)")

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

