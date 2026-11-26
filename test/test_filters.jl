using SMLMCore, Test
using SMLMCore: @filter as @keep
using Random: MersenneTwister

@testset "Filtering" begin
    # Create test data with known values
    cam = IdealCamera(1:512, 1:512, 0.1)
    emitters = [
        Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0, frame=1),
        Emitter2DFit{Float64}(1.5, 2.5, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0, frame=2),
        Emitter2DFit{Float64}(2.0, 3.0, 1100.0, 11.0, 0.01, 0.01, 55.0, 2.0, frame=3)
    ]
    smld = BasicSMLD(emitters, cam, 3, 1)

    @testset "Simple Conditions" begin
        # Test greater than
        bright = @filter(smld, photons > 1150)
        @test length(bright.emitters) == 1  # Only emitter[2] has photons > 1150 (1200.0)
        @test bright.emitters[1].photons > 1150
        
        # Test less than
        dim = @filter(smld, photons < 1050)
        @test length(dim.emitters) == 1  # Only emitter[1] has photons < 1050 (1000.0)
        @test dim.emitters[1].photons < 1050
        
        # Test equality
        frame2 = @filter(smld, frame == 2)
        @test length(frame2.emitters) == 1
        @test frame2.emitters[1].frame == 2
    end
    
    @testset "Compound Conditions" begin
        # Test AND
        result = @filter(smld, photons > 1000 && σ_x < 0.02)
        # All emitters have photons > 1000 (1000.0, 1200.0, 1100.0) and σ_x < 0.02 (all 0.01)
        @test length(result.emitters) == 2
        @test all(e -> e.photons > 1000 && e.σ_x < 0.02, result.emitters)
        
        # Test OR
        result = @filter(smld, photons > 1150 || frame == 1)
        # emitter[1] has frame == 1 and emitter[2] has photons > 1150
        @test length(result.emitters) == 2
        @test all(e -> e.photons > 1150 || e.frame == 1, result.emitters)
    end
    
    @testset "Range Comparisons" begin
        # Test inclusive range
        result = @filter(smld, 1.0 <= x <= 1.5)
        # Only emitters[1] and [2] have 1.0 <= x <= 1.5 (x values: 1.0, 1.5, 2.0)
        @test length(result.emitters) == 2
        @test all(e -> 1.0 <= e.x <= 1.5, result.emitters)
        
        # Test range with compound condition
        result = @filter(smld, 1.0 <= x <= 2.0 && photons > 1100)
        # emitters[2] and [3] have photons > 1100 (1200.0, 1100.0)
        # and only emitter[2] also has 1.0 <= x <= 2.0
        @test length(result.emitters) == 1
        @test result.emitters[1].x == 1.5  # Should be the second original emitter
        @test all(e -> (1.0 <= e.x <= 2.0) && e.photons > 1100, result.emitters)
    end
end

# Reference copies of the 0.7.0 filter_roi bodies minus the type check, for allocation parity
function _roi2d_reference(smld, x_range, y_range)
    x_min, x_max = extrema(x_range)
    y_min, y_max = extrema(y_range)
    keep = [x_min ≤ e.x ≤ x_max && y_min ≤ e.y ≤ y_max for e in smld.emitters]
    return typeof(smld)(
        smld.emitters[keep],
        smld.camera,
        smld.n_frames,
        smld.n_datasets,
        copy(smld.metadata)
    )
end

function _roi3d_reference(smld, x_range, y_range, z_range)
    x_min, x_max = extrema(x_range)
    y_min, y_max = extrema(y_range)
    z_min, z_max = extrema(z_range)
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
end

# @allocated of a single call jitters by a few dozen bytes, so take the minimum of several
_alloc_roi(smld, xr, yr) = minimum((@allocated filter_roi(smld, xr, yr)) for _ in 1:10)
_alloc_roi(smld, xr, yr, zr) = minimum((@allocated filter_roi(smld, xr, yr, zr)) for _ in 1:10)
_alloc_ref(smld, xr, yr) = minimum((@allocated _roi2d_reference(smld, xr, yr)) for _ in 1:10)
_alloc_ref(smld, xr, yr, zr) = minimum((@allocated _roi3d_reference(smld, xr, yr, zr)) for _ in 1:10)

# Emitter types as another package would define them: subtypes of AbstractEmitter only
mutable struct ForeignEmitter2D{T} <: SMLMCore.AbstractEmitter
    x::T; y::T; photons::T; frame::Int; dataset::Int; track_id::Int; id::Int
end
mutable struct ForeignEmitter3D{T} <: SMLMCore.AbstractEmitter
    x::T; y::T; z::T; photons::T; frame::Int; dataset::Int; track_id::Int; id::Int
end

# An emitter with its position in a tuple, x/y/z computed in getproperty,
# :z listed in propertynames only for N >= 3. No emitter_ndims method of its own.
struct PropZLoc{N,T} <: SMLMCore.AbstractEmitter
    position::NTuple{N,T}
    uncertainty::NTuple{N,T}
    photons::T
    bg::T
    σ_photons::T
    σ_bg::T
    frame::Int
    dataset::Int
    track_id::Int
    id::Int
end
function Base.getproperty(e::PropZLoc{N,T}, s::Symbol) where {N,T}
    s === :x && return getfield(e, :position)[1]
    s === :y && return getfield(e, :position)[2]
    s === :z && return N >= 3 ? getfield(e, :position)[3] : zero(T)
    s === :σ_x && return getfield(e, :uncertainty)[1]
    s === :σ_y && return getfield(e, :uncertainty)[2]
    s === :σ_z && return N >= 3 ? getfield(e, :uncertainty)[3] : zero(T)
    return getfield(e, s)
end
Base.propertynames(::PropZLoc{N,T}) where {N,T} =
    (fieldnames(PropZLoc{N,T})..., (N >= 3 ? (:x, :y, :z, :σ_x, :σ_y, :σ_z) : (:x, :y, :σ_x, :σ_y))...)

# One concrete type whose instances differ in dimension: :z is listed only when the
# position has three entries.
struct VarDimLoc <: SMLMCore.AbstractEmitter
    position::Vector{Float64}
    photons::Float64
    frame::Int
    dataset::Int
    track_id::Int
    id::Int
end
function Base.getproperty(e::VarDimLoc, s::Symbol)
    s === :x && return getfield(e, :position)[1]
    s === :y && return getfield(e, :position)[2]
    s === :z && return length(getfield(e, :position)) >= 3 ? getfield(e, :position)[3] : 0.0
    return getfield(e, s)
end
# Two constant tuples: splatting a runtime-chosen tuple here would allocate on every call.
Base.propertynames(e::VarDimLoc) = length(getfield(e, :position)) >= 3 ?
    (:position, :photons, :frame, :dataset, :track_id, :id, :x, :y, :z) :
    (:position, :photons, :frame, :dataset, :track_id, :id, :x, :y)

# Same as PropZLoc, plus the documented type-only declaration.
struct DeclaredZLoc{N,T} <: SMLMCore.AbstractEmitter
    position::NTuple{N,T}
    uncertainty::NTuple{N,T}
    photons::T
    bg::T
    σ_photons::T
    σ_bg::T
    frame::Int
    dataset::Int
    track_id::Int
    id::Int
end
function Base.getproperty(e::DeclaredZLoc{N,T}, s::Symbol) where {N,T}
    s === :x && return getfield(e, :position)[1]
    s === :y && return getfield(e, :position)[2]
    s === :z && return N >= 3 ? getfield(e, :position)[3] : zero(T)
    s === :σ_x && return getfield(e, :uncertainty)[1]
    s === :σ_y && return getfield(e, :uncertainty)[2]
    s === :σ_z && return N >= 3 ? getfield(e, :uncertainty)[3] : zero(T)
    return getfield(e, s)
end
Base.propertynames(::DeclaredZLoc{N,T}) where {N,T} =
    (fieldnames(DeclaredZLoc{N,T})..., (N >= 3 ? (:x, :y, :z, :σ_x, :σ_y, :σ_z) : (:x, :y, :σ_x, :σ_y))...)
SMLMCore.emitter_ndims(::Type{<:DeclaredZLoc{N}}) where {N} = N
SMLMCore.emitter_ndims(::Type{<:DeclaredZLoc}) = nothing

# Computes z in getproperty but does not list it in propertynames; declares its
# dimension on its type instead.
struct DeclaredOnlyLoc{N,T} <: SMLMCore.AbstractEmitter
    position::NTuple{N,T}
    photons::T
    frame::Int
    dataset::Int
    track_id::Int
    id::Int
end
function Base.getproperty(e::DeclaredOnlyLoc{N,T}, s::Symbol) where {N,T}
    s === :x && return getfield(e, :position)[1]
    s === :y && return getfield(e, :position)[2]
    s === :z && return N >= 3 ? getfield(e, :position)[3] : zero(T)
    return getfield(e, s)
end
SMLMCore.emitter_ndims(::Type{<:DeclaredOnlyLoc{N}}) where {N} = N

# Has a field z but its type declares 2: the declaration decides, for the type and its elements.
struct ZFieldDeclared2 <: SMLMCore.AbstractEmitter
    x::Float64
    y::Float64
    z::Float64
    photons::Float64
    frame::Int
    dataset::Int
    track_id::Int
    id::Int
end
SMLMCore.emitter_ndims(::Type{ZFieldDeclared2}) = 2

# Function barrier so the allocation count is the scan's own.
_nd_alloc(v) = minimum(@allocated(emitter_ndims(v)) for _ in 1:5)


@testset "Dimension routing" begin
    cam = IdealCamera(1:512, 1:512, 0.1)
    xr, yr, zr = (0.0, 2.0), (0.0, 2.0), (-1.0, 1.0)
    msg2on3 = "2D ROI cannot be applied to 3D emitter type"
    msg3on2 = "3D ROI cannot be applied to 2D emitter type"
    msg2onmixed = "2D ROI cannot be applied to mixed 2D/3D emitters"
    msg3onmixed = "3D ROI cannot be applied to mixed 2D/3D emitters"

    # Emitters 1 and 3 are inside the box; 2 (x), 4 (y) and 5 (z) are outside
    xs = [1.0, 5.0, 0.5, 1.0, 1.5]
    ys = [1.0, 1.0, 1.5, 9.0, 0.5]
    zs = [0.0, 0.0, 0.5, 0.0, 3.0]
    inside2d = [1, 3, 5]
    inside3d = [1, 3]

    make2d = Dict(
        Emitter2D => () -> [Emitter2D{Float64}(xs[i], ys[i], 1000.0) for i in 1:5],
        Emitter2DFit => () -> [Emitter2DFit{Float64}(xs[i], ys[i], 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0,
                                                     frame=i) for i in 1:5])
    make3d = Dict(
        Emitter3D => () -> [Emitter3D{Float64}(xs[i], ys[i], zs[i], 1000.0) for i in 1:5],
        Emitter3DFit => () -> [Emitter3DFit{Float64}(xs[i], ys[i], zs[i], 1000.0, 10.0,
                                                     0.01, 0.01, 0.02, 50.0, 2.0, frame=i) for i in 1:5])

    for (E, make) in make2d
        @testset "$E" begin
            s = BasicSMLD(make(), cam, 5, 1, Dict{String,Any}("k" => 1))
            r = filter_roi(s, xr, yr)
            @test typeof(r) == typeof(s)
            @test length(r.emitters) == length(inside2d)
            @test [e.x for e in r.emitters] == xs[inside2d]
            @test [e.y for e in r.emitters] == ys[inside2d]
            @test r.camera === s.camera
            @test r.n_frames == s.n_frames
            @test r.n_datasets == s.n_datasets
            @test r.metadata == s.metadata
            @test r.metadata !== s.metadata
            @test_throws ErrorException(msg3on2) filter_roi(s, xr, yr, zr)
            @test occursin("2D", sprint(show, s))
            @test occursin("2D localizations", sprint(show, MIME("text/plain"), s))
        end
    end

    for (E, make) in make3d
        @testset "$E" begin
            s = BasicSMLD(make(), cam, 5, 1, Dict{String,Any}("k" => 1))
            r = filter_roi(s, xr, yr, zr)
            @test typeof(r) == typeof(s)
            @test length(r.emitters) == length(inside3d)
            @test [e.x for e in r.emitters] == xs[inside3d]
            @test [e.y for e in r.emitters] == ys[inside3d]
            @test [e.z for e in r.emitters] == zs[inside3d]
            @test r.camera === s.camera
            @test r.n_frames == s.n_frames
            @test r.n_datasets == s.n_datasets
            @test r.metadata == s.metadata
            @test r.metadata !== s.metadata
            @test_throws ErrorException(msg2on3) filter_roi(s, xr, yr)
            @test occursin("3D", sprint(show, s))
            @test occursin("3D localizations", sprint(show, MIME("text/plain"), s))
        end
    end

    @testset "Allocation parity" begin
        # Routing adds nothing for the four own types: the dimension query allocates 0 B and infers
        # Int. filter_roi is compared with the copied 0.7.0 body within 128 B, not exactly, because
        # @allocated differs by 32-64 B between two separately compiled functions even for identical
        # code (0.7.0's own filter_roi misses exact equality with its copy on some random data).
        n = 10_000
        rx, ry, rz = (0.2, 0.8), (0.2, 0.8), (0.2, 0.8)
        rng = MersenneTwister(1)   # seeded, so a failure reproduces
        s2 = BasicSMLD([Emitter2DFit{Float64}(rand(rng), rand(rng), 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0)
                        for _ in 1:n], cam, 1, 1)
        s3 = BasicSMLD([Emitter3DFit{Float64}(rand(rng), rand(rng), rand(rng), 1000.0, 10.0, 0.01, 0.01,
                                              0.02, 50.0, 2.0) for _ in 1:n], cam, 1, 1)
        t2 = BasicSMLD([Emitter2D{Float64}(rand(rng), rand(rng), 1000.0) for _ in 1:n], cam, 1, 1)
        t3 = BasicSMLD([Emitter3D{Float64}(rand(rng), rand(rng), rand(rng), 1000.0) for _ in 1:n], cam, 1, 1)
        for (s, d) in ((s2, 2), (t2, 2), (s3, 3), (t3, 3))
            _nd_alloc(s.emitters)   # warm up
            @test _nd_alloc(s.emitters) == 0
            @test @inferred(emitter_ndims(s.emitters)) == d
        end
        for s in (s2, t2)
            _alloc_roi(s, rx, ry); _alloc_ref(s, rx, ry)
            @test abs(_alloc_roi(s, rx, ry) - _alloc_ref(s, rx, ry)) <= 128
        end
        for s in (s3, t3)
            _alloc_roi(s, rx, ry, rz); _alloc_ref(s, rx, ry, rz)
            @test abs(_alloc_roi(s, rx, ry, rz) - _alloc_ref(s, rx, ry, rz)) <= 128
        end
    end

    @testset "Foreign emitter types" begin
        e2 = [ForeignEmitter2D{Float64}(xs[i], ys[i], 1000.0, i, 1, 0, i) for i in 1:5]
        s2 = BasicSMLD(e2, cam, 5, 1)
        r2 = filter_roi(s2, xr, yr)
        @test [e.x for e in r2.emitters] == xs[inside2d]
        @test_throws ErrorException(msg3on2) filter_roi(s2, xr, yr, zr)
        @test occursin("2D", sprint(show, s2))
        @test occursin("2D localizations", sprint(show, MIME("text/plain"), s2))

        e3 = [ForeignEmitter3D{Float64}(xs[i], ys[i], zs[i], 1000.0, i, 1, 0, i) for i in 1:5]
        s3 = BasicSMLD(e3, cam, 5, 1)
        r3 = filter_roi(s3, xr, yr, zr)
        @test [e.x for e in r3.emitters] == xs[inside3d]
        @test [e.z for e in r3.emitters] == zs[inside3d]
        @test_throws ErrorException(msg2on3) filter_roi(s3, xr, yr)
        @test occursin("3D", sprint(show, s3))
        @test occursin("3D localizations", sprint(show, MIME("text/plain"), s3))
    end

    @testset "Non-concrete eltype" begin
        A = SMLMCore.AbstractEmitter
        e2 = A[Emitter2DFit{Float64}(xs[i], ys[i], 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0) for i in 1:5]
        e3 = A[Emitter3DFit{Float64}(xs[i], ys[i], zs[i], 1000.0, 10.0, 0.01, 0.01, 0.02, 50.0, 2.0) for i in 1:5]

        s2 = BasicSMLD(e2, cam, 5, 1)
        @test [e.x for e in filter_roi(s2, xr, yr).emitters] == xs[inside2d]
        @test_throws ErrorException(msg3on2) filter_roi(s2, xr, yr, zr)

        s3 = BasicSMLD(e3, cam, 5, 1)
        @test [e.z for e in filter_roi(s3, xr, yr, zr).emitters] == zs[inside3d]
        @test_throws ErrorException(msg2on3) filter_roi(s3, xr, yr)

        mixed = BasicSMLD(A[e2[1], e3[1]], cam, 5, 1)
        @test_throws ErrorException(msg2onmixed) filter_roi(mixed, xr, yr)
        @test_throws ErrorException(msg3onmixed) filter_roi(mixed, xr, yr, zr)

        U = Union{Emitter2DFit{Float64}, Emitter3DFit{Float64}}
        union_smld = BasicSMLD(U[e2[1], e3[1]], cam, 5, 1)
        @test_throws ErrorException(msg2onmixed) filter_roi(union_smld, xr, yr)
        @test_throws ErrorException(msg3onmixed) filter_roi(union_smld, xr, yr, zr)

        empty_smld = BasicSMLD(A[], cam, 5, 1)
        @test isempty(filter_roi(empty_smld, xr, yr).emitters)
        @test isempty(filter_roi(empty_smld, xr, yr, zr).emitters)
    end


    @testset "emitter_ndims" begin
        A = SMLMCore.AbstractEmitter
        mk = Dict(
            Emitter2D => (Emitter2D{Float64}(1.0, 2.0, 1000.0), 2),
            Emitter2DFit => (Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0), 2),
            Emitter3D => (Emitter3D{Float64}(1.0, 2.0, 3.0, 1000.0), 3),
            Emitter3DFit => (Emitter3DFit{Float64}(1.0, 2.0, 3.0, 1000.0, 10.0, 0.01, 0.01, 0.02, 50.0, 2.0), 3))
        for (E, (e, d)) in mk
            @test emitter_ndims(E) == d
            @test emitter_ndims(E{Float64}) == d
            @test emitter_ndims(e) == d
            @test emitter_ndims([e]) == d
            @test emitter_ndims(BasicSMLD([e], cam, 1, 1)) == d
        end

        f2 = ForeignEmitter2D{Float64}(1.0, 2.0, 1000.0, 1, 1, 0, 1)
        f3 = ForeignEmitter3D{Float64}(1.0, 2.0, 3.0, 1000.0, 1, 1, 0, 1)
        for (F, f, d) in ((ForeignEmitter2D, f2, 2), (ForeignEmitter3D, f3, 3))
            # An undeclared type has no type-level answer; its emitters decide by their properties.
            @test emitter_ndims(F) === nothing
            @test emitter_ndims(F{Float64}) === nothing
            @test emitter_ndims(f) == d
            @test emitter_ndims([f]) == d
            @test emitter_ndims(BasicSMLD([f], cam, 1, 1)) == d
        end

        e2, e3 = mk[Emitter2D][1], mk[Emitter3D][1]
        @test emitter_ndims(A[e2, e2]) == 2
        @test emitter_ndims(A[e3, e3]) == 3
        @test emitter_ndims(A[e2, e3]) === nothing
        @test emitter_ndims(A[]) === nothing
        @test emitter_ndims(Emitter3DFit{Float64}[]) == 3

        @test emitter_ndims(A) === nothing
        @test emitter_ndims(Union{Emitter2DFit{Float64}, Emitter3DFit{Float64}}) === nothing
        @test @inferred(emitter_ndims(Emitter2DFit{Float64}[])) == 2
        @test @inferred(emitter_ndims([mk[Emitter2DFit][1]])) == 2
        @test @inferred(emitter_ndims([mk[Emitter3DFit][1]])) == 3
    end

    @testset "emitter_ndims: computed z via propertynames" begin
        cam = IdealCamera(1:64, 1:64, 0.1)
        mk2(x, y, i) = PropZLoc{2,Float64}((x, y), (0.01, 0.01), 100.0, 5.0, 1.0, 1.0, 1, 1, 0, i)
        mk3(x, y, z, i) = PropZLoc{3,Float64}((x, y, z), (0.01, 0.01, 0.02 + i), 100.0, 5.0, 1.0, 1.0, 1, 1, 0, i)
        pts = [(0.5, 0.5, 0.0), (1.5, 1.0, 0.5), (5.0, 1.0, 0.0), (1.0, 1.0, 3.0)]   # first two inside the box
        p2s = [mk2(p[1], p[2], i) for (i, p) in enumerate(pts)]
        p3s = [mk3(p..., i) for (i, p) in enumerate(pts)]
        p2, p3 = p2s[1], p3s[1]

        @test emitter_ndims(p2) == 2
        @test emitter_ndims(p3) == 3
        @test emitter_ndims(p3s) == 3
        @test emitter_ndims(p2s) == 2
        s2 = BasicSMLD(p2s, cam, 1, 1)
        s3 = BasicSMLD(p3s, cam, 1, 1)
        @test emitter_ndims(s2) == 2
        @test emitter_ndims(s3) == 3
        @test emitter_ndims(PropZLoc[p3, p3]) == 3
        @test emitter_ndims(SMLMCore.AbstractEmitter[p2, p3]) === nothing

        r3 = filter_roi(s3, (0.0, 2.0), (0.0, 2.0), (-1.0, 1.0))
        @test [e.id for e in r3.emitters] == [1, 2]
        @test_throws ErrorException("2D ROI cannot be applied to 3D emitter type") filter_roi(s3, (0.0, 2.0), (0.0, 2.0))
        r2 = filter_roi(s2, (0.0, 2.0), (0.0, 2.0))
        @test [e.id for e in r2.emitters] == [1, 2, 4]
        @test_throws ErrorException("3D ROI cannot be applied to 2D emitter type") filter_roi(s2, (0.0, 2.0), (0.0, 2.0), (-1.0, 1.0))


        @test occursin("2D", sprint(show, s2))
        @test occursin("3D", sprint(show, s3))
        @test occursin("2D localizations", sprint(show, MIME("text/plain"), s2))
        @test occursin("3D localizations", sprint(show, MIME("text/plain"), s3))

        # Without an element an undeclared type gives no answer, so an ROI on empty data is a no-op.
        @test emitter_ndims(PropZLoc{3,Float64}) === nothing
        @test emitter_ndims(PropZLoc{3,Float64}[]) === nothing
        empty3 = BasicSMLD(PropZLoc{3,Float64}[], cam, 1, 1)
        @test isempty(filter_roi(empty3, (0.0, 2.0), (0.0, 2.0), (-1.0, 1.0)).emitters)
        @test isempty(filter_roi(empty3, (0.0, 2.0), (0.0, 2.0)).emitters)
    end

    @testset "emitter_ndims: declared type-only answer" begin
        cam = IdealCamera(1:64, 1:64, 0.1)
        d2 = DeclaredZLoc{2,Float64}((1.0, 1.0), (0.01, 0.01), 100.0, 5.0, 1.0, 1.0, 1, 1, 0, 1)
        d3 = DeclaredZLoc{3,Float64}((1.0, 1.0, 0.0), (0.01, 0.01, 0.02), 100.0, 5.0, 1.0, 1.0, 1, 1, 0, 2)
        @test emitter_ndims(DeclaredZLoc{3,Float64}) == 3
        @test emitter_ndims(DeclaredZLoc{3,Float64}[]) == 3
        @test emitter_ndims(DeclaredZLoc) === nothing
        @test emitter_ndims(DeclaredZLoc[]) === nothing
        @test emitter_ndims(DeclaredZLoc[d2, d3]) === nothing
        empty_s = BasicSMLD(DeclaredZLoc{3,Float64}[], cam, 1, 1)
        @test isempty(filter_roi(empty_s, (0.0, 2.0), (0.0, 2.0), (-1.0, 1.0)).emitters)
    end

    @testset "emitter_ndims: precedence" begin
        cam = IdealCamera(1:64, 1:64, 0.1)
        in2 = DeclaredOnlyLoc{2,Float64}((1.0, 1.0), 100.0, 1, 1, 0, 1)
        out2 = DeclaredOnlyLoc{2,Float64}((5.0, 5.0), 100.0, 1, 1, 0, 2)
        in3 = DeclaredOnlyLoc{3,Float64}((1.0, 1.0, 0.0), 100.0, 1, 1, 0, 3)
        out3 = DeclaredOnlyLoc{3,Float64}((5.0, 5.0, 5.0), 100.0, 1, 1, 0, 4)
        @test emitter_ndims(in2) == 2
        @test emitter_ndims(in3) == 3
        @test emitter_ndims([in3, out3]) == 3
        @test emitter_ndims(DeclaredOnlyLoc{3,Float64}[]) == 3
        @test emitter_ndims(DeclaredOnlyLoc[in3, out3]) == 3
        @test emitter_ndims(DeclaredOnlyLoc[in2, in3]) === nothing
        @test emitter_ndims(DeclaredOnlyLoc{2}) == 2
        s3 = BasicSMLD([in3, out3], cam, 1, 1)
        r3 = filter_roi(s3, (0.0, 2.0), (0.0, 2.0), (-1.0, 1.0))
        @test length(r3.emitters) == 1
        @test r3.emitters[1].id == 3
        s2 = BasicSMLD([in2, out2], cam, 1, 1)
        r2 = filter_roi(s2, (0.0, 2.0), (0.0, 2.0))
        @test length(r2.emitters) == 1
        @test r2.emitters[1].id == 1

        zf = ZFieldDeclared2(1.0, 1.0, 0.0, 100.0, 1, 1, 0, 1)
        @test emitter_ndims(ZFieldDeclared2) == 2
        @test emitter_ndims(zf) == 2
        @test emitter_ndims([zf, zf]) == 2

        e2 = Emitter2DFit{Float64}(1.0, 1.0, 100.0, 1.0, 0.01, 0.01, 1.0, 1.0, frame=1)
        @test emitter_ndims(SMLMCore.AbstractEmitter[e2, e2]) == 2
    end
    @testset "emitter_ndims: instances of one type that differ" begin
        cam = IdealCamera(1:64, 1:64, 0.1)
        a2 = VarDimLoc([1.0, 1.0], 100.0, 1, 1, 0, 1)
        a3 = VarDimLoc([1.0, 1.0, 0.0], 100.0, 1, 1, 0, 2)
        for order in ([a2, a3], [a3, a2])
            @test order isa Vector{VarDimLoc}
            @test emitter_ndims(order) === nothing
            s = BasicSMLD(order, cam, 1, 1)
            @test emitter_ndims(s) === nothing
            @test_throws ErrorException(msg2onmixed) filter_roi(s, xr, yr)
            @test_throws ErrorException(msg3onmixed) filter_roi(s, xr, yr, zr)
            @test occursin("mixed 2D/3D", sprint(show, s))
        end
        @test emitter_ndims([a3, a3]) == 3
        @test emitter_ndims([a2, a2]) == 2
        r3 = filter_roi(BasicSMLD([a3, a3], cam, 1, 1), xr, yr, zr)
        @test length(r3.emitters) == 2
        r2 = filter_roi(BasicSMLD([a2, a2], cam, 1, 1), xr, yr)
        @test length(r2.emitters) == 2
    end

    @testset "empty Union of one dimension" begin
        # A Union of SMLMCore's same-dimension types declares that dimension, so ROIs behave as in
        # 0.7.0, which checked eltype <: Union{Emitter2D, Emitter2DFit} (or the 3D pair).
        cam = IdealCamera(1:64, 1:64, 0.1)
        E2 = Union{Emitter2D{Float64}, Emitter2DFit{Float64}}
        E3 = Union{Emitter3D{Float64}, Emitter3DFit{Float64}}
        @test emitter_ndims(E2[]) == 2
        @test emitter_ndims(E3[]) == 3
        s2, s3 = BasicSMLD(E2[], cam, 1, 1), BasicSMLD(E3[], cam, 1, 1)
        @test isempty(filter_roi(s2, (0.0, 1.0), (0.0, 1.0)).emitters)
        @test_throws ErrorException("3D ROI cannot be applied to 2D emitter type") filter_roi(
            s2, (0.0, 1.0), (0.0, 1.0), (-1.0, 1.0))
        @test isempty(filter_roi(s3, (0.0, 1.0), (0.0, 1.0), (-1.0, 1.0)).emitters)
        @test_throws ErrorException("2D ROI cannot be applied to 3D emitter type") filter_roi(
            s3, (0.0, 1.0), (0.0, 1.0))
        @test emitter_ndims(Emitter2DFit{Float64}[]) == 2
        @test emitter_ndims(Emitter3DFit{Float64}[]) == 3
    end

    @testset "foreign element scan allocates nothing" begin
        n = 10_000
        mkp2(i) = PropZLoc{2,Float64}((1.0, 2.0), (0.01, 0.01), 100.0, 5.0, 1.0, 1.0, 1, 1, 0, i)
        mkp3(i) = PropZLoc{3,Float64}((1.0, 2.0, 3.0), (0.01, 0.01, 0.02), 100.0, 5.0, 1.0, 1.0, 1, 1, 0, i)
        vs = (
            [ForeignEmitter2D{Float64}(1.0, 2.0, 1000.0, 1, 1, 0, i) for i in 1:n],
            [ForeignEmitter3D{Float64}(1.0, 2.0, 3.0, 1000.0, 1, 1, 0, i) for i in 1:n],
            [mkp2(i) for i in 1:n],
            [mkp3(i) for i in 1:n],
            [VarDimLoc([1.0, 1.0], 100.0, 1, 1, 0, i) for i in 1:n],
            [VarDimLoc([1.0, 1.0, 0.0], 100.0, 1, 1, 0, i) for i in 1:n],
        )
        for v in vs
            _nd_alloc(v)   # warm up
            @test _nd_alloc(v) == 0
        end
    end


    @testset "show labels mixed and unknown dimensions" begin
        cam = IdealCamera(1:64, 1:64, 0.1)
        A = SMLMCore.AbstractEmitter
        e2 = Emitter2DFit{Float64}(1.0, 1.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0)
        e3 = Emitter3DFit{Float64}(1.0, 1.0, 0.0, 1000.0, 10.0, 0.01, 0.01, 0.02, 50.0, 2.0)
        s = BasicSMLD(A[e2, e3], cam, 1, 1)
        @test occursin("mixed 2D/3D", sprint(show, s))
        @test occursin("mixed 2D/3D localizations", sprint(show, MIME("text/plain"), s))
        @test occursin("unknown-dimension", sprint(show, BasicSMLD(A[], cam, 1, 1)))
    end


    @testset "bottom element type" begin
        # Union{} is a subtype of every type declared in this file (DeclaredZLoc, DeclaredOnlyLoc,
        # ZFieldDeclared2); its own method answers without ambiguity.
        cam = IdealCamera(1:64, 1:64, 0.1)
        @test emitter_ndims(Union{}) === nothing
        @test emitter_ndims(Union{}[]) === nothing
        @test emitter_ndims(BasicSMLD(Union{}[], cam, 1, 1)) === nothing
    end



end

# A @filter condition may use the caller's variables and functions; 0.1.0 read every name in it
# as an emitter field and threw for a variable, ≤, abs, ! or a range.
@testset "@filter with names from the caller" begin
    cam = IdealCamera(64, 64, 0.1)
    s = BasicSMLD([Emitter2DFit{Float64}(x, 1.0, ph, 5.0, 0.01, 0.01, 50.0, 2.0; frame = f, dataset = d)
                   for (x, ph, f, d) in ((0.5, 900.0, 1, 1), (1.5, 1100.0, 2, 2), (-2.0, 1300.0, 3, 1))],
                  cam, 3, 2, Dict{String,Any}("k" => 1))
    xs(r) = [e.x for e in r.emitters]

    thr = 1000.0
    @test xs(@filter(s, photons > thr)) == [1.5, -2.0]
    @test xs(@filter(s, x ≤ 1.0)) == [0.5, -2.0]
    @test xs(@filter(s, x ≥ 1.0)) == [1.5]
    @test xs(@filter(s, abs(x) < 1.0)) == [0.5]
    @test xs(@filter(s, !(frame == 2))) == [0.5, -2.0]
    @test xs(@filter(s, frame in 1:2)) == [0.5, 1.5]
    @test xs(@filter(s, x + 1.0 > 2.0)) == [1.5]
    @test xs(@filter(s, photons > thr && frame != 3)) == [1.5]
    @test xs(@filter(s, x < Inf && photons < typemax(Float64))) == [0.5, 1.5, -2.0]
    near(a; to) = abs(a - to) < 0.6
    @test xs(@filter(s, near(x; to = 1.0))) == [0.5, 1.5]
    @test xs(@filter(s, any(t -> photons > t, (1200.0, 1250.0)))) == [-2.0]

    # A name that is both a property and a variable reads the property; $name is the variable
    dataset = 2
    @test xs(@filter(s, dataset == dataset)) == [0.5, 1.5, -2.0]
    @test xs(@filter(s, dataset == $dataset)) == [1.5]
    per_frame(s) = [length(@filter(s, frame == $f)) for f in 1:3]
    @test per_frame(s) == [1, 1, 1]

    # A name that is neither throws getproperty's error, naming it, when the condition runs
    # (a FieldError from Julia 1.12, an ErrorException before), as 0.1.0 did
    err = try
        @filter(s, photons > not_defined_anywhere); nothing
    catch ex
        ex
    end
    @test err isa Exception && occursin("not_defined_anywhere", sprint(showerror, err))

    # The data-set expression is evaluated once
    calls = Ref(0)
    get_s() = (calls[] += 1; s)
    @filter(get_s(), photons > 0)
    @test calls[] == 1

    # The result is as before: same type, camera and counts, copied metadata, the input's emitters
    r = @filter(s, photons > thr)
    @test r isa typeof(s)
    @test r.camera === s.camera && r.n_frames == 3 && r.n_datasets == 2
    @test r.metadata == s.metadata && r.metadata !== s.metadata
    @test r.emitters[1] === s.emitters[2]
    @test @inferred(SMLMCore._filter_smld(s, e -> e.photons > 1000.0)) isa typeof(s)
end

# An emitter whose property `accept` holds a function, for the call-position rule
struct AcceptTestEmitter <: SMLMCore.AbstractEmitter
    x::Float64
    y::Float64
    photons::Float64
    accept::Function
end
_never(v) = false
_lower_than(v; lo) = v < lo
_filter_in_function(s, t) = (x_max = t; @filter(s, x < x_max && frame in 1:2))

@testset "@filter: names the condition binds, calls, and 0.1.0 forms" begin
    cam = IdealCamera(64, 64, 0.1)
    s = BasicSMLD([Emitter2DFit{Float64}(x, 1.0, ph, 5.0, sx, sx, 50.0, 2.0; frame = f, dataset = d)
                   for (x, ph, f, d, sx) in ((0.5, 900.0, 1, 1, 0.01), (1.5, 1100.0, 2, 2, 0.03),
                                             (-2.0, 1300.0, 3, 1, 0.01))],
                  cam, 3, 2, Dict{String,Any}())
    xs(r) = [e.x for e in r.emitters]

    # A name bound by the condition is its own, even when it is also a property
    @test xs(@filter(s, all(x -> x < 0.02, (σ_x, σ_y)))) == [0.5, -2.0]
    @test xs(@filter(s, any(x > 1.0 for x in (0.0, 0.5)))) == Float64[]
    @test xs(@filter(s, any(x > 5 for x in (10,)))) == [0.5, 1.5, -2.0]
    @test xs(@filter(s, sum(v for v in (x, photons) if v > 1) > 1000)) == [1.5, -2.0]
    @test xs(@filter(s, [x for x in (x,)][1] > 0)) == [0.5, 1.5]   # the iterator's x is the property
    @test xs(@filter(s, let frame = 9; frame == 9 end)) == [0.5, 1.5, -2.0]
    @test xs(@filter(s, let f = frame; f == 2 end)) == [1.5]
    @test xs(@filter(s, begin y2 = 2x; y2 > 1.0 end)) == [1.5]

    # Locals of the calling function, and `$name` there
    @test xs(_filter_in_function(s, 1.0)) == [0.5]
    g(s) = (frame = 2; @filter(s, frame == $frame))
    @test xs(g(s)) == [1.5]

    # The function called follows the same rule: the emitter's property, else the caller's;
    # `$f` is always the caller's. Broadcast calls too.
    sa = BasicSMLD([AcceptTestEmitter(1.0, 1.0, 1.0, v -> v > 0.5),
                    AcceptTestEmitter(0.2, 1.0, 1.0, v -> v > 0.5)], cam, 1, 1)
    accept = _never
    @test length(@filter(sa, accept(x))) == 1
    @test length(@filter(sa, $accept(x))) == 0
    @test xs(@filter(s, abs.(x) .> 1.0)) == [1.5, -2.0]
    @test xs(@filter(s, $abs(x) > 1.0)) == [1.5, -2.0]

    # Macros, keyword names and the `; lo` shorthand, and quoted code are left as written
    @test xs(@filter(s, @inbounds(x > 1.0))) == [1.5]
    @test xs(@filter(s, occursin(r"^1", string(x)))) == [1.5]
    lo = 1.0
    @test xs(@filter(s, _lower_than(x; lo))) == [0.5, -2.0]
    @test xs(@filter(s, _lower_than(x; lo = 0.0))) == [-2.0]
    @test xs(@filter(s, only(isapprox.((x,), 1.5; atol = 0.1)))) == [1.5]
    q = :(x + 1)
    @test xs(@filter(s, q == :(x + 1))) == [0.5, 1.5, -2.0]

    # 0.1.0 forms: e.name reads the emitter; a property computed by getproperty but not listed in
    # propertynames is read when no variable of that name is defined
    @test xs(@filter(s, e.x > 1)) == [1.5]
    e = 7
    @test xs(@filter(s, e.x > 1)) == [1.5]
    d = BasicSMLD([DeclaredOnlyLoc{2,Float64}((0.5, 1.0), 1000.0, 1, 1, 0, 0),
                   DeclaredOnlyLoc{2,Float64}((1.5, 1.0), 1000.0, 1, 1, 0, 0)], cam, 1, 1)
    @test [p.x for p in (@filter(d, x > 1.0)).emitters] == [1.5]
    @test_throws Exception @filter(s, no_such_name > 1)   # getproperty's error

    # A number as the answer keeps by its truth, as in 0.1.0; it never selects by position
    @test xs(@filter(s, 1)) == [0.5, 1.5, -2.0]
    @test xs(@filter(s, 0)) == Float64[]
    @test_throws InexactError @filter(s, frame)
end

@testset "filter_roi warns for ranges that may have lost their stop" begin
    cam = IdealCamera(64, 64, 0.1)
    xs = [0.2, 0.95, 1.0, 1.6, 1.8]
    s2 = BasicSMLD([Emitter2D{Float64}(x, 1.0, 1000.0) for x in xs], cam, 1, 1)
    s3 = BasicSMLD([Emitter3D{Float64}(x, 1.0, 0.5, 1000.0) for x in xs], cam, 1, 1)
    getx(r) = [e.x for e in r.emitters]
    warned = (:warn, r"filter_roi takes the range .* as the bounds .*Pass the bounds as a tuple")

    # Tuples, vectors and whole numbers in steps of 1 end where written: no warning
    r = @test_logs filter_roi(s2, (0.5, 1.7), (0.0, 2.0))
    @test getx(r) == [0.95, 1.0, 1.6]
    @test_logs filter_roi(s2, [0.5, 1.7], [0.0, 2.0])
    @test_logs filter_roi(s2, 0:2, 0:2)
    @test_logs filter_roi(s2, Base.OneTo(2), 0:2)
    @test_logs filter_roi(s2, 0:1:2, 2:-1:0)                    # step 1 written out, or -1
    @test_logs filter_roi(s2, 0:2, UnitRange(0, 2))
    @test_logs filter_roi(s3, (0.0, 2.0), (0.0, 2.0), (0.0, 1.0))

    # Any other range warns; the bounds and so the result are those of 0.1.0
    r = @test_logs warned filter_roi(s2, 0.0:0.3:1.0, (0.0, 2.0))
    @test getx(r) == [0.2]                         # the range ends at 0.9, not at 1.0
    @test_logs (:warn, r"as the bounds 0\.0 to 0\.9") filter_roi(s2, 0.0:0.3:1.0, (0.0, 2.0))
    r = @test_logs warned filter_roi(s2, 0.5:1.7, (0.0, 2.0))
    @test getx(r) == [0.95, 1.0]                   # 0.5:1.7 is 0.5:1.5
    @test getx(@test_logs warned filter_roi(s2, 0.0:2.0, 1.0:3.0)) == xs
    @test_logs warned filter_roi(s2, 0:2:8, (0.0, 2.0))       # integer steps of 2 may skip a stop
    @test_logs warned filter_roi(s2, (0.0, 2.0), 0.0:2.0)
    @test_logs warned filter_roi(s3, (0.0, 2.0), (0.0, 2.0), 0.0:0.5:1.0)
    @test_logs warned filter_roi(s3, 0.0:2.0, (0.0, 2.0), (0.0, 1.0))
    @test_logs warned filter_roi(s2, 2.0:-1.0:0.0, (0.0, 2.0))   # descending: bounds 0 to 2

    # Once per logger: two ranges in one call, then a second call, give one warning
    @test_logs warned begin
        filter_roi(s2, 0.0:2.0, 1.0:3.0)
        filter_roi(s3, 0.0:2.0, 0.0:2.0, 0.0:1.0)
    end
end

# A condition's assignments must not reach the caller's locals
function _filter_assigns(s)
    y2 = 100.0
    @filter(s, begin y2 = 2x; y2 > 1.0 end)
    return y2
end
function _filter_loop_assigns(s)
    t = 0
    @filter(s, begin for i in 1:2; t = frame; end; true end)
    return t
end

# Emitters with properties named like operators
struct OperatorNamedEmitter <: SMLMCore.AbstractEmitter
    x::Float64
    y::Float64
    photons::Float64
    var"in"::Function
    var"+"::Function
end
function _filter_nested_local(s)
    tmp = 11
    @filter(s, begin tmp = 2; let; local tmp = 8; end; true end)
    return tmp
end
function _filter_let_shadow(s)
    cutoff = 2
    return [e.x for e in @filter(s, begin let cutoff = 0; cutoff += 1; end; x <= cutoff end).emitters]
end

@testset "@filter follows Julia's scope rules" begin
    cam = IdealCamera(64, 64, 0.1)
    s = BasicSMLD([Emitter2DFit{Float64}(x, 1.0, ph, 5.0, 0.01, 0.01, 50.0, 2.0; frame = f)
                   for (x, ph, f) in ((0.5, 900.0, 1), (1.5, 1100.0, 2), (-2.0, 1300.0, 3))], cam, 3, 1)
    xs(r) = [e.x for e in r.emitters]
    every = [0.5, 1.5, -2.0]

    # Loops, local declarations, functions it defines, catch, assignments inside if, while
    @test xs(@filter(s, begin acc = 0.0; for x in (1.0, 2.0); acc += x; end; acc > 2.5 end)) == every
    @test xs(@filter(s, begin local x = 10; x > 5 end)) == every
    @test xs(@filter(s, begin f(x) = x > 5; f(10) end)) == every
    @test xs(@filter(s, begin function g(x) x > 5 end; g(10) end)) == every
    @test xs(@filter(s, try error("a"); catch x; x isa ErrorException end)) == every
    @test xs(@filter(s, begin if true; x = 10; end; x > 5 end)) == every
    @test xs(@filter(s, begin y = 0; for x in (10,); y = x; end; y > 5 end)) == every
    @test xs(@filter(s, begin i = 0; while i < 3; i += 1; end; i == 3 end)) == every
    # The loop body assigns the condition's own x, as Julia's rules say for an enclosing local
    @test xs(@filter(s, begin for i in 1:1; x = 10; end; x > 1.0 end)) == every
    @test xs(@filter(s, begin n = 0; for frame in 3:4, j in 1:frame; n += 1; end; n == 7 end)) == every
    @test xs(@filter(s, begin i = 0; while (x = i; x < 1); i += 1; end; i == 1 end)) == every
    @test xs(@filter(s, any(i for i in (true,) if (x = 10; x > 5)))) == every
    @test xs(@filter(s, let f(x) = x > 5; f(10) end)) == every
    @test xs(@filter(s, begin f(x)::Bool = x > 5; f(10) end)) == every
    @test xs(@filter(s, begin function h(x)::Bool; x > 5; end; h(10) end)) == every
    @test xs(@filter(s, begin f(t = x) = t > 1; f() end)) == [1.5]
    @test xs(@filter(s, let a = falses(3); a[frame] = true; a[2] end)) == [1.5]
    counts = zeros(Int, 3)
    @test xs(@filter(s, (counts[frame] += 1) <= 1)) == every
    @test counts == [1, 1, 1]
    @test _filter_nested_local(s) == 11
    @test _filter_let_shadow(s) == every

    # The caller's variables are not written
    @test _filter_assigns(s) == 100.0
    @test _filter_loop_assigns(s) == 0

    # `$expr` is the caller's value, whatever the condition binds
    x = 7
    @test xs(@filter(s, any(x -> x == $x, (4,)))) == Float64[]
    @test xs(@filter(s, any(x -> x == $x, (7,)))) == every
    f = _ -> false
    @test xs(@filter(s, let f = _ -> true; $f(x) end)) == Float64[]
    calls = Ref(0)
    count_call() = (calls[] += 1; 1.0)
    @filter(s, x > $(count_call()))
    @test calls[] == 1                                        # evaluated once
    @filter(s, @inbounds x > $(count_call()))
    @test calls[] == 2                                        # inside another macro too
    @test xs(@filter(s, any(x -> @inbounds(x == $x), (4,)))) == Float64[]

    # Macros expand first: a nested @filter has its own emitters; @isdefined sees the caller
    t = BasicSMLD([Emitter2DFit{Float64}(9.0, 1.0, 1.0, 5.0, 0.01, 0.01, 50.0, 2.0)], cam, 1, 1)
    @test xs(@filter(s, !isempty((@filter(t, x > 5)).emitters))) == every
    @test xs(@filter(s, length(@filter(s, frame == 2)) == 1)) == every
    @test xs(@filter(s, @isdefined(no_such_thing) || x > 1)) == [1.5]
    # a free name in the nested condition follows the outer one: the outer emitter's frame
    t2 = BasicSMLD([Emitter2D{Float64}(9.0, 1.0, 1.0)], cam, 1, 1)
    frame = 2
    @test xs(@filter(s, length(@filter(t2, frame == 2)) == 1)) == [1.5]

    # Operators passed as values keep their meaning, even beside a property of that name
    @test xs(@filter(s, all((.>)([x], 0)))) == [0.5, 1.5]
    @test xs(@filter(s, reduce(+, (1, 2)) == 3)) == every
    so = BasicSMLD([OperatorNamedEmitter(1.0, 1.0, 1.0, (a...) -> 42, (a...) -> 42)], cam, 1, 1)
    @test length(@filter(so, reduce(+, (1, 2)) == 3)) == 1
    @test length(@filter(so, map(in, (1,), ((1, 2),)) == (true,))) == 1
    @test length(@filter(so, in(1, (1, 2)))) == 1
end

# A getter that counts its reads
mutable struct TickingEmitter <: SMLMCore.AbstractEmitter
    x::Float64
    y::Float64
    photons::Float64
    n::Int
end
Base.getproperty(t::TickingEmitter, s::Symbol) =
    s === :tick ? (setfield!(t, :n, getfield(t, :n) + 1); getfield(t, :n)) : getfield(t, s)
# A caller that assigns a property's name after filtering (a captured local would be boxed)
function _filter_then_assign(s)
    r = @filter(s, photons > 1000)
    photons = [e.photons for e in r.emitters]
    return sum(photons)
end
function _filter_nested_global(s)
    tmp = 11
    @filter(s, begin tmp = 2; let; global tmp; end; true end)
    return tmp
end
_filter_global_counter = 0

@testset "@filter reads properties where reached, callers once" begin
    cam = IdealCamera(64, 64, 0.1)
    s = BasicSMLD([Emitter2DFit{Float64}(x, 1.0, ph, 5.0, 0.01, 0.01, 50.0, 2.0; frame = f)
                   for (x, ph, f) in ((0.5, 900.0, 1), (1.5, 1100.0, 2), (-2.0, 1300.0, 3))], cam, 3, 1)
    xs(r) = [e.x for e in r.emitters]
    every = [0.5, 1.5, -2.0]

    # A property is read only where the condition reaches it, as in 0.1.0
    mixed = BasicSMLD(SMLMCore.AbstractEmitter[Emitter2D{Float64}(1.0, 1.0, 1.0),
                                               Emitter3D{Float64}(2.0, 1.0, 0.5, 1000.0)], cam, 1, 1)
    @test [e.x for e in @filter(mixed, photons > 100 && z > 0).emitters] == [2.0]
    tk = BasicSMLD([TickingEmitter(1.0, 1.0, 1.0, 0)], cam, 1, 1)
    @test length(@filter(tk, tick < tick)) == 1

    # A caller variable is read once, outside the emitter function: no box in the caller
    @test Base.return_types(_filter_then_assign, (typeof(s),)) == [Float64]
    @test _filter_then_assign(s) == 2400.0

    # e.x is the emitter's, except inside a construct that binds e
    e = (x = -1.0,)
    @test xs(@filter(s, e.x > 0 && all(e -> e > 0, (1, 2)))) == [0.5, 1.5]

    # A catch variable is the condition's own, whatever its name
    @test xs(@filter(s, try error("a"); catch err; err isa ErrorException end)) == every
    # `end` in an index is not a name
    @test xs(@filter(s, (x, frame)[end] == 2)) == [1.5]
    # A name declared global in an inner scope leaves the condition's own binding alone
    @test _filter_nested_global(s) == 11
    # and a global the condition declares is the module's
    @filter(s, begin global _filter_global_counter += 1; true end)
    @test _filter_global_counter == 3

    # A nested @filter keeps its own `$`, under any name it is imported as
    t = BasicSMLD([Emitter2DFit{Float64}(1.0, 1.0, 1000.0, 5.0, 0.01, 0.01, 50.0, 2.0)], cam, 1, 1)
    c = Ref(0)
    r1 = xs(@filter(s, !isempty(@filter(t, x == $(c[] += 1)).emitters)))
    @test c[] == 3
    c[] = 0
    @test xs(@filter(s, !isempty(@keep(t, x == $(c[] += 1)).emitters))) == r1
    @test c[] == 3

    # Types in argument lists are not names
    @test xs(@filter(s, any((v::Float64) -> v > 0, (x,)))) == [0.5, 1.5]
    @test xs(@filter(s, any(((v::T) where {T<:Real}) -> v > 1, (x,)))) == [1.5]
    @test xs(@filter(s, any((::Float64) -> true, (x,)))) == every
end
