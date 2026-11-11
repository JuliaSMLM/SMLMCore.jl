"""
    @filter(smld, condition)

Return a new SMLD with the emitters for which `condition` holds, a condition written in terms of
emitter properties.

Every name in `condition` is read as an emitter property, except the operators `<`, `>`, `<=`,
`>=`, `==`, `!=`, `in` and `∈`, and `&&` and `||`. A condition therefore holds only property
names, number literals and tuples; comparisons may be chained (`1.0 <= x <= 5.0`). It cannot use
a variable (`photons > threshold` reads `e.threshold`), a function (`abs(x)`), arithmetic
(`x + y`), `!`, a range (`frame in 1:10`) or the operators `≤` and `≥`; each throws a
FieldError. For those, filter the emitters directly:

    BasicSMLD(filter(e -> e.photons > threshold, smld.emitters), smld.camera,
              smld.n_frames, smld.n_datasets, copy(smld.metadata))

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
```
"""
macro filter(smld, expr)
    # Only replace symbols that are emitter fields
    function replace_fields(ex)
        if ex isa Expr
            if ex.head == :(.)  # Already a field access
                return ex
            else
                return Expr(ex.head, map(replace_fields, ex.args)...)
            end
        elseif ex isa Symbol && !(ex in [:&&, :||, :<, :>, :<=, :>=, :(==), :!=, :in, :∈])
            # Convert symbol to field access unless it's an operator
            return :(e.$ex)
        else
            return ex
        end
    end
    
    condition = replace_fields(expr)
    
    return quote
        local emitters = $(esc(smld)).emitters
        local keep = Bool[]
        for e in emitters
            push!(keep, $condition)
        end
        typeof($(esc(smld)))(
            emitters[keep],
            $(esc(smld)).camera,
            $(esc(smld)).n_frames,
            $(esc(smld)).n_datasets,
            copy($(esc(smld)).metadata)
        )
    end
end

"""
    filter_frames(smld, frame::Integer)
    filter_frames(smld, frames::AbstractVector)

Return a new SMLD with the emitters of one frame, or of a set of frames given as a range or a
vector.

Needs emitters with a `frame` field (`Emitter2DFit`, `Emitter3DFit`). `Emitter2D` and
`Emitter3D` have none and throw a FieldError. The result's emitters are the input's own objects,
as for [`@filter`](@ref).

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

"""
    filter_roi(smld, x_range, y_range)
    filter_roi(smld, x_range, y_range, z_range)

Return a new SMLD with the emitters inside a rectangle (2D) or a box (3D).

# Arguments
- `x_range`, `y_range`, `z_range`: the bounds in µm, inclusive, each a tuple `(min, max)` or a
  range. A range's smallest and largest elements are the bounds, so `0.0:0.3:1.0` stops at 0.9.

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
    x_min, x_max = extrema(x_range)
    y_min, y_max = extrema(y_range)

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
    x_min, x_max = extrema(x_range)
    y_min, y_max = extrema(y_range)
    z_min, z_max = extrema(z_range)
    
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