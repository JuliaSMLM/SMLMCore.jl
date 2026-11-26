"""
    @filter(smld, condition)

Return a new SMLD with the emitters for which `condition` holds, a Julia expression written in
terms of emitter properties.

Each name in `condition` is an emitter property when the emitter has a property of that name
(`hasproperty`), and otherwise the variable or function of that name where `@filter` is called.
A condition can therefore mix properties with local variables, constants and functions:
`@filter(smld, photons > threshold)`, `@filter(smld, abs(x) < 1.0)`,
`@filter(smld, !(frame in skip))`, `@filter(smld, frame in 1:10 && x ≤ x_max)`. A name that is
both an emitter property and a variable reads the property; write `\$name` for the variable:
`@filter(smld, dataset == \$dataset)` keeps the emitters of the data set numbered by the
variable `dataset`, and `\$f(x)` calls the caller's `f`; each `\$expr` is evaluated once, where
`@filter` is called. A name that is neither is read with `getproperty`, so a property that the
emitter computes without listing it in `propertynames` is still read when no variable of that
name is defined where `@filter` is called (names Julia exports, such as `time`, count as
defined), and a missing one throws the error `getproperty` gives. `e.name` reads the emitter's
property `name`, as in 0.1.0.

Each name is bound this way once per emitter, before the condition runs, and the condition then
runs as written, so Julia's own scope rules decide the rest: a name the condition binds itself
(an argument of `x -> ...`, a loop or `let` variable, a name it assigns) has its own value
there, as in `@filter(smld, all(s -> s < 0.02, (σ_x, σ_y)))`, and an assignment in the
condition changes only its own binding, never the caller's variable. Operators (`>`, `in`,
`&&`) are never properties; keyword names, field names and quoted code are not names. Other
macros in the condition expand first. A free name inside a nested `@filter` follows the outer
condition's binding, the outer emitter's property when it has one. The condition must give
`true` or `false` (or `1` or `0`) for each emitter.

The result has a new emitter vector, but its emitters are the input's own mutable objects:
setting `bright.emitters[1].photons = 0` changes `smld` as well. `deepcopy` the result before
changing emitters in place. The same holds for [`filter_roi`](@ref), [`filter_frames`](@ref)
and [`cat_smld`](@ref).

# Example
```jldoctest
julia> cam = IdealCamera(64, 64, 0.1);

julia> smld = BasicSMLD([
           Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0; frame=1),
           Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.03, 0.03, 60.0, 2.0; frame=5),
       ], cam, 5, 1);

julia> length(@filter(smld, photons > 1100))
1

julia> length(@filter(smld, σ_x < 0.02 && frame in (1, 2)))
1

julia> length(@filter(smld, 0.5 <= x <= 5.0))
2

julia> threshold = 1100.0;

julia> length(@filter(smld, photons > threshold && abs(x - 3.0) ≤ 0.5))
1

julia> frame = 5;

julia> length(@filter(smld, frame == \$frame))
1
```
"""
macro filter(smld, condition)
    e = gensym(:emitter)
    # `$expr` is the caller's value: bound once, where @filter is called, outside every name the
    # condition binds.
    interpolated = Pair{Symbol,Any}[]
    cond = _filter_interpolations!(interpolated, condition)
    # Other macros expand first, so the names collected are those of the code they become.
    cond = macroexpand(__module__, cond; recursive = true)
    # `e.name` reads the emitter, as in 0.1.0, unless the condition binds `e` itself.
    binders = Set{Symbol}()
    _filter_names!(Set{Symbol}(), binders, Set{Symbol}(), cond)
    :e in binders || (cond = _filter_emitter_dot(cond, e))
    names, binders, globals = Set{Symbol}(), Set{Symbol}(), Set{Symbol}()
    _filter_names!(names, binders, globals, cond)
    skip = union(Set{Symbol}(first.(interpolated)), globals)
    used = sort!([n for n in union(names, binders) if !(n in skip) && _filter_is_variable(n)])
    # Each name is bound before the condition runs; the condition itself stays as written, so
    # Julia's own scope rules decide what every name inside it means, and its assignments reach
    # only these bindings, never the caller's variables.
    body = isempty(used) ? cond :
        Expr(:let, Expr(:block, (Expr(:(=), n, _filter_value(n, e, n in binders)) for n in used)...),
             Expr(:let, Expr(:block), cond))
    call = :($(GlobalRef(@__MODULE__, :_filter_smld))($smld, $e -> $body))
    if !isempty(interpolated)
        call = Expr(:let, Expr(:block, (Expr(:(=), k, v) for (k, v) in interpolated)...), call)
    end
    return esc(call)
end

# Expression heads whose contents are not names of the condition: quoted code and the markers
# that expanded macros leave.
const _FILTER_KEEP_HEADS = (:quote, :inert, :isdefined, :meta, :inbounds, :boundscheck, :loopinfo,
                            :line, :symbolicgoto, :symboliclabel)

# A name that can be a variable: not an operator (`+`, `in`, `isa` included), `end`, `begin`, or
# an all-underscore name.
_filter_is_variable(n::Symbol) = !(Base.isoperator(n) || n in (:in, :isa, :end, :begin) ||
                                   all(==('_'), String(n)))

# `x += 1`, `x .= y`: an assignment that also reads the target.
_is_op_assign(h::Symbol) = h !== :(=) && endswith(String(h), "=") &&
    !(h in (:(==), :(!=), :(<=), :(>=), :(===), :(!==)))

# A nested `@filter`, whose `$` interpolations are its own.
_is_filter_macro(m) = m === Symbol("@filter") ||
    (m isa GlobalRef && m.name === Symbol("@filter")) ||
    (m isa Expr && m.head === :. && m.args[end] isa QuoteNode && m.args[end].value === Symbol("@filter"))

# Each `$expr` outside quotes and nested @filter calls, replaced by a new name bound to it.
function _filter_interpolations!(acc, ex)
    ex isa Expr || return ex
    if ex.head === :$
        v = gensym(:interpolated)
        push!(acc, v => ex.args[1])
        return v
    end
    ex.head in (:quote, :inert) && return ex
    ex.head === :macrocall && _is_filter_macro(ex.args[1]) && return ex
    return Expr(ex.head, (_filter_interpolations!(acc, a) for a in ex.args)...)
end

# `e.name` as the emitter's property `name`.
function _filter_emitter_dot(ex, e::Symbol)
    ex isa Expr || return ex
    ex.head in (:quote, :inert) && return ex
    if ex.head === :. && length(ex.args) == 2 && ex.args[1] === :e && ex.args[2] isa QuoteNode
        return Expr(:., e, ex.args[2])
    end
    return Expr(ex.head, (_filter_emitter_dot(a, e) for a in ex.args)...)
end

# The names an assignment target, argument list or loop specification binds: `x`, `(a, b)`,
# `(; a, b)`, `x::T`, `x = 1`, `xs...`, a function's name and arguments.
_filter_targets(s::Symbol) = Symbol[s]
function _filter_targets(ex::Expr)
    if ex.head in (:tuple, :parameters, :block)
        return reduce(vcat, (_filter_targets(a) for a in ex.args); init = Symbol[])
    elseif ex.head in (:kw, :..., :(=)) || (ex.head === :(::) && length(ex.args) == 2)
        return _filter_targets(ex.args[1])
    elseif ex.head in (:call, :where)
        return reduce(vcat, (_filter_targets(a) for a in ex.args); init = Symbol[])
    end
    return Symbol[]
end
_filter_targets(_) = Symbol[]

# Every symbol the condition uses as a name (`names`), those it binds anywhere (`binders`: they
# may have no value until bound) and those it declares `global`; keyword names, named-tuple
# entry names, field names and quoted code are not names.
function _filter_names!(names, binders, globals, ex)
    if ex isa Symbol
        push!(names, ex)
        return
    end
    ex isa Expr || return
    h, args = ex.head, ex.args
    h in _FILTER_KEEP_HEADS && return
    if h === :kw
        _filter_names!(names, binders, globals, args[2])
    elseif h === :. && length(args) == 2 && args[2] isa QuoteNode
        _filter_names!(names, binders, globals, args[1])
    elseif h === :tuple
        for a in args
            entry = a isa Expr && a.head in (:(=), :kw) && a.args[1] isa Symbol
            _filter_names!(names, binders, globals, entry ? a.args[2] : a)
        end
    elseif h === :global
        for a in args
            union!(globals, _filter_targets(a))
            a isa Expr && a.head === :(=) && _filter_names!(names, binders, globals, a.args[2])
        end
    else
        if h === :(=) || _is_op_assign(h)
            union!(binders, _filter_targets(args[1]))
        elseif h === :local
            foreach(a -> union!(binders, _filter_targets(a)), args)
        elseif h === :-> || h === :function
            union!(binders, _filter_targets(args[1]))
        elseif h === :for || h === :let
            specs = args[1] isa Expr && args[1].head === :block ? args[1].args : Any[args[1]]
            foreach(s -> union!(binders, _filter_targets(s)), specs)
        elseif h === :generator || h === :filter
            foreach(s -> union!(binders, _filter_targets(s)), args[2:end])
        elseif h === :try && args[2] isa Symbol
            push!(binders, args[2])
        end
        foreach(a -> _filter_names!(names, binders, globals, a), args)
    end
    return
end

# The value a name is bound to: the emitter's property when it has one, else the caller's
# variable or function when one is defined, else, for a name the condition only reads,
# `getproperty` (a property computed but not listed in `propertynames`, or the error for a
# missing one), and for one the condition binds, `nothing` until it does.
function _filter_value(n::Symbol, e::Symbol, bound::Bool)
    p = QuoteNode(n)
    get = :($(GlobalRef(Base, :getproperty))($e, $p))
    return :($(GlobalRef(Base, :hasproperty))($e, $p) ? $get :
             $(Expr(:isdefined, n)) ? $n : $(bound ? nothing : get))
end

# The `@filter` result: the emitters for which `keep` holds, with the input's camera, frame and
# data-set counts and a copy of its metadata. The mask converts each answer to `Bool`, so a
# condition that gives a number keeps by its truth (1 or 0), never selects by position.
function _filter_smld(smld, keep)
    emitters = smld.emitters
    return typeof(smld)(
        emitters[Bool[keep(x) for x in emitters]],
        smld.camera,
        smld.n_frames,
        smld.n_datasets,
        copy(smld.metadata)
    )
end

"""
    filter_frames(smld, frame::Integer)
    filter_frames(smld, frames::AbstractVector)

Return a new SMLD with the emitters of one frame, or of a set of frames given as a range or a
vector.

Needs emitters with a `frame` field (`Emitter2DFit`, `Emitter3DFit`). `Emitter2D` and
`Emitter3D` have none and throw an error that names the missing field (a `FieldError` from Julia
1.12, an `ErrorException` before). The result's emitters are the input's own objects, as for
[`@filter`](@ref).

# Example
```jldoctest
julia> cam = IdealCamera(64, 64, 0.1);

julia> emitters = [Emitter2DFit{Float64}(1.0, 1.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0; frame=f)
                   for f in 1:5];

julia> smld = BasicSMLD(emitters, cam, 5, 1);

julia> length(filter_frames(smld, 3)), length(filter_frames(smld, 2:4)), length(filter_frames(smld, [1, 5]))
(1, 3, 2)
```
"""
function filter_frames(smld::AbstractSMLD, frame::Integer)
    keep = [e.frame == frame for e in smld.emitters]
    return typeof(smld)(
        smld.emitters[keep],
        smld.camera,
        smld.n_frames,
        smld.n_datasets,
        copy(smld.metadata)
    )
end

function filter_frames(smld::AbstractSMLD, frames::Union{AbstractVector,AbstractRange})
    frame_set = Set(frames)  # Convert to Set for O(1) lookup
    keep = [e.frame ∈ frame_set for e in smld.emitters]
    return typeof(smld)(
        smld.emitters[keep],
        smld.camera,
        smld.n_frames,
        smld.n_datasets,
        copy(smld.metadata)
    )
end

# The (min, max) bounds of one side of a region: a tuple, a vector or a range.
_roi_bounds(b) = extrema(b)
# Whole numbers in steps of 1 (`0:2`, `0:1:2`, `2:-1:0`) always end at the number written. Any
# other range may have lost its stop (0.0:0.3:1.0 ends at 0.9), and the shortened range is the
# same value as one written to end there, so every such range warns.
function _roi_bounds(r::AbstractRange)
    lo, hi = extrema(r)
    r isa AbstractRange{<:Integer} && isone(abs(step(r))) && return lo, hi
    @warn "filter_roi takes the range $r as the bounds $lo to $hi: a range stops at its " *
          "last whole step, which can fall short of the number written. Pass the bounds as " *
          "a tuple (min, max)." maxlog = 1
    return lo, hi
end

"""
    filter_roi(smld, x_range, y_range)
    filter_roi(smld, x_range, y_range, z_range)

Return a new SMLD with the emitters inside a rectangle (2D) or a box (3D).

# Arguments
- `x_range`, `y_range`, `z_range`: the bounds in µm, inclusive, each a tuple `(min, max)` or a
  range. A range's smallest and largest elements are the bounds. A range stops at its last
  whole step, so `0.0:0.3:1.0` stops at 0.9, and the shortened range cannot be told from one
  written to stop there; any range other than whole numbers in steps of 1 (`0:2`, `0:1:2`)
  therefore logs a warning, once per logger (once per Julia session with the default logger).
  Pass a tuple.

# Notes
The emitters' dimension ([`emitter_ndims`](@ref)) picks the form: the 2D form needs dimension 2
and the 3D form dimension 3, for SMLMCore's emitter types and for emitter types from other
packages alike. Empty data whose dimension is `nothing` give an empty result from either form.
Otherwise an `ErrorException` is thrown: "2D ROI cannot be applied to 3D emitter type" (or its
3D counterpart) for data of the other dimension, and "2D ROI cannot be applied to mixed 2D/3D
emitters" (or its 3D counterpart) for mixed data. The result's emitters are the input's own
objects, as for [`@filter`](@ref).

# Example
```jldoctest
julia> cam = IdealCamera(64, 64, 0.1);

julia> smld = BasicSMLD([Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0)], cam, 1, 1);

julia> length(filter_roi(smld, (0.0, 2.0), (1.0, 3.0)))
1

julia> length(filter_roi(smld, (1.5, 2.0), (1.0, 3.0)))
0
```
"""
function filter_roi(smld::AbstractSMLD, x_range, y_range)
    x_min, x_max = _roi_bounds(x_range)
    y_min, y_max = _roi_bounds(y_range)

    d = emitter_ndims(smld.emitters)
    if d == 2 || (d === nothing && isempty(smld.emitters))
        keep = [x_min ≤ e.x ≤ x_max && y_min ≤ e.y ≤ y_max for e in smld.emitters]
        return typeof(smld)(
            smld.emitters[keep],
            smld.camera,
            smld.n_frames,
            smld.n_datasets,
            copy(smld.metadata)
        )
    elseif d === nothing
        error("2D ROI cannot be applied to mixed 2D/3D emitters")
    else
        error("2D ROI cannot be applied to 3D emitter type")
    end
end

function filter_roi(smld::AbstractSMLD, x_range, y_range, z_range)
    x_min, x_max = _roi_bounds(x_range)
    y_min, y_max = _roi_bounds(y_range)
    z_min, z_max = _roi_bounds(z_range)
    
    d = emitter_ndims(smld.emitters)
    if d == 3 || (d === nothing && isempty(smld.emitters))
        keep = [x_min ≤ e.x ≤ x_max && 
                y_min ≤ e.y ≤ y_max && 
                z_min ≤ e.z ≤ z_max for e in smld.emitters]
        return typeof(smld)(
            smld.emitters[keep],
            smld.camera,
            smld.n_frames,
            smld.n_datasets,
            copy(smld.metadata)
        )
    elseif d === nothing
        error("3D ROI cannot be applied to mixed 2D/3D emitters")
    else
        error("3D ROI cannot be applied to 2D emitter type")
    end
end