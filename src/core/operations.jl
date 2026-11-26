"""
    cat_smld(smlds::Vector{<:AbstractSMLD})
    cat_smld(smlds::AbstractSMLD...)

Concatenate SMLDs into one, keeping every emitter's frame and dataset numbers.

# Returns
- A new SMLD of the first input's type that holds every input's emitters, in order.

# Notes
- The cameras must be the same: the same type and equal values in every field, calibration
  included (a scalar and a uniform map of the same value differ). Otherwise an `ErrorException`
  names the input and the fields that differ.
- All inputs must hold the same emitter type.
- `n_frames` and `n_datasets` are the largest of the inputs'.
- Metadata is a copy of the first input's, plus `"concatenated_from" => number of inputs`. The
  other inputs' metadata are dropped.
- The result's emitters are the inputs' own objects (see [`@filter`](@ref)).
- With one input, the result is a new SMLD with a new emitter vector and the
  `"concatenated_from"` key, as with several. An empty vector throws an `ErrorException`.
- `cat_smld(xs)` gives the same emitters, `n_frames` and `n_datasets` as `merge_smld(xs)`
  without renumbering; only the metadata keys differ.

# Example
```jldoctest
julia> cam = IdealCamera(64, 64, 0.1);

julia> a = BasicSMLD([Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0)], cam, 1, 1);

julia> b = BasicSMLD([Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0)], cam, 1, 1);

julia> c = cat_smld(a, b);

julia> length(c), c.n_frames, c.metadata["concatenated_from"]
(2, 1, 2)
```

# See also
[`merge_smld`](@ref)
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

Merge SMLDs into one, optionally renumbering frames or datasets so that the inputs stay apart.

# Keyword Arguments
- `adjust_frames=false`: place each input's frames after the earlier inputs' frames. Needs
  emitters with a `frame` property.
- `adjust_datasets=false`: place each input's datasets after the earlier inputs' datasets. Needs
  emitters with a `dataset` property.

`Emitter2D` and `Emitter3D` have neither property; renumbering them throws an error that names
the missing field (a `FieldError` from Julia 1.12, an `ErrorException` before).

# Returns
- A new SMLD of the first input's type that holds every input's emitters, in order.

# Notes
- The cameras must be the same, by the rule in [`cat_smld`](@ref), and all inputs must hold the
  same emitter type.
- With `adjust_frames`, each input's frame numbers move by the sum of the earlier inputs'
  `n_frames`, and the result's `n_frames` is that sum over all inputs; without it, `n_frames` is
  the largest of the inputs'. `adjust_datasets` does the same for dataset numbers and
  `n_datasets`. An input whose emitters lie in datasets `1:n_datasets` therefore keeps its
  datasets apart from every other input's; numbers an input declares but does not use stay
  empty in the result.
- The inputs are never modified. Each renumbered emitter is a new object, one per entry, even
  when an input lists the same emitter object more than once. Only the requested numbers are
  read and changed, so an emitter type with a `frame` field and no `dataset` field can be
  renumbered by frame, and immutable emitter types can be renumbered. A renumbered emitter is
  rebuilt from the input's fields, a move starting from `e.frame` and `e.dataset` for a mutable
  type and from the fields for an immutable one, as in 0.1.0, so fields that hold arrays or other
  objects stay shared with the input emitter (fields left unset stay unset), as `cat_smld` shares
  whole emitters. A type with its own `setproperty!` (a frame kept in an array, say, or a setter
  that keeps another field in step) is deep-copied instead and set through its setter, both
  numbers computed before either is set, so the write cannot reach the input; a setter that also
  changes the number not being set throws an `ArgumentError`, and storage that `deepcopy`
  cannot copy, such as memory behind a raw pointer, is not supported. A moved number is stored in
  the field's type (through a setter, in the property's type); one that does not fit throws an
  `OverflowError` or `InexactError`, as does a float number, or a result count, that cannot hold
  its value exactly. The first input's emitters (and,
  without renumbering, every input's) are the inputs' own objects, as in [`cat_smld`](@ref).
- Metadata is a copy of the first input's, plus `"merged_from"` (the number of inputs),
  `"frame_adjustment"` and `"dataset_adjustment"` (the two keywords). The other inputs' metadata
  are dropped.
- With one input, the result is a new SMLD with these metadata keys, as with several; its
  numbers do not move. An empty vector throws an `ErrorException`.

# Example
```jldoctest
julia> cam = IdealCamera(64, 64, 0.1);

julia> a = BasicSMLD([Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0; frame=3)], cam, 10, 1);

julia> b = BasicSMLD([Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0; frame=3)], cam, 10, 1);

julia> m = merge_smld(a, b; adjust_frames = true);

julia> [e.frame for e in m.emitters], m.n_frames
([3, 13], 20)

julia> b.emitters[1].frame   # the input is unchanged
3
```

# See also
[`cat_smld`](@ref)
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
    # Running totals, summed only when they are used: in Int or the counts' wider type, checked,
    # so a sum never wraps.
    frame_offset = smlds[1].n_frames
    dataset_offset = smlds[1].n_datasets
    own_setter = IdDict{Type,Bool}()  # per emitter type, for the whole merge
    for smld in smlds[2:end]
        if renumber
            _append_renumbered!(all_emitters, smld.emitters,
                adjust_frames ? _offset(frame_offset) : 0,
                adjust_datasets ? _offset(dataset_offset) : 0, own_setter)
        else
            append!(all_emitters, smld.emitters)
        end
        adjust_frames && (frame_offset = _count_add(frame_offset, smld.n_frames))
        adjust_datasets && (dataset_offset = _count_add(dataset_offset, smld.n_datasets))
    end

    new_n_frames = adjust_frames ? frame_offset : maximum(smld.n_frames for smld in smlds)
    new_n_datasets = adjust_datasets ? dataset_offset : maximum(smld.n_datasets for smld in smlds)

    # Combine metadata
    metadata = copy(smlds[1].metadata)
    metadata["merged_from"] = length(smlds)
    metadata["frame_adjustment"] = adjust_frames
    metadata["dataset_adjustment"] = adjust_datasets

    # Create the new SMLD object; a count its type cannot hold exactly (a float total) throws
    result = typeof(first(smlds))(
        all_emitters,
        smlds[1].camera,
        new_n_frames,
        new_n_datasets,
        metadata
    )
    result.n_frames == new_n_frames ||
        throw(InexactError(:merge_smld, typeof(result.n_frames), new_n_frames))
    result.n_datasets == new_n_datasets ||
        throw(InexactError(:merge_smld, typeof(result.n_datasets), new_n_datasets))
    return result
end



# Varargs version
merge_smld(smlds::AbstractSMLD...; kwargs...) = merge_smld(collect(smlds); kwargs...)

# Function barrier: `emitters` has a concrete type here even when the input vector does not.
# `own_setter` holds, per type, whether it has its own setter.
function _append_renumbered!(dest, emitters, df::Real, dd::Real, own_setter::IdDict{Type,Bool})
    for e in emitters
        T = typeof(e)
        own = get!(() -> _has_own_setter(T), own_setter, T)
        push!(dest, own ? _renumbered_by_property(e, df, dd) : _renumbered(e, df, dd))
    end
    return dest
end

# Whether `E` has a `setproperty!` method of its own, not Base's field setter.
_has_own_setter(E::Type) =
    any(m -> m.module !== Base && m.module !== Core, methods(setproperty!, Tuple{E,Symbol,Any}))

# A whole number as an integer: a float count or offset that holds one moves numbers exactly.
_whole(x::Integer) = x
_whole(x::AbstractFloat) = isinteger(x) ? BigInt(x) : x
_whole(x) = x

# A sum of two counts in Int or the counts' wider type, checked so that it cannot wrap; whole
# numbers held as floats are summed as integers.
_count_add(a::Integer, b::Integer) = Base.checked_add(promote(a, b, 0)...)
function _count_add(a, b)
    wa, wb = _whole(a), _whole(b)
    return wa isa Integer && wb isa Integer ? _count_add(wa, wb) : a + b
end

# An offset as an Int when it fits (so Int emitter numbers move in Int), else as it is.
_offset(d::Integer) = d isa Int || !(typemin(Int) <= d <= typemax(Int)) ? d : Int(d)
_offset(d) = (w = _whole(d); w isa Integer ? _offset(w) : w)

# A number moved by `d`: an integer in Int or the wider type, checked so the sum cannot wrap; a
# float only when its own type holds the sum exactly.
_moved(old::Integer, d::Integer) = Base.checked_add(promote(old, d)...)
function _moved(old::AbstractFloat, d::Real)
    if isinteger(old) && isinteger(d)
        n = BigInt(old) + BigInt(d)
        r = convert(typeof(old), n)
        isfinite(r) && BigInt(r) == n || throw(InexactError(:merge_smld, typeof(old), n))
        return r
    end
    r = old + d
    isfinite(r) && Rational{BigInt}(r) == Rational{BigInt}(old) + Rational{BigInt}(d) ||
        throw(InexactError(:merge_smld, typeof(r), (old, d)))
    return r
end
_moved(old, d) = old + d

# A moved number as a field of type `FT`; a float that cannot hold it exactly throws.
function _stored(::Type{FT}, v) where {FT}
    r = convert(FT, v)
    (r isa AbstractFloat || v isa AbstractFloat) && r != v &&
        throw(InexactError(:merge_smld, FT, v))
    return r
end

# A moved number in the type of the property it replaces, for a setter that may store it as given.
_moved_as(old, d) = _stored(typeof(old), _moved(old, d))

# A deep copy of `e` with its numbers set through its own setter, so the write cannot reach `e`.
# Both numbers are computed before either is set; afterwards both must read as asked, so a setter
# that also changes the other number is refused instead of giving numbers the result does not
# declare.
function _renumbered_by_property(e, df, dd)
    c = deepcopy(e)
    f = iszero(df) ? (hasproperty(c, :frame) ? getproperty(c, :frame) : nothing) :
                     _moved_as(getproperty(c, :frame), df)
    d = iszero(dd) ? (hasproperty(c, :dataset) ? getproperty(c, :dataset) : nothing) :
                     _moved_as(getproperty(c, :dataset), dd)
    iszero(df) || setproperty!(c, :frame, f)
    iszero(dd) || setproperty!(c, :dataset, d)
    (f === nothing || isequal(getproperty(c, :frame), f)) &&
        (d === nothing || isequal(getproperty(c, :dataset), d)) ||
        throw(ArgumentError(string(typeof(e), "'s setter changes the frame or dataset beside the ",
            "one set, so merge_smld cannot renumber it")))
    return c
end

# A new emitter rebuilt from the fields of `e`, its frame and dataset moved by `df` and `dd`;
# `e` is not changed, fields that hold objects are shared, fields left unset stay unset, and a
# number with a zero move is not read or written. A move starts from `e.frame` for a mutable
# type and from the field for an immutable one, as in 0.1.0. This needs a `frame` field only for
# a frame move and a `dataset` field only for a dataset move.
@generated function _renumbered(e::E, df::Real, dd::Real) where {E<:AbstractEmitter}
    names = fieldnames(E)
    mut = ismutabletype(E)
    # A number with no field: for a mutable type `getproperty`'s error (0.1.0 read `e.frame`),
    # for an immutable one an ArgumentError, as in 0.1.0.
    checks = Expr[]
    for (nm, d) in ((:frame, :df), (:dataset, :dd))
        nm in names && continue
        read = mut ? :(getproperty(e, $(QuoteNode(nm)))) : nothing
        push!(checks, :(iszero($d) || ($read;
            throw(ArgumentError(string($E, " has no ", $(string(nm)), " field to renumber"))))))
    end
    from(nm) = mut ? :(getproperty(e, $(QuoteNode(nm)))) : :(getfield(e, $(QuoteNode(nm))))
    move(nm) = nm === :frame ? :df : nm === :dataset ? :dd : nothing
    args = Any[]
    for (i, n) in enumerate(names)
        FT = fieldtype(E, i)
        d = move(n)
        push!(args, d === nothing ? :(getfield(e, $i)) :
            :(iszero($d) ? getfield(e, $i) : _stored($FT, _moved($(from(n)), $d))))
    end
    body = Expr(:new, E, args...)
    objects = findall(j -> !isbitstype(fieldtype(E, j)), 1:length(names))
    isempty(objects) && return Expr(:block, checks..., body)
    lost(i) = Expr[:(iszero($(move(names[j]))) || throw(ArgumentError(string($E, ": cannot move ",
                     $(string(names[j])), ", which this emitter leaves unset"))))
                   for j in i:length(names) if move(names[j]) !== nothing]
    if mut && !any(j -> isconst(E, j), 1:length(names))
        # A mutable emitter's unset fields need not be the last ones: start from an emitter with
        # every field unset and set the ones `e` has, and a moved number from `e.frame` even when
        # its field is unset.
        sets = map(1:length(names)) do i
            d = move(names[i])
            !(i in objects) ? :(setfield!(c, $i, $(args[i]))) :
            d === nothing ? :(isdefined(e, $i) && setfield!(c, $i, $(args[i]))) :
                            :((isdefined(e, $i) || !iszero($d)) && setfield!(c, $i, $(args[i])))
        end
        alldefined = foldl((a, b) -> :($a && $b), (:(isdefined(e, $i)) for i in objects))
        partial = Expr(:block, :(c = $(Expr(:new, E))), sets..., :c)
        return Expr(:block, checks..., :($alldefined ? $body : $partial))
    end
    # Otherwise (an immutable type, or a mutable one with `const` fields, which cannot be set
    # after `new`) rebuild with the leading fields `e` has set, `new` with fewer arguments; a
    # mutable emitter whose unset fields are not all at the end is deep-copied and set instead.
    for (k, i) in enumerate(reverse(objects))
        later = objects[end-k+2:end]
        prefix = Expr(:block, lost(i)..., Expr(:new, E, args[1:i-1]...))
        alt = mut && !isempty(later) ?
            :($(foldl((a, b) -> :($a || $b), (:(isdefined(e, $j)) for j in later))) ?
              _renumbered_by_property(e, df, dd) : $prefix) : prefix
        body = :(isdefined(e, $i) ? $body : $alt)
    end
    return Expr(:block, checks..., body)
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
