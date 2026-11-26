"""
    @filter(smld, condition)

Return a new SMLD with the emitters for which `condition` holds, a Julia expression written in
terms of emitter properties.

Each name in `condition` is an emitter property when the emitter has a property of that name,
and otherwise the variable or function of that name where `@filter` is called. A condition can
therefore mix properties with local variables, constants and functions:
`@filter(smld, photons > threshold)`, `@filter(smld, abs(x) < 1.0)`,
`@filter(smld, !(frame in skip))`, `@filter(smld, frame in 1:10 && x ≤ x_max)`. A name that is
both an emitter property and a variable reads the property; write `\$name` for the variable:
`@filter(smld, dataset == \$dataset)` keeps the emitters of the data set numbered by the
variable `dataset`. A name that is neither throws an `UndefVarError` when the condition runs.
The condition must give `true` or `false` for each emitter.

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
    test = _filter_condition(condition, e)
    return esc(:($(GlobalRef(@__MODULE__, :_filter_smld))($smld, $e -> $test)))
end

# The body of a `@filter` condition, rewritten as a function of the emitter `e`: a name is the
# emitter's property when it has one and otherwise the caller's variable; `$name` is always the
# caller's variable. Function positions, keyword names and bound names (in `->`, generators,
# `let`) are left as written. The whole result is escaped by `@filter`, so every name not
# rewritten resolves where `@filter` is called.
function _filter_condition(ex, e::Symbol)
    if ex isa Symbol
        ex in (:end, :begin) && return ex
        prop = QuoteNode(ex)
        return :($(GlobalRef(Base, :hasproperty))($e, $prop) ?
                 $(GlobalRef(Base, :getproperty))($e, $prop) : $ex)
    elseif ex isa Expr
        h, args = ex.head, ex.args
        if h === :$
            return args[1]
        elseif h === :call
            return Expr(:call, args[1], (_filter_argument(a, e) for a in args[2:end])...)
        elseif h === :comparison  # a < b <= c: operands at odd positions, operators between
            return Expr(:comparison,
                        (isodd(i) ? _filter_condition(a, e) : a for (i, a) in enumerate(args))...)
        elseif h === :.  # a.b reads property b of a; f.(x) broadcasts f
            target = args[2] isa QuoteNode ? args[2] : _filter_condition(args[2], e)
            return Expr(:., args[2] isa QuoteNode ? _filter_condition(args[1], e) : args[1], target)
        elseif h === :-> || h === :(=)  # bound names stay; the body or value is a condition
            return Expr(h, args[1], (_filter_condition(a, e) for a in args[2:end])...)
        else
            return Expr(h, (_filter_condition(a, e) for a in args)...)
        end
    else
        return ex  # literals, quoted symbols, line numbers
    end
end

# An argument of a call in a condition: a keyword keeps its name.
function _filter_argument(ex, e::Symbol)
    if ex isa Expr && ex.head === :kw
        return Expr(:kw, ex.args[1], _filter_condition(ex.args[2], e))
    elseif ex isa Expr && ex.head === :parameters
        return Expr(:parameters, (_filter_argument(a, e) for a in ex.args)...)
    else
        return _filter_condition(ex, e)
    end
end

# The `@filter` result: the emitters for which `keep` holds, with the input's camera, frame and
# data-set counts and a copy of its metadata.
function _filter_smld(smld, keep)
    emitters = smld.emitters
    return typeof(smld)(
        emitters[map(keep, emitters)],
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
# Whole numbers in steps of 1 always end at the number written.
_roi_bounds(r::AbstractUnitRange{<:Integer}) = extrema(r)
# Any other range may have lost its stop (0.0:0.3:1.0 ends at 0.9), and the shortened range is
# the same value as one written to end there, so every such range warns.
function _roi_bounds(r::AbstractRange)
    lo, hi = extrema(r)
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
  range. A range's smallest and largest elements are the bounds, so `0.0:0.3:1.0` stops at 0.9.
  A range stops at its last whole step, which can fall short of the number written, and the
  shortened range cannot be told from one written to stop there, so any range other than
  whole numbers in steps of 1 (`0:2`) logs a warning, once per Julia session. Pass a tuple.

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