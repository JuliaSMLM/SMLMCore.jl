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

Operators (`>`, `in`, `&&`) are never properties. Names that the condition binds itself keep
their own values, by Julia's scope rules: arguments of `x -> ...` and of functions it defines,
variables of generators, comprehensions, `for` loops and `let`, a `catch` variable, and names
it assigns or declares `local`: `@filter(smld, all(s -> s < 0.02, (σ_x, σ_y)))`. Names the
condition assigns are local to it, so it never changes the caller's variables. Other macros in
the condition expand first, and their code follows the same rules; keyword names and quoted
code are left as written. The condition must give `true` or `false` (or `1` or `0`) for each
emitter.

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
    # `$expr` is the caller's value: bound once, where @filter is called, so no name that the
    # condition binds can capture it.
    interpolated = Pair{Symbol,Any}[]
    cond = _filter_interpolations!(interpolated, condition)
    # Other macros (a nested @filter, @inbounds, @isdefined) expand first, so what is rewritten is
    # the code they become.
    cond = macroexpand(__module__, cond; recursive = true)
    bound = union(Set{Symbol}(first.(interpolated)), _local_names(cond))
    test = _filter_condition(cond, e, bound)
    # Names the condition assigns are its own locals, so it never writes the caller's variables.
    own = setdiff(_assigned_names(cond), _declared_names(cond))
    isempty(own) || (test = Expr(:block, (Expr(:local, n) for n in own)..., test))
    call = :($(GlobalRef(@__MODULE__, :_filter_smld))($smld, $e -> $test))
    if !isempty(interpolated)
        call = Expr(:let, Expr(:block, (Expr(:(=), k, v) for (k, v) in interpolated)...), call)
    end
    return esc(call)
end

# Expression heads left exactly as written: quoted code and the markers that expanded macros leave.
const _FILTER_KEEP_HEADS = (:quote, :inert, :isdefined, :meta, :inbounds, :boundscheck, :loopinfo,
                            :line, :symbolicgoto, :symboliclabel)
# Definitions that cannot appear in a condition.
const _FILTER_REFUSED_HEADS = (:struct, :module, :macro, :abstract, :primitive, :import, :using,
                               :export, :toplevel, :const)
# Expression heads that open a scope of their own; names assigned inside belong to it.
const _FILTER_SCOPE_HEADS = (:->, :function, :let, :for, :while, :try, :generator, :quote, :inert)

# `x += 1`, `x .= y`: an assignment that also reads the target.
_is_op_assign(h::Symbol) = h !== :(=) && endswith(String(h), "=") &&
    !(h in (:(==), :(!=), :(<=), :(>=), :(===), :(!==)))
# `f(x) = body` and `f(x) where T = body` define a function.
_is_function_form(ex) = ex isa Expr && ex.head === :(=) && ex.args[1] isa Expr &&
    ex.args[1].head in (:call, :where)

# Each `$expr` outside quotes and macro calls, replaced by a new name bound to it.
function _filter_interpolations!(acc, ex)
    ex isa Expr || return ex
    if ex.head === :$
        v = gensym(:interpolated)
        push!(acc, v => ex.args[1])
        return v
    end
    ex.head in (:quote, :inert, :macrocall) && return ex
    return Expr(ex.head, (_filter_interpolations!(acc, a) for a in ex.args)...)
end

# The body of a `@filter` condition, rewritten as a function of the emitter `e`. Each free name
# becomes `_filter_name`; names in `bound` (bound by the condition itself) stay. The whole result
# is escaped by `@filter`, so every name left as written resolves where `@filter` is called.
function _filter_condition(ex, e::Symbol, bound::Set{Symbol})
    if ex isa Symbol
        (ex in bound || ex === :end || ex === :begin || Base.isoperator(ex)) && return ex
        return _filter_name(ex, e)
    elseif !(ex isa Expr)
        return ex  # literals, quoted symbols, line numbers, global references
    end
    h, args = ex.head, ex.args
    h in _FILTER_KEEP_HEADS && return ex
    h in _FILTER_REFUSED_HEADS && throw(ArgumentError("@filter: a condition cannot hold `$h`"))
    if h === :$  # left by a macro's expansion: the caller's
        return args[1]
    elseif h === :call
        return Expr(:call, _filter_callee(args[1], e, bound),
                    (_filter_argument(a, e, bound) for a in args[2:end])...)
    elseif h === :. && length(args) == 2 && args[2] isa QuoteNode  # a.b; e.b is the emitter's
        obj = args[1] === :e && !(:e in bound) ? e : _filter_condition(args[1], e, bound)
        return Expr(:., obj, args[2])
    elseif h === :. && length(args) == 2 && args[2] isa Expr && args[2].head === :tuple  # f.(x)
        return Expr(:., _filter_callee(args[1], e, bound),
                    Expr(:tuple, (_filter_argument(a, e, bound) for a in args[2].args)...))
    elseif h === :.  # an operator as a value, `(.>)`
        return ex
    elseif h === :comparison  # a < b <= c: operands at odd positions, operators between
        return Expr(:comparison, (isodd(i) ? _filter_condition(a, e, bound) : a
                                  for (i, a) in enumerate(args))...)
    elseif h === :->
        inner = union(bound, _bound_names(args[1]), _local_names(args[2]))
        return Expr(:->, args[1], (_filter_condition(a, e, inner) for a in args[2:end])...)
    elseif h === :function || _is_function_form(ex)
        inner = union(bound, _signature_names(args[1]), _local_names(args[2]))
        return Expr(h, args[1], (_filter_condition(a, e, inner) for a in args[2:end])...)
    elseif h === :let
        return _filter_let(ex, e, bound)
    elseif h === :for
        return _filter_for(ex, e, bound)
    elseif h === :while  # the condition is outside the body's scope
        return Expr(:while, _filter_condition(args[1], e, bound),
                    _filter_condition(args[2], e, union(bound, _local_names(args[2]))))
    elseif h === :try
        return _filter_try(ex, e, bound)
    elseif h === :generator
        return _filter_generator(ex, e, bound)
    elseif h === :(=) || _is_op_assign(h)  # the target is bound (see `_local_names`); the value is not
        return Expr(h, args[1], _filter_condition(args[2], e, bound))
    elseif h === :local || h === :global
        return Expr(h, (a isa Expr && a.head === :(=) ?
                        Expr(:(=), a.args[1], _filter_condition(a.args[2], e, bound)) : a
                        for a in args)...)
    else
        return Expr(h, (_filter_argument(a, e, bound) for a in args)...)
    end
end

# A free name: the emitter's property when it has one, else the caller's variable or function
# when one is defined, else `getproperty` (a property computed but not listed in
# `propertynames`, or the error for a missing one).
function _filter_name(n::Symbol, e::Symbol)
    p = QuoteNode(n)
    get = :($(GlobalRef(Base, :getproperty))($e, $p))
    return :($(GlobalRef(Base, :hasproperty))($e, $p) ? $get :
             $(Expr(:isdefined, n)) ? $n : $get)
end

# The function called: an operator, `in` or `isa` is never a property; any other free name
# follows `_filter_name`.
function _filter_callee(f, e::Symbol, bound::Set{Symbol})
    f isa Expr && f.head === :$ && return f.args[1]
    if f isa Symbol
        (f in bound || Base.isoperator(f) || f === :in || f === :isa) && return f
        return _filter_name(f, e)
    end
    return _filter_condition(f, e, bound)
end

# An argument: a keyword keeps its name, and `f(x; lo)` stays `f(x; lo = lo)`.
function _filter_argument(ex, e::Symbol, bound::Set{Symbol})
    if ex isa Expr && ex.head === :kw
        return Expr(:kw, ex.args[1], _filter_condition(ex.args[2], e, bound))
    elseif ex isa Expr && ex.head === :parameters
        return Expr(:parameters, (p isa Symbol ? Expr(:kw, p, _filter_condition(p, e, bound)) :
                                  _filter_argument(p, e, bound) for p in ex.args)...)
    else
        return _filter_condition(ex, e, bound)
    end
end

# The names an argument list or assignment target binds: `x`, `(a, b)`, `(; a, b)`, `x::T`,
# `x = 1` (a default), `xs...`. A target such as `a.b` or `a[i]` binds none.
_bound_names(s::Symbol) = Symbol[s]
function _bound_names(ex::Expr)
    if ex.head in (:tuple, :parameters)
        return reduce(vcat, (_bound_names(a) for a in ex.args); init = Symbol[])
    elseif ex.head in (:kw, :..., :(=)) || (ex.head === :(::) && length(ex.args) == 2)
        return _bound_names(ex.args[1])
    end
    return Symbol[]
end
_bound_names(_) = Symbol[]

# The function name and argument names of a signature `f(x, y; k)`, `f(x::T) where T`.
function _signature_names(sig)
    sig isa Expr || return Symbol[]
    if sig.head === :where
        return vcat(_signature_names(sig.args[1]),
                    reduce(vcat, (_bound_names(t isa Expr && t.head === :<: ? t.args[1] : t)
                                  for t in sig.args[2:end]); init = Symbol[]))
    elseif sig.head === :call
        return reduce(vcat, (_bound_names(a) for a in sig.args[2:end]); init = Symbol[])
    end
    return _bound_names(sig)
end

# The name a function definition gives: `f` in `f(x) = ...` or `function f(x) ... end`.
function _function_name(sig)
    sig isa Symbol && return sig
    sig isa Expr && sig.head in (:where, :(::)) && return _function_name(sig.args[1])
    sig isa Expr && sig.head === :call && sig.args[1] isa Symbol && return sig.args[1]
    return nothing
end

# The names local to one scope of the condition, as Julia decides them: every name assigned,
# declared `local` or `global`, or given a function anywhere in the scope, outside the scopes it
# contains. They are bound in the whole scope, before the assignment too.
function _local_names(ex, acc::Set{Symbol} = Set{Symbol}())
    ex isa Expr || return acc
    h, args = ex.head, ex.args
    if h === :function || _is_function_form(ex)
        f = _function_name(args[1])
        f === nothing || push!(acc, f)
    elseif h === :(=) || _is_op_assign(h)
        union!(acc, _bound_names(args[1]))
        _local_names(args[2], acc)
    elseif h === :local || h === :global
        for a in args
            a isa Expr && a.head === :(=) ? (union!(acc, _bound_names(a.args[1]));
                                             _local_names(a.args[2], acc)) :
                                            union!(acc, _bound_names(a))
        end
    elseif h === :tuple || h === :parameters  # `(a = 1,)` names an entry, it assigns nothing
        for a in args
            _local_names(a isa Expr && a.head in (:(=), :kw) ? a.args[2] : a, acc)
        end
    elseif h === :kw
        _local_names(args[2], acc)
    elseif !(h in _FILTER_SCOPE_HEADS)
        foreach(a -> _local_names(a, acc), args)
    end
    return acc
end

# Every name the condition assigns or defines, in any scope of it, except the names that
# `let`, `for`, generators, `catch` and argument lists bind themselves.
function _assigned_names(ex, acc::Set{Symbol} = Set{Symbol}())
    ex isa Expr || return acc
    h, args = ex.head, ex.args
    h in (:quote, :inert) && return acc
    if h === :function || _is_function_form(ex)
        f = _function_name(args[1])
        f === nothing || push!(acc, f)
        foreach(a -> _assigned_names(a, acc), args[2:end])
    elseif h === :(=) || _is_op_assign(h)
        union!(acc, _bound_names(args[1]))
        _assigned_names(args[2], acc)
    elseif h === :->
        foreach(a -> _assigned_names(a, acc), args[2:end])
    elseif h === :let || h === :for
        specs = args[1] isa Expr && args[1].head === :block ? args[1].args : Any[args[1]]
        for s in specs
            s isa Expr && s.head === :(=) && _assigned_names(s.args[2], acc)
        end
        _assigned_names(args[2], acc)
    elseif h === :generator
        _assigned_names(args[1], acc)
        for s in args[2:end]
            s isa Expr && s.head === :filter ? _assigned_names(s.args[1], acc) :
            s isa Expr && s.head === :(=) ? _assigned_names(s.args[2], acc) : nothing
        end
    elseif h === :try
        for (i, a) in enumerate(args)
            i == 2 || _assigned_names(a, acc)  # the second is the catch variable
        end
    elseif h === :tuple || h === :parameters
        for a in args
            _assigned_names(a isa Expr && a.head in (:(=), :kw) ? a.args[2] : a, acc)
        end
    elseif h === :kw
        _assigned_names(args[2], acc)
    else
        foreach(a -> _assigned_names(a, acc), args)
    end
    return acc
end

# Names the condition declares `local` or `global` itself.
function _declared_names(ex, acc::Set{Symbol} = Set{Symbol}())
    ex isa Expr || return acc
    ex.head in (:quote, :inert) && return acc
    if ex.head === :local || ex.head === :global
        for a in ex.args
            union!(acc, _bound_names(a isa Expr && a.head === :(=) ? a.args[1] : a))
        end
    end
    foreach(a -> _declared_names(a, acc), ex.args)
    return acc
end

# `let a = v, b = w; body end`: each value sees the names bound before it, the body all of them
# and its own locals.
function _filter_let(ex::Expr, e::Symbol, bound::Set{Symbol})
    binds, body = ex.args
    specs = binds isa Expr && binds.head === :block ? binds.args : Any[binds]
    inner = copy(bound)
    out = Any[]
    for s in specs
        if s isa Expr && s.head === :(=)
            push!(out, Expr(:(=), s.args[1], _filter_condition(s.args[2], e, inner)))
            union!(inner, _bound_names(s.args[1]))
        else
            union!(inner, _bound_names(s))  # `let x`: a new local
            push!(out, s)
        end
    end
    newbinds = binds isa Expr && binds.head === :block ? Expr(:block, out...) : out[1]
    return Expr(:let, newbinds, _filter_condition(body, e, union(inner, _local_names(body))))
end

# `for x in xs, y in ys; body end`: the iterators see the names outside, the body the loop names
# and its own locals.
function _filter_for(ex::Expr, e::Symbol, bound::Set{Symbol})
    specs, body = ex.args
    list = specs isa Expr && specs.head === :block ? specs.args : Any[specs]
    inner = union(bound, _local_names(body))
    out = Any[]
    for s in list
        if s isa Expr && s.head === :(=)
            push!(out, Expr(:(=), s.args[1], _filter_condition(s.args[2], e, bound)))
            union!(inner, _bound_names(s.args[1]))
        else
            push!(out, s)
        end
    end
    newspecs = specs isa Expr && specs.head === :block ? Expr(:block, out...) : out[1]
    return Expr(:for, newspecs, _filter_condition(body, e, inner))
end

# `try a catch err; b finally c end`: each block is a scope; the catch block also binds `err`.
function _filter_try(ex::Expr, e::Symbol, bound::Set{Symbol})
    args = copy(ex.args)
    catchvar = args[2]
    for i in eachindex(args)
        i == 2 && continue
        args[i] === false && continue
        names = union(bound, _local_names(args[i]))
        i == 3 && catchvar isa Symbol && push!(names, catchvar)
        args[i] = _filter_condition(args[i], e, names)
    end
    return Expr(:try, args...)
end

# `body for x in xs, y in ys if cond`: iterators see the names outside, the body and the
# condition see the loop names too.
function _filter_generator(ex::Expr, e::Symbol, bound::Set{Symbol})
    inner = copy(bound)
    spec(s) = s isa Expr && s.head === :(=) ?
        Expr(:(=), s.args[1], _filter_condition(s.args[2], e, bound)) : s
    out = Any[]
    for s in ex.args[2:end]
        if s isa Expr && s.head === :filter
            fspecs = Any[spec(t) for t in s.args[2:end]]
            foreach(t -> union!(inner, _bound_names(t)), s.args[2:end])
            push!(out, Expr(:filter, _filter_condition(s.args[1], e, inner), fspecs...))
        else
            push!(out, spec(s))
            union!(inner, _bound_names(s))
        end
    end
    body = ex.args[1]
    return Expr(:generator, _filter_condition(body, e, union(inner, _local_names(body))), out...)
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