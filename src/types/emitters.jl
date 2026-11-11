"""
    AbstractEmitter

Supertype of all emitter (localization) types. Positions are in µm.

A custom emitter type subtypes `AbstractEmitter` and has the properties `x` and `y` (and `z`
for 3D) in µm and `photons`. [`filter_frames`](@ref) needs a `frame` property. In
[`merge_smld`](@ref), `adjust_frames` needs `frame` and `adjust_datasets` needs `dataset`.
Declare the type's dimension as [`emitter_ndims`](@ref) describes.
"""
abstract type AbstractEmitter end

"""
    Emitter2D{T} <: AbstractEmitter

A 2D emitter with a position and a photon count, as used for simulation and ground truth.

# Fields
- `x::T`: x position (µm)
- `y::T`: y position (µm)
- `photons::T`: number of photons from the emitter that reach the camera in the frame, before QE

It has no `frame` or `dataset` field, so [`filter_frames`](@ref) and renumbering in
[`merge_smld`](@ref) do not apply to it.

# Constructors
- `Emitter2D{T}(x, y, photons)`, or `Emitter2D(x, y, photons)` with all three of one type.
"""
mutable struct Emitter2D{T} <: AbstractEmitter
    x::T
    y::T
    photons::T
end

"""
    Emitter3D{T} <: AbstractEmitter

A 3D emitter with a position and a photon count, as used for simulation and ground truth.

# Fields
- `x::T`: x position (µm)
- `y::T`: y position (µm)
- `z::T`: axial position (µm)
- `photons::T`: number of photons from the emitter that reach the camera in the frame, before QE

It has no `frame` or `dataset` field, so [`filter_frames`](@ref) and renumbering in
[`merge_smld`](@ref) do not apply to it.

# Constructors
- `Emitter3D{T}(x, y, z, photons)`, or `Emitter3D(x, y, z, photons)` with all four of one type.
"""
mutable struct Emitter3D{T} <: AbstractEmitter
    x::T
    y::T
    z::T
    photons::T
end

"""
    Emitter2DFit{T} <: AbstractEmitter

A fitted 2D localization: position, photons and background with their uncertainties, and the
frame, dataset and track it belongs to.

# Fields
- `x::T`, `y::T`: fitted position (µm)
- `photons::T`: fitted signal, the total in the frame, in the fitter's working units (below)
- `bg::T`: fitted background per pixel, in the same units
- `σ_x::T`, `σ_y::T`: standard deviations of the position (µm)
- `σ_xy::T`: covariance of x and y (µm²); 0 when the uncertainty ellipse is axis-aligned
- `σ_photons::T`: standard deviation of `photons`, in its units
- `σ_bg::T`: standard deviation of `bg`, in its units
- `frame::Int`: frame number, 1-based
- `dataset::Int`: dataset number, 1-based
- `track_id::Int`: track the localization is linked into (0 = unlinked)
- `id::Int`: identifier within the dataset (0 = not set)

`photons` (the total in the frame) and `bg` (per pixel) are in the units the fitter works in:
photons when the data are in photons (an [`IdealCamera`](@ref), or an [`SCMOSCamera`](@ref)
with `qe = 1`), and photoelectrons (photons × `qe`) when the fitter converts `SCMOSCamera` ADU
with `(ADU - offset) * gain`, as GaussMLE does. A simulator that fills these types with ground
truth, as SMLMSim does, stores `photons` before QE: the photons that reach the camera in the
frame, as in `Emitter2D`.

The position covariance is
``\\Sigma = \\begin{pmatrix} \\sigma_x^2 & \\sigma_{xy} \\\\ \\sigma_{xy} & \\sigma_y^2 \\end{pmatrix}``:
`σ_x` and `σ_y` are standard deviations (µm), and `σ_xy` is a covariance (µm²).

# Constructors
- `Emitter2DFit{T}(x, y, photons, bg, σ_x, σ_y, σ_photons, σ_bg; σ_xy=zero(T), frame=1,
  dataset=1, track_id=0, id=0)`: the eight values must already be of type `T` (write `1000.0`,
  not `1000`).
- `Emitter2DFit{T}(x, y, photons, bg, σ_x, σ_y, σ_xy, σ_photons, σ_bg, frame, dataset,
  track_id, id)`: every field, in field order.

# Example
```jldoctest
julia> e = Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0; frame=5);

julia> (e.x, e.y, e.frame, e.dataset, e.σ_xy)
(1.0, 2.0, 5, 1, 0.0)
```
"""
mutable struct Emitter2DFit{T} <: AbstractEmitter
    x::T
    y::T
    photons::T
    bg::T
    σ_x::T
    σ_y::T
    σ_xy::T
    σ_photons::T
    σ_bg::T
    frame::Int
    dataset::Int
    track_id::Int
    id::Int
end

"""
    Emitter3DFit{T} <: AbstractEmitter

A fitted 3D localization: position, photons and background with their uncertainties, and the
frame, dataset and track it belongs to.

# Fields
- `x::T`, `y::T`, `z::T`: fitted position (µm)
- `photons::T`: fitted signal, the total in the frame, in the fitter's working units (below)
- `bg::T`: fitted background per pixel, in the same units
- `σ_x::T`, `σ_y::T`, `σ_z::T`: standard deviations of the position (µm)
- `σ_xy::T`, `σ_xz::T`, `σ_yz::T`: covariances of the position (µm²); 0 = uncorrelated
- `σ_photons::T`: standard deviation of `photons`, in its units
- `σ_bg::T`: standard deviation of `bg`, in its units
- `frame::Int`: frame number, 1-based
- `dataset::Int`: dataset number, 1-based
- `track_id::Int`: track the localization is linked into (0 = unlinked)
- `id::Int`: identifier within the dataset (0 = not set)

`photons` (the total in the frame) and `bg` (per pixel) are in the units the fitter works in:
photons when the data are in photons (an [`IdealCamera`](@ref), or an [`SCMOSCamera`](@ref)
with `qe = 1`), and photoelectrons (photons × `qe`) when the fitter converts `SCMOSCamera` ADU
with `(ADU - offset) * gain`, as GaussMLE does. A simulator that fills these types with ground
truth, as SMLMSim does, stores `photons` before QE: the photons that reach the camera in the
frame, as in `Emitter2D`.

The position covariance is
``\\Sigma = \\begin{pmatrix} \\sigma_x^2 & \\sigma_{xy} & \\sigma_{xz} \\\\ \\sigma_{xy} & \\sigma_y^2 & \\sigma_{yz} \\\\ \\sigma_{xz} & \\sigma_{yz} & \\sigma_z^2 \\end{pmatrix}``:
`σ_x`, `σ_y` and `σ_z` are standard deviations (µm), and `σ_xy`, `σ_xz` and `σ_yz` are
covariances (µm²).

# Constructors
- `Emitter3DFit{T}(x, y, z, photons, bg, σ_x, σ_y, σ_z, σ_photons, σ_bg; σ_xy=zero(T),
  σ_xz=zero(T), σ_yz=zero(T), frame=1, dataset=1, track_id=0, id=0)`: the ten values must
  already be of type `T`.
- `Emitter3DFit{T}(x, y, z, photons, bg, σ_x, σ_y, σ_z, σ_xy, σ_xz, σ_yz, σ_photons, σ_bg,
  frame, dataset, track_id, id)`: every field, in field order.

# Example
```jldoctest
julia> e = Emitter3DFit{Float64}(1.0, 2.0, -0.5, 1000.0, 10.0, 0.01, 0.01, 0.02, 50.0, 2.0;
                                 σ_xz=0.002, frame=5);

julia> (e.z, e.σ_z, e.σ_xz, e.frame)
(-0.5, 0.02, 0.002, 5)
```
"""
mutable struct Emitter3DFit{T} <: AbstractEmitter
    x::T
    y::T
    z::T
    photons::T
    bg::T
    σ_x::T
    σ_y::T
    σ_z::T
    σ_xy::T
    σ_xz::T
    σ_yz::T
    σ_photons::T
    σ_bg::T
    frame::Int
    dataset::Int
    track_id::Int
    id::Int
end


# Keyword constructors of the fit types (documented in the type docstrings)
function Emitter2DFit{T}(x::T, y::T, photons::T, bg::T,
                        σ_x::T, σ_y::T, σ_photons::T, σ_bg::T;
                        σ_xy::T=zero(T), frame::Int=1, dataset::Int=1, track_id::Int=0, id::Int=0) where T
    Emitter2DFit{T}(x, y, photons, bg, σ_x, σ_y, σ_xy, σ_photons, σ_bg,
                    frame, dataset, track_id, id)
end

function Emitter3DFit{T}(x::T, y::T, z::T, photons::T, bg::T,
                        σ_x::T, σ_y::T, σ_z::T, σ_photons::T, σ_bg::T;
                        σ_xy::T=zero(T), σ_xz::T=zero(T), σ_yz::T=zero(T),
                        frame::Int=1, dataset::Int=1, track_id::Int=0, id::Int=0) where T
    Emitter3DFit{T}(x, y, z, photons, bg, σ_x, σ_y, σ_z, σ_xy, σ_xz, σ_yz, σ_photons, σ_bg,
                    frame, dataset, track_id, id)
end

"""
    emitter_ndims(smld::AbstractSMLD)
    emitter_ndims(emitters::AbstractVector{<:AbstractEmitter})
    emitter_ndims(e::AbstractEmitter)
    emitter_ndims(::Type{<:AbstractEmitter})

Return the spatial dimension of emitters, `2`, `3`, or `nothing` when there is no single answer.

An emitter's dimension is the one its type declares, and for a type that declares none it is
`3` when the emitter has a property `z` (`hasproperty(e, :z)`) and `2` when it does not. A
collection has its element type's declared dimension, or else the dimension all its elements
share, and is `nothing` when they disagree or when it is empty and its element type declares
none (`Union{}` never does).

SMLMCore's four emitter types declare their dimension, and so does a `Union` of its types of one
dimension; for any other type the type method returns `nothing` unless the type declares one.
Fields are never read: a type that computes `z` in `getproperty` is seen through
`propertynames`, as Julia's convention for `getproperty` asks, and a type that stores `z` but
leaves it out of `propertynames` is 2D. Emitter types from other packages need nothing else. A
type whose `propertynames` lists a property that `getproperty` refuses breaks that convention
and is not supported.

A type declares its dimension with a method on its type. The declaration then decides for the
type, for its elements (whatever their properties) and for empty vectors of it:

    SMLMCore.emitter_ndims(::Type{<:MyLocalization{N}}) where {N} = N

A caller that needs a number must handle `nothing` itself, for example
`d = emitter_ndims(smld); d === nothing && throw(ArgumentError("emitters are mixed 2D/3D or empty"))`,
or treat an empty input as a no-op before asking. Do not compare the result with `<` or `>`
without that check.

# Example
```jldoctest
julia> emitter_ndims(Emitter2DFit{Float64})
2

julia> emitter_ndims(Emitter3D{Float64}(1.0, 2.0, 0.1, 500.0))
3

julia> mixed = SMLMCore.AbstractEmitter[Emitter2D{Float64}(1.0, 2.0, 500.0),
                                        Emitter3D{Float64}(1.0, 2.0, 0.1, 500.0)];

julia> emitter_ndims(mixed) === nothing
true

julia> struct MyEmitter <: SMLMCore.AbstractEmitter   # a type from another package
           x::Float64
           y::Float64
           photons::Float64
       end

julia> emitter_ndims(MyEmitter(1.0, 2.0, 500.0))   # no property z
2

julia> emitter_ndims(MyEmitter) === nothing   # the type declares no dimension
true
```
"""
function emitter_ndims(::Type{E}) where {E<:AbstractEmitter}
    E <: Union{Emitter2D, Emitter2DFit} && return 2
    E <: Union{Emitter3D, Emitter3DFit} && return 3
    return nothing
end
# Union{} is a subtype of every emitter type, so without its own method it would match every
# declared method at once (ambiguous) and take the 2D branch above.
emitter_ndims(::Type{Union{}}) = nothing
function emitter_ndims(e::AbstractEmitter)
    d = emitter_ndims(typeof(e))
    return d === nothing ? (hasproperty(e, :z) ? 3 : 2) : d
end
function emitter_ndims(emitters::AbstractVector{<:AbstractEmitter})
    d = emitter_ndims(eltype(emitters))
    (d === nothing && !isempty(emitters)) || return d
    d1 = emitter_ndims(first(emitters))
    return all(e -> emitter_ndims(e) == d1, emitters) ? d1 : nothing
end

# Base.show methods for the emitter types: a compact one-line form and a detailed REPL form.

# --- Emitter2D ---

function Base.show(io::IO, e::Emitter2D{T}) where T
    x = round(e.x, digits=3)
    y = round(e.y, digits=3)
    photons = round(Int, e.photons)
    print(io, "Emitter2D{$T}($(x), $(y) μm, $(photons) photons)")
end

function Base.show(io::IO, ::MIME"text/plain", e::Emitter2D{T}) where T
    println(io, "Emitter2D{$T}:")
    println(io, "  Position: ($(e.x), $(e.y)) μm")
    print(io, "  Photons: $(e.photons)")
end

# --- Emitter3D ---

function Base.show(io::IO, e::Emitter3D{T}) where T
    x = round(e.x, digits=3)
    y = round(e.y, digits=3)
    z = round(e.z, digits=3)
    photons = round(Int, e.photons)
    print(io, "Emitter3D{$T}($(x), $(y), $(z) μm, $(photons) photons)")
end

function Base.show(io::IO, ::MIME"text/plain", e::Emitter3D{T}) where T
    println(io, "Emitter3D{$T}:")
    println(io, "  Position: ($(e.x), $(e.y), $(e.z)) μm")
    print(io, "  Photons: $(e.photons)")
end

# --- Emitter2DFit ---

function Base.show(io::IO, e::Emitter2DFit{T}) where T
    x = round(e.x, digits=3)
    y = round(e.y, digits=3)
    photons = round(Int, e.photons)
    print(io, "Emitter2DFit{$T}($(x), $(y) μm, $(photons) photons, frame=$(e.frame))")
end

function Base.show(io::IO, ::MIME"text/plain", e::Emitter2DFit{T}) where T
    println(io, "Emitter2DFit{$T}:")
    println(io, "  Position: ($(e.x), $(e.y)) μm")
    println(io, "  Photons: $(e.photons)")
    println(io, "  Background: $(e.bg)")
    println(io, "  Uncertainties:")
    println(io, "    σ_x: $(e.σ_x) μm")
    println(io, "    σ_y: $(e.σ_y) μm")
    e.σ_xy != 0 && println(io, "    σ_xy: $(e.σ_xy) μm²")
    println(io, "    σ_photons: $(e.σ_photons)")
    println(io, "    σ_bg: $(e.σ_bg)")
    println(io, "  Frame: $(e.frame)")
    println(io, "  Dataset: $(e.dataset)")
    print(io, "  Track ID: $(e.track_id == 0 ? "unlinked" : e.track_id)")
end

# --- Emitter3DFit ---

function Base.show(io::IO, e::Emitter3DFit{T}) where T
    x = round(e.x, digits=3)
    y = round(e.y, digits=3)
    z = round(e.z, digits=3)
    photons = round(Int, e.photons)
    print(io, "Emitter3DFit{$T}($(x), $(y), $(z) μm, $(photons) photons, frame=$(e.frame))")
end

function Base.show(io::IO, ::MIME"text/plain", e::Emitter3DFit{T}) where T
    println(io, "Emitter3DFit{$T}:")
    println(io, "  Position: ($(e.x), $(e.y), $(e.z)) μm")
    println(io, "  Photons: $(e.photons)")
    println(io, "  Background: $(e.bg)")
    println(io, "  Uncertainties:")
    println(io, "    σ_x: $(e.σ_x) μm")
    println(io, "    σ_y: $(e.σ_y) μm")
    println(io, "    σ_z: $(e.σ_z) μm")
    has_cov = e.σ_xy != 0 || e.σ_xz != 0 || e.σ_yz != 0
    if has_cov
        println(io, "  Covariances:")
        e.σ_xy != 0 && println(io, "    σ_xy: $(e.σ_xy) μm²")
        e.σ_xz != 0 && println(io, "    σ_xz: $(e.σ_xz) μm²")
        e.σ_yz != 0 && println(io, "    σ_yz: $(e.σ_yz) μm²")
    end
    println(io, "    σ_photons: $(e.σ_photons)")
    println(io, "    σ_bg: $(e.σ_bg)")
    println(io, "  Frame: $(e.frame)")
    println(io, "  Dataset: $(e.dataset)")
    print(io, "  Track ID: $(e.track_id == 0 ? "unlinked" : e.track_id)")
end
