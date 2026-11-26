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
defined), and a missing one throws the error `getproperty` gives. `e` is the emitter itself, so
`e.name` reads its property `name`, as in 0.1.0, and `f(e)` passes the emitter to `f`; write
`\$e` for a caller variable named `e`.

A property is read where the condition reaches it, as in 0.1.0, so `photons > 100 && z > 0`
never reads `z` of an emitter with 100 photons or fewer. The data set is evaluated first, then
each `\$expr` and each caller variable the condition names, once, where `@filter` is called.
Names the condition binds itself (an argument of `x -> ...`, a loop or `let` variable, a name
it assigns, a `where` parameter) keep Julia's own scope rules, as in
`@filter(smld, all(s -> s < 0.02, (σ_x, σ_y)))`: each such name starts, before the condition
runs, as the emitter's property or the caller's variable of that name (else `nothing`), and an
assignment in the condition changes only that binding, never the caller's variable (a name it
declares `global` is the module's). `e` follows the same rules, starting as the emitter: inside
a construct that binds `e` (`e -> ...`, a generator or loop over `e`, `let e = ...`) it is that
construct's, and `catch e` or `e = ...` assigns it, as in Julia. Operators (`>`, `in`, `&&`) are
never properties; keyword names, field names, types in `x::T` (read by Julia where the
condition runs) and quoted code are not names. Other macros in the condition expand first. A
free name inside a nested `@filter` follows the outer condition, the outer emitter's property
when it has one. The condition must give `true` or `false` (or `1` or `0`) for each emitter; a
condition written as an assignment (`dataset = 1`, for `==`) is refused with an
`ArgumentError` when the macro expands.

The caller's variables are read outside the function that tests each emitter, so that function
captures none of them. A `@filter` inside a comprehension or closure of the caller reads them
inside that closure, which captures them as any Julia closure does: a captured local that the
caller assigns again later is boxed, slowing the caller (`\$name` does not change this).

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
    # `@filter(smld, dataset = 1)` is a slip for `==`; 0.1.0 wrote 1 into every emitter.
    condition isa Expr && condition.head === :(=) && throw(ArgumentError(string("@filter: the ",
        "condition `", condition, "` is an assignment; write `==` to compare")))
    e = gensym(:emitter)
    # `$expr` is the caller's value: bound once, where @filter is called, outside every name the
    # condition binds; a nested @filter's own `$` stay its own.
    interpolated = Pair{Symbol,Any}[]
    cond = _filter_interpolations!(interpolated, condition, __module__)
    # Other macros expand first, so the names found are those of the code they become.
    cond = macroexpand(__module__, cond; recursive = true)
    names, binders = Set{Symbol}(), Set{Symbol}()
    _filter_names!(names, binders, cond)
    # `e` is the emitter (so `e.name` reads it, as in 0.1.0), wherever the condition does not
    # bind `e` itself; the names `$expr` became are the caller's values.
    skip = push!(Set{Symbol}(first.(interpolated)), :e)
    used = sort!([n for n in union(names, binders) if !(n in skip) && _filter_is_variable(n)])
    # Each name's caller binding is read once, where @filter is called, so the emitter function
    # never captures a caller variable (a caller local captured and assigned later would be
    # boxed, slowing the caller's whole function).
    caller = Dict(n => gensym(n) for n in used)
    reads = [Expr(:(=), caller[n], :($(Expr(:isdefined, n)) ? $n :
                                     $(GlobalRef(@__MODULE__, :_FILTER_UNDEFINED)))) for n in used]
    # A name the condition never binds is the same name wherever it appears, so each read is
    # replaced in place by its lookup, run only when reached (as 0.1.0 read properties).
    free = Set{Symbol}(n for n in used if !(n in binders))
    :e in binders || (push!(free, :e); caller[:e] = e)
    cond = _filter_reads(cond, e, free, caller)
    # A name the condition binds somewhere is bound before it runs, and the condition then runs
    # as written inside, so Julia's own scope rules decide what it means where, and assignments
    # reach only these bindings, never the caller's variables.
    bound = Any[Expr(:(=), n, _filter_value(n, e, caller[n])) for n in used if n in binders]
    :e in binders && push!(bound, Expr(:(=), :e, e))
    body = isempty(bound) ? cond :
        Expr(:let, Expr(:block, bound...), Expr(:let, Expr(:block), cond))
    # The data set is evaluated first, once; then `$expr` and the caller's variables, so a data
    # set that changes them is seen as it leaves them.
    s = gensym(:smld)
    call = :($(GlobalRef(@__MODULE__, :_filter_smld))($s, $e -> $body))
    outer = vcat(Any[Expr(:(=), k, v) for (k, v) in interpolated], reads)
    isempty(outer) || (call = Expr(:let, Expr(:block, outer...), call))
    return esc(Expr(:let, Expr(:(=), s, smld), call))
end

# A caller name that is not defined where @filter is called.
struct _FilterUndefined end
const _FILTER_UNDEFINED = _FilterUndefined()

# Expression heads whose contents are not names of the condition: quoted code and the markers
# that expanded macros leave.
const _FILTER_KEEP_HEADS = (:quote, :inert, :meta, :inbounds, :boundscheck, :loopinfo, :line,
                            :symbolicgoto, :symboliclabel, :islocal, :isglobal, :locals, :generated,
                            :gc_preserve_begin, :gc_preserve_end, :foreigncall, :new, :splatnew,
                            :static_parameter, :copyast, :cfunction)

# A name that can be a variable: not an operator (`+`, `in`, `isa` included), `end`, `begin`, or
# an all-underscore name.
_filter_is_variable(n::Symbol) = !(Base.isoperator(n) || n in (:in, :isa, :end, :begin) ||
                                   all(==('_'), String(n)))

# `x += 1`, `x .= y`: an assignment that also reads the target.
_is_op_assign(h::Symbol) = h !== :(=) && endswith(String(h), "=") &&
    !(h in (:(==), :(!=), :(<=), :(>=), :(===), :(!==)))

# Whether a macro call's name is this package's `@filter`, under any name it was imported as.
function _is_filter_macro(m, mod::Module)
    f = try
        m isa Symbol ? (isdefined(mod, m) ? getfield(mod, m) : nothing) :
        m isa GlobalRef ? getfield(m.mod, m.name) :
        m isa Expr && m.head === :. ? Core.eval(mod, m) : nothing
    catch
        nothing
    end
    return f === getfield(@__MODULE__, Symbol("@filter"))
end

# Each `$expr` outside quotes and nested @filter calls, replaced by a new name bound to it.
function _filter_interpolations!(acc, ex, mod::Module)
    ex isa Expr || return ex
    if ex.head === :$
        v = gensym(:interpolated)
        push!(acc, v => ex.args[1])
        return v
    end
    ex.head in (:quote, :inert) && return ex
    ex.head === :macrocall && _is_filter_macro(ex.args[1], mod) && return ex
    return Expr(ex.head, (_filter_interpolations!(acc, a, mod) for a in ex.args)...)
end

# The names an assignment target, argument list or loop specification binds: `x`, `(a, b)`,
# `(; a, b)`, `x::T` (not `T`), `x = 1`, `xs...`, `outer x`, an argument marked
# `@nospecialize`, a function's name and arguments.
_filter_targets(s::Symbol) = Symbol[s]
function _filter_targets(ex::Expr)
    if ex.head in (:tuple, :parameters, :block)
        return reduce(vcat, (_filter_targets(a) for a in ex.args); init = Symbol[])
    elseif ex.head === :where  # `f(x::T) where {T<:Real}` binds `T` too
        params = (t isa Expr && t.head in (:<:, :>:) ? t.args[1] : t for t in ex.args[2:end])
        return vcat(_filter_targets(ex.args[1]), Symbol[t for t in params if t isa Symbol])
    elseif ex.head in (:kw, :..., :(=), :outer) || (ex.head === :(::) && length(ex.args) == 2)
        return _filter_targets(ex.args[1])
    elseif ex.head === :meta
        return reduce(vcat, (_filter_targets(a) for a in ex.args[2:end]); init = Symbol[])
    elseif ex.head === :call
        return reduce(vcat, (_filter_targets(a) for a in ex.args); init = Symbol[])
    end
    return Symbol[]
end
_filter_targets(_) = Symbol[]

# The names a scope construct binds for its body: arguments, loop and `let` variables, the
# `catch` variable.
function _filter_scope_names(ex::Expr)
    h, args = ex.head, ex.args
    h === :-> && return _filter_targets(args[1])
    (h === :function || (h === :(=) && args[1] isa Expr && args[1].head in (:call, :where))) &&
        return _filter_targets(args[1])
    if h === :for || h === :let
        specs = args[1] isa Expr && args[1].head === :block ? args[1].args : Any[args[1]]
        return reduce(vcat, (_filter_targets(s) for s in specs); init = Symbol[])
    end
    h in (:generator, :filter) &&
        return reduce(vcat, (_filter_targets(s) for s in args[2:end]); init = Symbol[])
    h === :try && args[2] isa Symbol && return Symbol[args[2]]
    return Symbol[]
end

# Every symbol the condition uses as a name (`names`) and those it binds anywhere (`binders`);
# keyword names, named-tuple entry names, field names, types in `x::T` and `where`, and quoted
# code are not names.
function _filter_names!(names, binders, ex)
    if ex isa Symbol
        push!(names, ex)
        return
    end
    ex isa Expr || return
    h, args = ex.head, ex.args
    h in _FILTER_KEEP_HEADS && return
    if h === :isdefined
        args[1] isa Symbol && push!(names, args[1])
    elseif h === :kw
        _filter_names!(names, binders, args[2])
    elseif h === :. && length(args) == 2 && args[2] isa QuoteNode
        _filter_names!(names, binders, args[1])
    elseif h === :(::) || h === :where
        # the type is not a name of the condition
        (h === :where || length(args) == 2) && _filter_names!(names, binders, args[1])
    elseif h === :tuple
        for a in args
            entry = a isa Expr && a.head in (:(=), :kw) && a.args[1] isa Symbol
            _filter_names!(names, binders, entry ? a.args[2] : a)
        end
    else
        if h === :(=) || _is_op_assign(h)
            union!(binders, _filter_targets(args[1]))
        elseif h === :local || h === :global
            foreach(a -> union!(binders, _filter_targets(a)), args)
        elseif h === :function
            union!(binders, _filter_targets(args[1]))
        else
            union!(binders, _filter_scope_names(ex))
        end
        foreach(a -> _filter_names!(names, binders, a), args)
    end
    return
end

# Each read of a name in `free` replaced by its lookup, run where it is reached, and
# `@isdefined(name)` by whether the lookup finds it; the positions that `_filter_names!` does
# not count as names are left alone.
function _filter_reads(ex, e::Symbol, free::Set{Symbol}, caller)
    ex isa Symbol && return ex in free ? _filter_lookup(ex, e, caller[ex]) : ex
    ex isa Expr || return ex
    h, args = ex.head, ex.args
    h in _FILTER_KEEP_HEADS && return ex
    rw(a) = _filter_reads(a, e, free, caller)
    if h === :isdefined
        n = args[1]
        n === :e && n in free && return true
        return n isa Symbol && n in free ?
            :($(GlobalRef(Base, :hasproperty))($e, $(QuoteNode(n))) ||
              $(caller[n]) !== $(GlobalRef(@__MODULE__, :_FILTER_UNDEFINED))) : ex
    elseif h === :kw
        return Expr(:kw, args[1], rw(args[2]))
    elseif h === :. && length(args) == 2 && args[2] isa QuoteNode
        return Expr(:., rw(args[1]), args[2])
    elseif h === :(::)
        return length(args) == 2 ? Expr(:(::), rw(args[1]), args[2]) : ex
    elseif h === :where
        return Expr(:where, rw(args[1]), args[2:end]...)
    elseif h === :tuple
        return Expr(:tuple, (a isa Expr && a.head in (:(=), :kw) && a.args[1] isa Symbol ?
                             Expr(a.head, a.args[1], rw(a.args[2])) : rw(a) for a in args)...)
    elseif h === :parameters
        # `f(x; lo)` is `f(x; lo = lo)`: keep the keyword's name
        return Expr(:parameters, (a isa Symbol && a in free ? Expr(:kw, a, rw(a)) : rw(a)
                                  for a in args)...)
    else
        return Expr(h, (rw(a) for a in args)...)
    end
end

# A free read: the emitter's property when it has one, else the caller's variable or function
# (`c`, read once where @filter is called) when one is defined, else `getproperty` (a property
# computed but not listed in `propertynames`, or the error for a missing one), evaluated where
# the read is reached.
function _filter_lookup(n::Symbol, e::Symbol, c::Symbol)
    n === :e && return e
    p = QuoteNode(n)
    get = :($(GlobalRef(Base, :getproperty))($e, $p))
    undefined = GlobalRef(@__MODULE__, :_FILTER_UNDEFINED)
    return :($(GlobalRef(Base, :hasproperty))($e, $p) ? $get : $c !== $undefined ? $c : $get)
end

# The value a name the condition binds is given before the condition runs: the emitter's
# property when it has one, else the caller's variable or function when one is defined, else
# `nothing` until the condition binds it.
function _filter_value(n::Symbol, e::Symbol, c::Symbol)
    p = QuoteNode(n)
    get = :($(GlobalRef(Base, :getproperty))($e, $p))
    undefined = GlobalRef(@__MODULE__, :_FILTER_UNDEFINED)
    return :($(GlobalRef(Base, :hasproperty))($e, $p) ? $get : $c !== $undefined ? $c : nothing)
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