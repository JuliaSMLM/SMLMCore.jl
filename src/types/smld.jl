"""
    AbstractSMLD

Supertype of SMLD (single molecule localization data) containers: a set of emitters with the
camera they were imaged on. Emitter positions are in µm.

A custom SMLD type subtypes `AbstractSMLD` and has the fields `emitters`, `camera`, `n_frames`,
`n_datasets` and `metadata::Dict{String,Any}`. It also needs a constructor
`MySMLD(emitters, camera, n_frames, n_datasets, metadata)` (the default constructor, when the
fields are in that order), because the filters, [`cat_smld`](@ref) and [`merge_smld`](@ref) build
their result with `typeof(smld)(emitters, camera, n_frames, n_datasets, metadata)`. Its emitters
meet the requirements in [`AbstractEmitter`](@ref).

`length(smld)` is the number of emitters, and iterating an SMLD iterates its emitters.
"""
abstract type AbstractSMLD end

emitter_ndims(smld::AbstractSMLD) = emitter_ndims(smld.emitters)

# Dimension word for display; mixed or empty non-concrete data are labelled as such rather than as 3D.
function _dim_label(emitters)
    d = emitter_ndims(emitters)
    d === nothing && return isempty(emitters) ? "unknown-dimension" : "mixed 2D/3D"
    return string(d, "D")
end

# Backward compatibility alias
"""
    SMLD

Alias of [`AbstractSMLD`](@ref), kept for code written against SMLMData. Use `AbstractSMLD` in
new code.
"""
const SMLD = AbstractSMLD

"""
    BasicSMLD{T,E<:AbstractEmitter} <: AbstractSMLD

The general-purpose SMLD container: emitters of one type, the camera they were imaged on, and
the numbers of frames and datasets.

# Fields
- `emitters::Vector{E}`: the localizations
- `camera::AbstractCamera`: the camera of the full image
- `n_frames::Int`: number of frames in the acquisition
- `n_datasets::Int`: number of datasets
- `metadata::Dict{String,Any}`: any other information, by name

`T` is the element type of the camera's pixel edges (not of the emitters), and `E` is the emitter
type.

# Constructors
- `BasicSMLD(emitters, camera, n_frames, n_datasets, metadata = Dict{String,Any}())`:
  `metadata` must be a `Dict{String,Any}`; write `Dict{String,Any}("exposure_time" => 0.1)`. A
  plain `Dict("exposure_time" => 0.1)` is a `Dict{String,Float64}` and has no matching method.

# Example
```jldoctest
julia> cam = IdealCamera(512, 512, 0.1);

julia> emitters = [
           Emitter2DFit{Float64}(1.0, 1.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0; frame=1),
           Emitter2DFit{Float64}(5.0, 5.0, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0; frame=2),
       ];

julia> smld = BasicSMLD(emitters, cam, 2, 1, Dict{String,Any}("exposure_time" => 0.1));

julia> length(smld), smld.n_frames, smld.metadata["exposure_time"]
(2, 2, 0.1)

julia> print(smld)
BasicSMLD(2 2D emitters, 2 frames)
```

# See also
[`AbstractSMLD`](@ref), [`@filter`](@ref), [`cat_smld`](@ref), [`merge_smld`](@ref)
"""
struct BasicSMLD{T,E<:AbstractEmitter} <: AbstractSMLD
    emitters::Vector{E}
    camera::AbstractCamera
    n_frames::Int
    n_datasets::Int
    metadata::Dict{String,Any}
end

function BasicSMLD(emitters::Vector{E}, camera::AbstractCamera,
                  n_frames::Int, n_datasets::Int,
                  metadata::Dict{String,Any}=Dict{String,Any}()) where E<:AbstractEmitter
    T = eltype(camera.pixel_edges_x)
    BasicSMLD{T,E}(emitters, camera, n_frames, n_datasets, metadata)
end

# Helper method to get the number of emitters
Base.length(smld::AbstractSMLD) = length(smld.emitters)

# Helper method for iteration
Base.iterate(smld::AbstractSMLD) = iterate(smld.emitters)
Base.iterate(smld::AbstractSMLD, state) = iterate(smld.emitters, state)

# Format an integer with thousands separators, for display.
function format_with_commas(n::Integer)
    return replace(string(n), r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => ",")
end


# Base.show methods for AbstractSMLD types: a compact one-line form and a detailed REPL form.

# --- Generic AbstractSMLD compact show method ---
# This works for any concrete AbstractSMLD type

function Base.show(io::IO, smld::S) where {S<:AbstractSMLD}
    n_emitters = length(smld.emitters)
    
    # Determine localization dimension
    dim_str = _dim_label(smld.emitters)
    
    # Get a cleaner type name without parameters
    type_name = string(S.name.name)
    
    print(io, "$type_name($(format_with_commas(n_emitters)) $dim_str emitters, $(format_with_commas(smld.n_frames)) frames)")
end

# --- BasicSMLD detailed show method ---

function Base.show(io::IO, ::MIME"text/plain", smld::BasicSMLD{T,E}) where {T,E}
    n_emitters = length(smld.emitters)
    
    # Camera info
    cam = smld.camera
    n_pixels_x = length(cam.pixel_edges_x) - 1
    n_pixels_y = length(cam.pixel_edges_y) - 1
    
    # Find mean photons per emitter
    if n_emitters > 0
        mean_photons = sum(e.photons for e in smld.emitters) / n_emitters
        mean_photons = round(mean_photons, digits=1)
    else
        mean_photons = "N/A"
    end
    
    # Prepare metadata preview
    meta_keys = keys(smld.metadata)
    meta_preview = isempty(meta_keys) ? "none" : join(collect(meta_keys)[1:min(3, length(meta_keys))], ", ")
    if length(meta_keys) > 3
        meta_preview *= ", ..."
    end
    
    # Get localization dimensions
    dim_str = _dim_label(smld.emitters)
    
    println(io, "BasicSMLD{$T,$E}:")
    println(io, "  Emitters: $(format_with_commas(n_emitters)) $dim_str localizations")
    println(io, "  Camera: $(n_pixels_x)×$(n_pixels_y) pixels")
    println(io, "  Frames: $(format_with_commas(smld.n_frames))")
    println(io, "  Datasets: $(smld.n_datasets)")
    println(io, "  Mean photons: $mean_photons")
    print(io, "  Metadata keys: $meta_preview")
end

# --- Generic AbstractSMLD detailed show method for subtypes without specific methods ---

function Base.show(io::IO, ::MIME"text/plain", smld::S) where {S<:AbstractSMLD}
    # Skip if a more specific method exists (to avoid method ambiguities)
    if S <: BasicSMLD
        return
    end
    
    n_emitters = length(smld.emitters)
    
    # Camera info if available
    cam_info = if hasproperty(smld, :camera)
        cam = smld.camera
        n_pixels_x = length(cam.pixel_edges_x) - 1
        n_pixels_y = length(cam.pixel_edges_y) - 1
        "$(n_pixels_x)×$(n_pixels_y) pixels"
    else
        "not specified"
    end
    
    # Find mean photons per emitter
    if n_emitters > 0 && all(hasfield(typeof(e), :photons) for e in smld.emitters)
        mean_photons = sum(e.photons for e in smld.emitters) / n_emitters
        mean_photons = round(mean_photons, digits=1)
        photon_info = "Mean photons: $mean_photons"
    else
        photon_info = "Mean photons: N/A"
    end
    
    # Get localization dimensions
    dim_str = _dim_label(smld.emitters)
    
    # Get type name without parameters
    type_name = string(S.name.name)
    
    println(io, "$type_name:")
    println(io, "  Emitters: $(format_with_commas(n_emitters)) $dim_str localizations")
    println(io, "  Camera: $cam_info")
    println(io, "  Frames: $(hasproperty(smld, :n_frames) ? format_with_commas(smld.n_frames) : "unknown")")
    println(io, "  Datasets: $(hasproperty(smld, :n_datasets) ? smld.n_datasets : "unknown")")
    print(io, "  $photon_info")
end

