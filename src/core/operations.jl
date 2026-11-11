"""
    cat_smld(smlds::Vector{<:AbstractSMLD})
    cat_smld(smlds::AbstractSMLD...)

Concatenate multiple SMLD objects into a single SMLD.

# Arguments
- `smlds`: Vector of AbstractSMLD objects or multiple AbstractSMLD arguments

# Returns
New AbstractSMLD containing all emitters from inputs

# Notes
- Camera must be identical across all SMLDs: the same type and equal values in every field,
  calibration included. Numbers, arrays, dictionaries, tuples, immutable structs and wrapped
  cameras compare by value (NaN equals NaN); any other object in a camera field compares with
  its own `==`, which for a mutable struct without a `==` method means the same object. A
  plain-bits field that a camera's constructor leaves unset holds whatever was in memory, so it
  can make two otherwise equal cameras differ. The error names the input and the fields that differ
- All inputs must hold the same emitter type
- n_frames is set to the largest `n_frames` of the inputs
- n_datasets is set to the largest `n_datasets` of the inputs
- Metadata from first SMLD is used, with conflicts noted in metadata

# Examples
```julia
# Concatenate two SMLDs
combined = cat_smld(smld1, smld2)

# Concatenate multiple SMLDs
combined = cat_smld(smld1, smld2, smld3)

# Concatenate vector of SMLDs
combined = cat_smld([smld1, smld2, smld3])
```
"""
function cat_smld(smlds::Vector{<:AbstractSMLD})
    isempty(smlds) && error("No SMLDs to concatenate")

    # One input goes through the same steps as several: the result is a new SMLD with a new
    # emitter vector and the same metadata keys, never the input itself.
    ref_camera = smlds[1].camera
    for k in 2:length(smlds)
        is_same_camera(ref_camera, smlds[k].camera) ||
            error("Cannot concatenate SMLDs with different cameras: ",
                _camera_difference(k, ref_camera, smlds[k].camera))
    end

    # Concatenate emitters
    all_emitters = vcat([smld.emitters for smld in smlds]...)

    # Find maximum frame and dataset numbers
    max_frames = maximum(smld.n_frames for smld in smlds)
    max_datasets = maximum(smld.n_datasets for smld in smlds)

    # Combine metadata
    metadata = copy(smlds[1].metadata)
    metadata["concatenated_from"] = length(smlds)

    # Use typeof(smlds[1]) instead of typeof(first(smlds))
    return typeof(smlds[1])(
        all_emitters,
        ref_camera,
        max_frames,
        max_datasets,
        metadata
    )
end

# Varargs version
cat_smld(smlds::AbstractSMLD...) = cat_smld(collect(smlds))

"""
    merge_smld(smlds::Vector{<:AbstractSMLD}; adjust_frames=false, adjust_datasets=false)
    merge_smld(smlds::AbstractSMLD...; adjust_frames=false, adjust_datasets=false)

Merge multiple SMLD objects with options to adjust frame and dataset numbering.

# Arguments
- `smlds`: Vector of AbstractSMLD objects or multiple AbstractSMLD arguments
- `adjust_frames`: If true, places each input's frames after the earlier inputs' frames
- `adjust_datasets`: If true, places each input's datasets after the earlier inputs' datasets

# Returns
New AbstractSMLD containing all emitters with adjusted numbering if requested

# Notes
- Camera must be identical across all SMLDs: the same type and equal values in every field,
  calibration included (a scalar calibration and a uniform map of the same value differ).
  Numbers, arrays, dictionaries, tuples, immutable structs and wrapped cameras compare by value
  (NaN equals NaN); any other object in a camera field compares with its own `==`, which for a
  mutable struct without a `==` method means the same object. A plain-bits field that a camera's
  constructor leaves unset holds whatever was in memory, so it can make two otherwise equal
  cameras differ. The error names the input and the fields that differ
- All inputs must hold the same emitter type
- When adjust_frames=true, each input's frame numbers move by the sum of the earlier inputs'
  `n_frames`, and the result's `n_frames` is that sum over all inputs
- When adjust_datasets=true, each input's dataset numbers move by the sum of the earlier inputs'
  `n_datasets`, and the result's `n_datasets` is that sum over all inputs. An input whose emitters
  lie in datasets `1:n_datasets` therefore keeps datasets apart from every other input; numbers an
  input declares but does not use stay empty in the result
- The inputs are never modified. Each renumbered emitter is a new object, one per entry, even when
  an input lists the same emitter object more than once, and only the requested numbers change
  (an emitter type with a `frame` field and no `dataset` field can be renumbered by frame). A
  mutable emitter is copied field by field and its numbers are set through `setproperty!`; fields
  that hold arrays or other objects stay shared with the input emitter (an emitter with a field
  left undefined is deep-copied instead). An immutable emitter is rebuilt from its fields without
  calling its constructor (fields its constructor left unset stay unset). The first input's emitters (and,
  without renumbering, every input's) are the inputs' own objects, as in `cat_smld`
- Metadata includes information about the merge operation

# Examples
```julia
# Simple merge
merged = merge_smld(smld1, smld2)

# Merge with frame number adjustment
merged = merge_smld(smld1, smld2, adjust_frames=true)

# Merge multiple with both adjustments
merged = merge_smld([smld1, smld2, smld3], 
                   adjust_frames=true, 
                   adjust_datasets=true)
```
"""
function merge_smld(smlds::Vector{<:AbstractSMLD};
    adjust_frames::Bool=false,
    adjust_datasets::Bool=false)
    isempty(smlds) && error("No SMLDs to merge")

    # Check camera compatibility (one input goes through the same steps as several)
    for k in 2:length(smlds)
        is_same_camera(smlds[1].camera, smlds[k].camera) ||
            error("Cannot merge SMLDs with different cameras: ",
                _camera_difference(k, smlds[1].camera, smlds[k].camera))
    end

    # The first input keeps its numbers. Each later input moves by the earlier inputs' total
    # n_frames and n_datasets. Renumbering never changes an emitter in place: the inputs' emitters
    # are shared with the caller (and an input may list one object twice), so each entry becomes
    # a new emitter with the moved numbers.
    renumber = adjust_frames || adjust_datasets
    all_emitters = copy(smlds[1].emitters)
    sizehint!(all_emitters, sum(smld -> length(smld.emitters), smlds))
    frame_offset = Int(smlds[1].n_frames)
    dataset_offset = Int(smlds[1].n_datasets)
    for smld in smlds[2:end]
        if renumber
            _append_renumbered!(all_emitters, smld.emitters,
                adjust_frames ? frame_offset : 0, adjust_datasets ? dataset_offset : 0)
        else
            append!(all_emitters, smld.emitters)
        end
        frame_offset += Int(smld.n_frames)
        dataset_offset += Int(smld.n_datasets)
    end

    new_n_frames = adjust_frames ? frame_offset : maximum(smld.n_frames for smld in smlds)
    new_n_datasets = adjust_datasets ? dataset_offset : maximum(smld.n_datasets for smld in smlds)

    # Combine metadata
    metadata = copy(smlds[1].metadata)
    metadata["merged_from"] = length(smlds)
    metadata["frame_adjustment"] = adjust_frames
    metadata["dataset_adjustment"] = adjust_datasets

    # Create the new SMLD object
    return typeof(first(smlds))(
        all_emitters,
        smlds[1].camera,
        new_n_frames,
        new_n_datasets,
        metadata
    )
end



# Varargs version
merge_smld(smlds::AbstractSMLD...; kwargs...) = merge_smld(collect(smlds); kwargs...)

# Function barrier: `emitters` has a concrete type here even when the input vector does not.
function _append_renumbered!(dest, emitters, df::Int, dd::Int)
    for e in emitters
        push!(dest, _renumbered(e, df, dd))
    end
    return dest
end

# A new emitter equal to `e` except that its frame and dataset are moved by `df` and `dd`; `e` is
# not changed, and a number with a zero move is not read or written. A mutable emitter is copied
# field by field and set through `setproperty!` (so a type's own setter, and frame or dataset held
# as properties, work as before). An immutable emitter is rebuilt from its fields, which needs a
# `frame` field only for a frame move and a `dataset` field only for a dataset move.
@generated function _renumbered(e::E, df::Int, dd::Int) where {E<:AbstractEmitter}
    if ismutabletype(E)
        return quote
            c = _field_copy(e)
            iszero(df) || (c.frame += df)
            iszero(dd) || (c.dataset += dd)
            c
        end
    end
    names = fieldnames(E)
    checks = Expr[]
    :frame in names || push!(checks,
        :(iszero(df) || throw(ArgumentError(string($E, " has no frame field to renumber")))))
    :dataset in names || push!(checks,
        :(iszero(dd) || throw(ArgumentError(string($E, " has no dataset field to renumber")))))
    args = Any[]
    for (i, n) in enumerate(names)
        FT = fieldtype(E, i)
        push!(args,
            n === :frame ? :(iszero(df) ? getfield(e, :frame) : convert($FT, getfield(e, :frame) + df)) :
            n === :dataset ? :(iszero(dd) ? getfield(e, :dataset) : convert($FT, getfield(e, :dataset) + dd)) :
            :(getfield(e, $i)))
    end
    # A field that is not plain bits can be left undefined only at the end (`new` with fewer
    # arguments): rebuild with the fields `e` has defined, and throw if a requested move falls
    # among the fields it leaves unset.
    body = Expr(:new, E, args...)
    for i in reverse(findall(j -> !isbitstype(fieldtype(E, j)), 1:length(names)))
        lost = Expr[]
        for (nm, d) in ((:frame, :df), (:dataset, :dd))
            j = findfirst(==(nm), names)
            j !== nothing && j >= i && push!(lost, :(iszero($d) || throw(ArgumentError(
                string($E, ": cannot move ", $(string(nm)), ", which this emitter leaves unset")))))
        end
        body = :(isdefined(e, $i) ? $body : $(Expr(:block, lost..., Expr(:new, E, args[1:i-1]...))))
    end
    return Expr(:block, checks..., body)
end

# A field-by-field copy of a mutable struct (fields that hold objects are shared). A field that
# can be left undefined is checked first; with one undefined, the copy is a deepcopy instead.
@generated function _field_copy(e::E) where {E}
    n = fieldcount(E)
    build = Expr(:new, E, Any[:(getfield(e, $i)) for i in 1:n]...)
    checks = Any[:(isdefined(e, $i)) for i in 1:n if !isbitstype(fieldtype(E, i))]
    isempty(checks) && return build
    alldefined = foldl((x, y) -> :($x && $y), checks)
    return :($alldefined ? $build : deepcopy(e))
end

# Two cameras are the same when they have the same type and the same value in every field: pixel
# edges and calibration (an sCMOS camera's offset, gain, read noise and QE). Each value is compared
# by what it is, and nothing else is entered, so a container's internal storage is never read:
# - numbers by value: `==` (so -0.0 equals 0.0, as before), and NaN equals NaN;
# - arrays element by element, whatever their types (axes must match, and an empty slot matches
#   only an empty slot); dictionaries entry by entry; tuples element by element;
# - a camera held in a field (a camera that wraps another), and any immutable struct, field by
#   field (a field left undefined matches only one left undefined);
# - anything else (a string, or a mutable object such as a lock or an instrument handle) with its
#   own `==`, which for a mutable struct without a `==` method means the same object.
# Values of two different types are different unless both are numbers, arrays, dictionaries or
# tuples. An array whose elements are not plain bits, a dictionary, or a mutable camera met again
# while its own comparison is under way (a cycle) compares as equal so far; the rest of the walk
# decides. A plain-bits field that a constructor leaves unset holds whatever was in memory.
is_same_camera(cam1::AbstractCamera, cam2::AbstractCamera) =
    cam1 === cam2 ||
    (typeof(cam1) === typeof(cam2) && _same_value(cam1, cam2, IdDict{Any,Nothing}()))

# For the error when input k's camera is not the first input's: the two types, or the fields
# whose values differ (each field compared on its own by the rule above).
function _camera_difference(k::Integer, a::AbstractCamera, b::AbstractCamera)
    head = string("input ", k, "'s camera differs from input 1's in ")
    typeof(a) === typeof(b) || return string(head, "type (", typeof(b), ", not ", typeof(a), ")")
    names = String[]
    for i in 1:fieldcount(typeof(a))
        da = isdefined(a, i)
        same = da == isdefined(b, i) &&
            (!da || _same_value(getfield(a, i), getfield(b, i), IdDict{Any,Nothing}()))
        same || push!(names, string(fieldname(typeof(a), i)))
    end
    isempty(names) && return string(head, "its values")
    return string(head, length(names) == 1 ? "field " : "fields ", join(names, ", "))
end
function _same_value(a, b, seen)
    a === b && return true
    a isa Number && b isa Number && return _same_number(a, b)
    if a isa AbstractArray && b isa AbstractArray
        if isbitstype(eltype(a)) && isbitstype(eltype(b))
            (a == b) === true && return true
        else
            _revisit!(seen, a, b) && return true
        end
        return _same_elements(a, b, seen)
    end
    if a isa AbstractDict && b isa AbstractDict
        _revisit!(seen, a, b) && return true
        length(a) == length(b) || return false
        for (k, v) in a
            haskey(b, k) || return false
            _same_value(v, b[k], seen) || return false
        end
        return true
    end
    if a isa Tuple && b isa Tuple
        length(a) == length(b) || return false
        for i in eachindex(a)
            _same_value(a[i], b[i], seen) || return false
        end
        return true
    end
    T = typeof(a)
    T === typeof(b) || return false
    if a isa AbstractCamera
        ismutable(a) && _revisit!(seen, a, b) && return true
        return _same_fields(a, b, seen)
    end
    isstructtype(T) && !ismutabletype(T) && return _same_fields(a, b, seen)
    return (a == b) === true
end
function _same_number(a::Number, b::Number)
    (a == b) === true && return true
    a isa AbstractFloat && b isa AbstractFloat && return isnan(a) && isnan(b)
    a isa Complex && b isa Complex &&
        return _same_number(real(a), real(b)) && _same_number(imag(a), imag(b))
    return false
end
function _same_elements(a::AbstractArray, b::AbstractArray, seen)
    axes(a) == axes(b) || return false
    for i in eachindex(a, b)
        da = isassigned(a, i)
        da == isassigned(b, i) || return false
        da && !_same_value(a[i], b[i], seen) && return false
    end
    return true
end
function _same_fields(a::T, b::T, seen) where {T}
    for i in 1:fieldcount(T)
        da = isdefined(a, i)
        da == isdefined(b, i) || return false
        da && !_same_value(getfield(a, i), getfield(b, i), seen) && return false
    end
    return true
end
# Records the pair (a, b) as under comparison; true if it already was. A pair stays recorded: a
# later meeting finds it either still under way or already found equal, since a difference ends
# the whole walk. Keyed by the pair, so meeting `a` beside a different `b` is not a revisit.
function _revisit!(seen, a, b)
    haskey(seen, (a, b)) && return true
    seen[(a, b)] = nothing
    return false
end
