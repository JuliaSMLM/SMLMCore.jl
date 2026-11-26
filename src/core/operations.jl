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
  renumbered by frame, and immutable emitter types can be renumbered.
- A renumbered emitter is built from the input's fields, its `frame` and `dataset` fields moved;
  no getter or setter runs, and the fields that hold arrays or other objects are shared with the
  input emitter (fields left unset stay unset), as `cat_smld` shares whole emitters. A mutable
  type with `const` fields and an unset field before a set one is deep-copied.
- An emitter whose type has its own `getproperty` (a mutable type) or `setproperty!` (a frame
  read from a table, say, or a setter that keeps another field in step) is deep-copied and
  moved through them, so nothing they write can reach the input: `e.frame` and `e.dataset` are
  both read on the copy before either is set, frame first, as in 0.1.0. Afterwards each moved
  number must read as merge_smld set it and the other as it was: a getter or setter that
  changes the other number, or stores a value other than the one given (a clamp, say), throws
  an `ArgumentError`. To check this, both numbers are read through the type's getter. Storage
  that `deepcopy` cannot copy, such as memory behind a raw pointer, is not supported.
- A moved number is the exact sum, stored in the field's type; one that does not fit throws an
  `OverflowError` or `InexactError`, as does a result count that cannot hold its value
  exactly. A type's own setter is given the sum in the property's type when that reaches the
  same setter method as 0.1.0's `e.frame + offset`, and otherwise in 0.1.0's type. A NaN or
  infinite float number stays as it is.
- The first input's emitters (and, without renumbering, every input's) are the inputs' own
  objects, as in [`cat_smld`](@ref).
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
    cache = IdDict{Any,Any}()  # per emitter type, for the whole merge
    for smld in smlds[2:end]
        if renumber
            _append_renumbered!(all_emitters, smld.emitters,
                adjust_frames ? _offset(frame_offset) : 0,
                adjust_datasets ? _offset(dataset_offset) : 0, cache)
        else
            append!(all_emitters, smld.emitters)
        end
        adjust_frames && (frame_offset = _count_add(frame_offset, smld.n_frames))
        adjust_datasets && (dataset_offset = _count_add(dataset_offset, smld.n_datasets))
    end

    new_n_frames = adjust_frames ? frame_offset : _count_max(smld.n_frames for smld in smlds)
    new_n_datasets = adjust_datasets ? dataset_offset :
                     _count_max(smld.n_datasets for smld in smlds)

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
    isequal(result.n_frames, new_n_frames) ||
        throw(InexactError(:merge_smld, typeof(result.n_frames), new_n_frames))
    isequal(result.n_datasets, new_n_datasets) ||
        throw(InexactError(:merge_smld, typeof(result.n_datasets), new_n_datasets))
    return result
end



# Varargs version
merge_smld(smlds::AbstractSMLD...; kwargs...) = merge_smld(collect(smlds); kwargs...)

# Function barrier: `emitters` has a concrete type here even when the input vector does not.
# `cache` holds, for the whole merge, what each emitter type's property methods are.
function _append_renumbered!(dest, emitters, df::Real, dd::Real, cache::IdDict{Any,Any})
    for e in emitters
        T = typeof(e)
        # no closure here: with a run-time T, building one per emitter costs more than the move
        flags = get(cache, T, nothing)
        flags === nothing && (flags = cache[T] = (_has_own_getter(T), _has_own_setter(T)))
        getter, setter = flags::NTuple{2,Bool}
        push!(dest, setter || (getter && ismutabletype(T)) ?
              _renumbered_by_property(e, df, dd, getter, setter, cache) : _renumbered(e, df, dd))
    end
    return dest
end

# Whether `E` has a `getproperty` or `setproperty!` method of its own, not Base's field access.
_own_method(f, sig) = any(m -> m.module !== Base && m.module !== Core, methods(f, sig))
_has_own_getter(E::Type) = _own_method(getproperty, Tuple{E,Symbol})
_has_own_setter(E::Type) = _own_method(setproperty!, Tuple{E,Symbol,Any})

# A whole number as an integer: a float or Rational count or offset that holds one moves
# numbers exactly.
_whole(x::Integer) = x
_whole(x::AbstractFloat) = isinteger(x) ? BigInt(x) : x
_whole(x::Rational) = isinteger(x) ? BigInt(numerator(x)) : x
_whole(x) = x

# The largest count, compared exactly and kept as given (`maximum` would promote first, and a
# Float32 can round an Int); a NaN count gives NaN, as `maximum` does, in any order.
_count_max(counts) = reduce((a, b) -> (b > a || b != b) && a == a ? b : a, counts)

# A sum of two counts in Int or the counts' wider type, checked so that it cannot wrap; whole
# numbers held as floats or Rationals are summed as integers.
_count_add(a::Integer, b::Integer) = Base.checked_add(promote(a, b, 0)...)
function _count_add(a, b)
    wa, wb = _whole(a), _whole(b)
    return wa isa Integer && wb isa Integer ? _count_add(wa, wb) : a + b
end

# An offset as an Int when it fits (so Int emitter numbers move in Int), else as it is.
_offset(d::Integer) = d isa Int || !(typemin(Int) <= d <= typemax(Int)) ? d : Int(d)
_offset(d) = (w = _whole(d); w isa Integer ? _offset(w) : w)

# `old + d`, exactly, as a `T`, or `nothing` when a `T` cannot hold it. Whole numbers are
# summed as integers (no BigFloat precision is involved); a NaN or infinite number stays as it is.
function _sum_as(::Type{T}, old::Real, d::Real) where {T}
    T <: Real || return nothing
    if old isa AbstractFloat && !isfinite(old)
        r = try convert(T, old + d) catch err; err isa InterruptException && rethrow(); nothing end
        return r isa T ? r : nothing
    end
    o = _int_or_nothing(old)
    q = if o !== nothing && d isa Integer
        s, wrapped = Base.add_with_overflow(promote(o, d)...)
        wrapped ? BigInt(o) + BigInt(d) : s
    else
        _exact_sum(old, d)
    end
    r = try
        q isa Rational ? convert(T, old) + convert(T, d) : convert(T, q)
    catch err
        err isa InterruptException && rethrow()
        return nothing
    end
    return r isa T && _exact(r, q) ? r : nothing
end
_sum_as(::Type, old, d) = nothing

# A whole number that an Int holds, as an Int (so a float frame moves without BigInt), or nothing.
_int_or_nothing(x::Integer) = x
_int_or_nothing(x::AbstractFloat) = isinteger(x) && -0x1p62 <= x <= 0x1p62 ? Int(x) : nothing
_int_or_nothing(x) = nothing

# The exact value of `old + d`, and whether `r` is that value.
_exact_sum(old, d) = isinteger(old) && isinteger(d) ? BigInt(old) + BigInt(d) :
                     Rational{BigInt}(old) + Rational{BigInt}(d)
_exact(r, q::Integer) = isfinite(r) && isinteger(r) && r == q
_exact(r, q::Rational) = isfinite(r) && Rational{BigInt}(r) == q

# A moved number stored in a field of type `FT`: the exact sum, or an `OverflowError` (an
# integer sum past its type) or `InexactError` (a field that cannot hold it).
_moved_field(::Type{FT}, old::Integer, d::Integer) where {FT<:Integer} =
    convert(FT, Base.checked_add(promote(old, d)...))
function _moved_field(::Type{FT}, old, d) where {FT}
    r = _sum_as(FT, old, d)
    r === nothing && throw(InexactError(:merge_smld, FT, (old, d)))
    return r
end

# The moved number given to `setproperty!`, `old + d` exactly. Base's setter converts it to the
# field's type, so it must fit that type exactly. A type's own setter is given it in the
# property's own type when that reaches the same setter method as `old + d`'s type (so a setter
# that stores what it is given stores the property's type), else in `old + d`'s type, as 0.1.0
# gave it, else in the field's type when that reaches the same method.
function _setter_value(cache, E::Type, s::Symbol, old, d, setter::Bool)
    P = promote_type(typeof(old), typeof(d))
    F = hasfield(E, s) ? fieldtype(E, s) : Union{}
    setter || !isconcretetype(F) || return _moved_field(F, old, d)
    for T in (typeof(old), P, F)
        isconcretetype(T) || continue
        T === P || _same_setter(cache, E, T, P) || continue
        r = _sum_as(T, old, d)
        r === nothing || return r
    end
    throw(InexactError(:merge_smld, P, (old, d)))
end
_same_setter(cache, E, A, B) = get!(cache, (E, A, B)) do
    try
        which(setproperty!, Tuple{E,Symbol,A}) === which(setproperty!, Tuple{E,Symbol,B})
    catch err
        err isa InterruptException && rethrow()
        false
    end
end::Bool

# The number a property holds, for the check after a setter runs; `nothing` when the emitter has
# no such number (no field of that name and Base's getter) or leaves it unset.
function _number_or_nothing(c, s::Symbol, getter::Bool)
    getter || return hasfield(typeof(c), s) && isdefined(c, s) ? getfield(c, s) : nothing
    return try
        getproperty(c, s)
    catch err
        err isa InterruptException && rethrow()
        nothing
    end
end
_number_now(c, s, moved, getter) = moved ? getproperty(c, s) : _number_or_nothing(c, s, getter)

# A deep copy of `e` with its numbers moved through its own property methods, so no getter or
# setter can write into `e`: both numbers are read and both moves computed before either is set,
# frame first, as 0.1.0 set them. Afterwards each moved number must read as merge_smld set it and
# the other as it was; a getter or setter that changes the other number, or stores a value other
# than the one given (a clamp, say), is refused with an ArgumentError instead of giving numbers
# the result does not declare.
function _renumbered_by_property(e, df, dd, getter::Bool, setter::Bool, cache)
    c = deepcopy(e)
    E = typeof(c)
    mf, md = !iszero(df), !iszero(dd)
    f0 = _number_now(c, :frame, mf, getter)
    d0 = _number_now(c, :dataset, md, getter)
    f = mf ? _setter_value(cache, E, :frame, f0, df, setter) : f0
    d = md ? _setter_value(cache, E, :dataset, d0, dd, setter) : d0
    mf && setproperty!(c, :frame, f)
    md && setproperty!(c, :dataset, d)
    isequal(_number_now(c, :frame, mf, getter), f) &&
        isequal(_number_now(c, :dataset, md, getter), d) || _not_as_set(e)
    return c
end

@noinline _not_as_set(e) = throw(ArgumentError(string(typeof(e), "'s getproperty or setproperty! ",
    "does not leave the frame and dataset as merge_smld sets them (a setter that changes the ",
    "other number, or stores a value other than the one given), so it cannot renumber it")))

# A new emitter equal to `e` except that its frame and dataset fields are moved by `df` and `dd`;
# `e` is not changed, fields that hold objects are shared, fields left unset stay unset, and a
# number with a zero move is not read or written. Only fields are read and written: no getter or
# setter of the type's own runs. This needs a `frame` field only for a frame move and a `dataset`
# field only for a dataset move.
@generated function _renumbered(e::E, df::Real, dd::Real) where {E<:AbstractEmitter}
    names = fieldnames(E)
    n = length(names)
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
    move(nm) = nm === :frame ? :df : nm === :dataset ? :dd : nothing
    args = Any[]
    for (i, nm) in enumerate(names)
        d = move(nm)
        push!(args, d === nothing ? :(getfield(e, $i)) :
            :(iszero($d) ? getfield(e, $i) : _moved_field($(fieldtype(E, i)), getfield(e, $i), $d)))
    end
    body = Expr(:new, E, args...)
    objects = findall(j -> !isbitstype(fieldtype(E, j)), 1:n)
    isempty(objects) && return Expr(:block, checks..., body)
    unset_move(j) = (d = move(names[j]); d === nothing ? nothing :
        :(iszero($d) || throw(ArgumentError(string($E, ": cannot move ", $(string(names[j])),
                                                   ", which this emitter leaves unset")))))
    # Fields left unset: rebuild with `new` and the leading set fields when every later field is
    # an unset object field (the only shape an immutable emitter can have, and one `const`
    # fields allow); otherwise (a mutable emitter) start from an emitter with every field unset
    # and set the ones `e` has, or, with `const` fields, which only `new` can set, deep-copy and
    # set the moved fields.
    hasconst = mut && any(j -> isconst(E, j), 1:n)
    general = if !mut
        nothing
    elseif !hasconst
        sets = map(1:n) do j
            set = :(setfield!(c, $j, $(args[j])))
            j in objects ? :(isdefined(e, $j) ? $set : $(unset_move(j))) : set
        end
        Expr(:block, :(c = $(Expr(:new, E))), sets..., :c)
    else
        moved = [:(iszero($(move(names[j]))) || setfield!(c, $j, $(args[j])))
                 for j in 1:n if move(names[j]) !== nothing && !isconst(E, j)]
        frozen = [j for j in 1:n if move(names[j]) !== nothing && isconst(E, j)]
        refuse = [:(iszero($(move(names[j]))) || throw(ArgumentError(string($E, ": cannot move ",
                      $(string(names[j])), ", a const field, in an emitter with an unset field ",
                      "before a set one")))) for j in frozen]
        Expr(:block, refuse..., :(c = deepcopy(e)), moved..., :c)
    end
    for i in reverse(objects)
        tail = i+1:n
        prefix = Expr(:block, (unset_move(j) for j in i:n if unset_move(j) !== nothing)...,
                      Expr(:new, E, args[1:i-1]...))
        alt = if !mut
            prefix
        elseif all(j -> j in objects, tail)
            anyset = foldl((a, b) -> :($a || $b), (:(isdefined(e, $j)) for j in tail); init = false)
            isempty(tail) ? prefix : :($anyset ? $general : $prefix)
        else
            general
        end
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
