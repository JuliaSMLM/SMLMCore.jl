using SMLMCore, Test

# A camera that wraps another camera and adds a fixed background pattern
struct WrappedTestCamera{C<:SMLMCore.AbstractCamera} <: SMLMCore.AbstractCamera
    base::C
    background::Matrix{Float64}
end
# A camera that keeps its calibration in a struct, and one that holds a tuple of cameras
struct TestCalibration
    gain::Matrix{Float64}
end
struct CalibratedTestCamera <: SMLMCore.AbstractCamera
    pixel_edges_x::Vector{Float64}
    pixel_edges_y::Vector{Float64}
    calibration::TestCalibration
end
struct PairTestCamera <: SMLMCore.AbstractCamera
    cameras::Tuple{IdealCamera{Float64},IdealCamera{Float64}}
end
# An immutable emitter type, and one whose frame and dataset are properties, not fields
struct ImmutableTestEmitter <: SMLMCore.AbstractEmitter
    x::Float64
    y::Float64
    frame::Int32
    dataset::Int32
end
mutable struct PropertyTestEmitter <: SMLMCore.AbstractEmitter
    x::Float64
    y::Float64
    fr::Int
    ds::Int
end
const _PROPMAP = (frame = :fr, dataset = :ds)
Base.getproperty(e::PropertyTestEmitter, s::Symbol) = getfield(e, get(_PROPMAP, s, s))
Base.setproperty!(e::PropertyTestEmitter, s::Symbol, v) = setfield!(e, get(_PROPMAP, s, s), v)
# Emitter types with a frame field and no dataset field, one mutable and one immutable
mutable struct FrameOnlyMutable <: SMLMCore.AbstractEmitter
    x::Float64
    frame::Int
end
struct FrameOnlyImmutable <: SMLMCore.AbstractEmitter
    x::Float64
    frame::Int
end
# A dataset that may be nothing; a setter that keeps a derived field in step; a field that may
# be left undefined
mutable struct MaybeDatasetEmitter <: SMLMCore.AbstractEmitter
    frame::Int
    dataset::Union{Nothing,Int}
end
mutable struct TimedTestEmitter <: SMLMCore.AbstractEmitter
    frame::Int
    dataset::Int
    t::Float64                      # frame * 0.01 s, kept in step by setproperty!
end
function Base.setproperty!(e::TimedTestEmitter, s::Symbol, v)
    setfield!(e, s, convert(fieldtype(TimedTestEmitter, s), v))
    s === :frame && setfield!(e, :t, 0.01 * v)
    return v
end
mutable struct ExtraTestEmitter <: SMLMCore.AbstractEmitter
    frame::Int
    dataset::Int
    extra::Vector{Float64}
    ExtraTestEmitter(f, d) = new(f, d)
    ExtraTestEmitter(f, d, v) = new(f, d, v)
end
struct ImmutableMaybeDataset <: SMLMCore.AbstractEmitter
    frame::Int
    dataset::Union{Nothing,Int}
end
# Immutable emitters whose constructors can leave trailing fields unset
struct ImmutableExtraEmitter <: SMLMCore.AbstractEmitter
    frame::Int
    dataset::Int
    extra::Vector{Float64}
    ImmutableExtraEmitter(f, d) = new(f, d)
    ImmutableExtraEmitter(f, d, v) = new(f, d, v)
end
struct LateNumbersEmitter <: SMLMCore.AbstractEmitter
    extra::Vector{Float64}
    frame::Int
    dataset::Int
    LateNumbersEmitter() = new()
    LateNumbersEmitter(v, f, d) = new(v, f, d)
end
# An SMLD type that stores its counts as another integer type
struct CountTestSMLD{E<:SMLMCore.AbstractEmitter,C<:Integer} <: SMLMCore.AbstractSMLD
    emitters::Vector{E}
    camera::SMLMCore.AbstractCamera
    n_frames::C
    n_datasets::C
    metadata::Dict{String,Any}
end
# A camera with a dictionary of settings, and one with a vector of vectors
struct Setting
    value::Vector{Float64}
end
struct DictTestCamera <: SMLMCore.AbstractCamera
    settings::AbstractDict
end
struct NestedTestCamera <: SMLMCore.AbstractCamera
    maps::Vector{Vector{Float64}}
end
# A camera with a cache field that may be left undefined
struct CachedTestCamera <: SMLMCore.AbstractCamera
    pixel_edges_x::Vector{Float64}
    pixel_edges_y::Vector{Float64}
    cache::Vector{Float64}
    CachedTestCamera(x, y) = new(x, y)
    CachedTestCamera(x, y, c) = new(x, y, c)
end
# A camera that lists cameras, itself included (a cycle)
struct ListingTestCamera <: SMLMCore.AbstractCamera
    pixel_edges_x::Vector{Float64}
    pixel_edges_y::Vector{Float64}
    cameras::Vector{Any}
end
function self_listing_camera()
    cam = ListingTestCamera([0.0, 0.1], [0.0, 0.1], Any[])
    push!(cam.cameras, cam)
    return cam
end
# A mutable camera type whose field refers back to the camera
mutable struct SelfTestCamera <: SMLMCore.AbstractCamera
    pixel_edges_x::Vector{Float64}
    me::Any
    function SelfTestCamera(x)
        c = new(x)
        c.me = c
        return c
    end
end
# A camera holding a mutable instrument object that has no == method
mutable struct TestInstrument
    name::String
end
struct InstrumentTestCamera <: SMLMCore.AbstractCamera
    pixel_edges_x::Vector{Float64}
    pixel_edges_y::Vector{Float64}
    inst::TestInstrument
end
# Cameras with abstractly typed fields, which may hold arrays or tuples of different types
struct AbstractMapsTestCamera <: SMLMCore.AbstractCamera
    maps::AbstractArray
end
struct TupleTestCamera <: SMLMCore.AbstractCamera
    t::Tuple
end
struct AbstractBaseTestCamera <: SMLMCore.AbstractCamera
    base::SMLMCore.AbstractCamera
end
# A camera holding a setting whose == returns missing
struct MissingEqSetting
    value::Vector{Float64}
end
Base.:(==)(::MissingEqSetting, ::MissingEqSetting) = missing
struct MissingEqTestCamera <: SMLMCore.AbstractCamera
    setting::MissingEqSetting
end

@testset "SMLD Operations" begin
    # Setup helper function to create test data
    function create_test_smld(frame_range, dataset_num=1)
        cam = IdealCamera(1:512, 1:512, 0.1)
        emitters = [
            Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0,
                                frame=f, dataset=dataset_num, track_id=1, id=i)
            for (i, f) in enumerate(frame_range)
        ]
        return BasicSMLD(emitters, cam, maximum(frame_range), dataset_num, 
                        Dict{String,Any}("original_frames" => frame_range))
    end

    @testset "cat_smld" begin
        @testset "Basic Concatenation" begin
            smld1 = create_test_smld(1:2)
            smld2 = create_test_smld(3:4)
            
            # Test varargs version
            result = cat_smld(smld1, smld2)
            @test length(result.emitters) == 4
            @test result.n_frames == 4
            @test result.n_datasets == 1
            
            # Test vector version
            result_vec = cat_smld([smld1, smld2])
            @test length(result_vec.emitters) == 4
            @test result_vec.n_frames == 4
        end

        @testset "Camera Compatibility" begin
            smld1 = create_test_smld(1:2)
            # Create SMLD with different camera
            cam2 = IdealCamera(1:256, 1:256, 0.1)
            emitters2 = [
                Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0)
            ]
            smld2 = BasicSMLD(emitters2, cam2, 1, 1, Dict{String,Any}())
            
            # Should error on different cameras
            @test_throws ErrorException cat_smld(smld1, smld2)
        end

        @testset "Camera Calibration" begin
            # Same pixels, different calibration: not the same camera
            em = [Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0)]
            rn = fill(1.5, 16, 16); rn[3, 4] = 2.0
            s_map = BasicSMLD(em, SCMOSCamera(16, 16, 0.1, rn), 1, 1, Dict{String,Any}())
            s_scalar = BasicSMLD(em, SCMOSCamera(16, 16, 0.1, 1.5), 1, 1, Dict{String,Any}())
            s_gain = BasicSMLD(em, SCMOSCamera(16, 16, 0.1, rn; gain = 0.5), 1, 1, Dict{String,Any}())
            @test_throws ErrorException cat_smld(s_map, s_scalar)
            @test_throws ErrorException merge_smld(s_map, s_scalar)
            @test_throws ErrorException cat_smld(s_map, s_gain)
            @test_throws ErrorException merge_smld(s_map, s_gain)

            # Equal cameras built separately are the same camera
            s_map2 = BasicSMLD(em, SCMOSCamera(16, 16, 0.1, copy(rn)), 1, 1, Dict{String,Any}())
            @test length(cat_smld(s_map, s_map2).emitters) == 2
            @test length(merge_smld(s_map, s_map2).emitters) == 2

            # A scalar calibration and a uniform map of the same value are different cameras
            s_uniform = BasicSMLD(em, SCMOSCamera(16, 16, 0.1, fill(1.5, 16, 16)), 1, 1, Dict{String,Any}())
            @test_throws ErrorException merge_smld(s_scalar, s_uniform)

            # The error names the input and the fields that differ, or the two camera types
            errmsg(f) = try
                f(); ""
            catch e
                e isa ErrorException ? e.msg : string(typeof(e))
            end
            s_gq = BasicSMLD(em, SCMOSCamera(16, 16, 0.1, rn; gain = 0.5, qe = 0.9), 1, 1, Dict{String,Any}())
            @test errmsg(() -> merge_smld(s_map, s_map2, s_gain)) ==
                "Cannot merge SMLDs with different cameras: input 3's camera differs from input 1's in field gain"
            @test errmsg(() -> cat_smld(s_map, s_gq)) ==
                "Cannot concatenate SMLDs with different cameras: input 2's camera differs from input 1's in fields gain, qe"
            @test occursin("in field readnoise", errmsg(() -> cat_smld(s_map, s_scalar)))
            s_ideal = BasicSMLD(em, IdealCamera(1:16, 1:16, 0.1), 1, 1, Dict{String,Any}())
            # (a type prints with or without its module, depending on where the test runs)
            msg = errmsg(() -> merge_smld(s_map, s_ideal))
            @test occursin("input 2's camera differs from input 1's in type (", msg)
            @test occursin(r"\(\S*IdealCamera\{Float64\}, not \S*SCMOSCamera\{Float64\}\)$", msg)

            # Calibration held in a struct, and a tuple of cameras, compare by value
            cc(g) = CalibratedTestCamera([0.0, 0.1], [0.0, 0.1], TestCalibration(fill(g, 1, 1)))
            @test SMLMCore.is_same_camera(cc(2.0), cc(2.0))
            @test !SMLMCore.is_same_camera(cc(2.0), cc(3.0))
            pc(p) = PairTestCamera((IdealCamera(1:4, 1:4, 0.1), IdealCamera(1:4, 1:4, p)))
            @test SMLMCore.is_same_camera(pc(0.1), pc(0.1))
            @test !SMLMCore.is_same_camera(pc(0.1), pc(0.2))

            # A camera that wraps another is compared field by field, the wrapped camera included
            base = IdealCamera(1:16, 1:16, 0.1)
            bg = fill(2.0, 16, 16)
            @test SMLMCore.is_same_camera(WrappedTestCamera(base, bg), WrappedTestCamera(IdealCamera(1:16, 1:16, 0.1), copy(bg)))
            @test !SMLMCore.is_same_camera(WrappedTestCamera(base, bg), WrappedTestCamera(base, bg .+ 1))
            @test !SMLMCore.is_same_camera(WrappedTestCamera(base, bg), WrappedTestCamera(IdealCamera(1:16, 1:16, 0.2), bg))

            # Edges compare with == as before (-0.0 == 0.0); NaN matches NaN, in a map or in edges
            @test SMLMCore.is_same_camera(IdealCamera([-0.0, 0.1], [0.0, 0.1]), IdealCamera([0.0, 0.1], [0.0, 0.1]))
            rn_nan = copy(rn); rn_nan[1, 1] = NaN
            @test SMLMCore.is_same_camera(SCMOSCamera(16, 16, 0.1, rn_nan), SCMOSCamera(16, 16, 0.1, copy(rn_nan)))
            @test SMLMCore.is_same_camera(IdealCamera([NaN, 0.1], [0.0, 0.1]), IdealCamera([NaN, 0.1], [0.0, 0.1]))
            rn_negnan = copy(rn); rn_negnan[1, 1] = -NaN    # another NaN bit pattern: == fails, isequal matches
            @test SMLMCore.is_same_camera(SCMOSCamera(16, 16, 0.1, rn_nan), SCMOSCamera(16, 16, 0.1, rn_negnan))
            # NaN and a -0.0 in the same map or edges: neither == nor isequal alone matches them
            rn_nz = copy(rn_nan); rn_nz[2, 1] = -0.0
            rn_pz = copy(rn_nan); rn_pz[2, 1] = 0.0
            @test SMLMCore.is_same_camera(SCMOSCamera(16, 16, 0.1, rn_nz), SCMOSCamera(16, 16, 0.1, rn_pz))
            @test SMLMCore.is_same_camera(IdealCamera([NaN, -0.0, 0.1], [0.0, 0.1]), IdealCamera([NaN, 0.0, 0.1], [0.0, 0.1]))
            @test !SMLMCore.is_same_camera(IdealCamera([NaN, -0.0, 0.1], [0.0, 0.1]), IdealCamera([NaN, 0.05, 0.1], [0.0, 0.1]))

            # A field left undefined matches only one left undefined
            e2 = [0.0, 0.1]
            @test SMLMCore.is_same_camera(CachedTestCamera(e2, e2), CachedTestCamera(copy(e2), copy(e2)))
            @test !SMLMCore.is_same_camera(CachedTestCamera(e2, e2), CachedTestCamera(e2, e2, [1.0]))
            @test SMLMCore.is_same_camera(CachedTestCamera(e2, e2, [1.0]), CachedTestCamera(e2, e2, [1.0]))

            # Dictionaries compare entry by entry, never by their internal storage
            dc(s, v) = DictTestCamera(Dict{String,Any}("serial" => s, "gain" => Setting([v])))
            @test SMLMCore.is_same_camera(dc("A1", 2.0), dc("A1", 2.0))
            @test !SMLMCore.is_same_camera(dc("A1", 2.0), dc("B2", 2.0))
            @test !SMLMCore.is_same_camera(dc("A1", 2.0), dc("A1", 3.0))
            dn(g) = DictTestCamera(Dict{String,Float64}("gain" => g, "offset" => 100.0))
            @test all(SMLMCore.is_same_camera(dn(NaN), dn(NaN)) for _ in 1:20)
            @test !SMLMCore.is_same_camera(dn(NaN), dn(1.0))
            @test SMLMCore.is_same_camera(dn(1.0), DictTestCamera(Dict{String,Any}("offset" => 100, "gain" => 1.0)))
            # A dictionary with an extra key, or other keys, is a different camera, in either order
            dbig = DictTestCamera(Dict{String,Float64}("gain" => 1.0, "offset" => 100.0, "qe" => 0.7))
            @test !SMLMCore.is_same_camera(dn(1.0), dbig)
            @test !SMLMCore.is_same_camera(dbig, dn(1.0))
            @test !SMLMCore.is_same_camera(dn(1.0), DictTestCamera(Dict{String,Float64}("gain" => 1.0, "qe" => 0.7)))
            # missing matches missing (a map with missing entries)
            @test SMLMCore.is_same_camera(AbstractMapsTestCamera(Union{Missing,Float64}[missing, NaN, -0.0]), AbstractMapsTestCamera(Union{Missing,Float64}[missing, NaN, 0.0]))
            @test !SMLMCore.is_same_camera(AbstractMapsTestCamera(Union{Missing,Float64}[missing, 1.0]), AbstractMapsTestCamera(Union{Missing,Float64}[1.0, 1.0]))
            # An abstractly typed camera field holding cameras of two types is different, not an error
            @test !SMLMCore.is_same_camera(AbstractBaseTestCamera(IdealCamera(1:4, 1:4, 0.1)), AbstractBaseTestCamera(SCMOSCamera(4, 4, 0.1, 1.5)))
            @test SMLMCore.is_same_camera(AbstractBaseTestCamera(IdealCamera(1:4, 1:4, 0.1)), AbstractBaseTestCamera(IdealCamera(1:4, 1:4, 0.1)))

            # Arrays with empty slots compare without throwing, also when their types differ
            nv() = (v = Vector{Vector{Float64}}(undef, 2); v[1] = [1.0]; v)
            @test SMLMCore.is_same_camera(NestedTestCamera(nv()), NestedTestCamera(nv()))
            w = nv(); w[2] = [2.0]
            @test !SMLMCore.is_same_camera(NestedTestCamera(nv()), NestedTestCamera(w))
            na() = (v = Vector{Any}(undef, 2); v[1] = [1.0]; v)
            @test SMLMCore.is_same_camera(AbstractMapsTestCamera(nv()), AbstractMapsTestCamera(na()))
            wa = na(); wa[2] = [1.0]
            @test !SMLMCore.is_same_camera(AbstractMapsTestCamera(nv()), AbstractMapsTestCamera(wa))
            nb = Vector{Any}(undef, 2); nb[1] = 1.0
            @test !SMLMCore.is_same_camera(AbstractMapsTestCamera([1.0, 2.0]), AbstractMapsTestCamera(nb))
            # Arrays and tuples of different types holding NaN compare by their elements
            @test SMLMCore.is_same_camera(AbstractMapsTestCamera([NaN, 2.0]), AbstractMapsTestCamera(Float32[NaN32, 2]))
            big = fill(9.0, 3, 3); big[1:2, 1:2] = [NaN 1.0; 2.0 -0.0]
            @test SMLMCore.is_same_camera(AbstractMapsTestCamera([NaN 1.0; 2.0 0.0]), AbstractMapsTestCamera(view(big, 1:2, 1:2)))
            @test !SMLMCore.is_same_camera(AbstractMapsTestCamera([NaN 1.0; 2.0 0.5]), AbstractMapsTestCamera(view(big, 1:2, 1:2)))
            @test SMLMCore.is_same_camera(TupleTestCamera((NaN, 1)), TupleTestCamera((NaN32, 1.0)))
            @test !SMLMCore.is_same_camera(TupleTestCamera((NaN, 1)), TupleTestCamera((NaN, 2)))

            # A camera in a cycle (it lists itself) compares without overflowing the stack
            @test SMLMCore.is_same_camera(self_listing_camera(), self_listing_camera())
            s_l1 = BasicSMLD(em, self_listing_camera(), 1, 1, Dict{String,Any}())
            s_l2 = BasicSMLD(em, self_listing_camera(), 1, 1, Dict{String,Any}())
            @test length(cat_smld(s_l1, s_l2).emitters) == 2
            @test length(merge_smld(s_l1, s_l2; adjust_frames=true).emitters) == 2
            # A list met again beside a different list is compared, not taken as a revisit
            ca = self_listing_camera(); push!(ca.cameras, ca)
            cb = self_listing_camera(); push!(cb.cameras, ListingTestCamera([0.0, 0.1], [0.0, 0.1], Any[1.0]))
            @test !SMLMCore.is_same_camera(ca, cb)
            @test SMLMCore.is_same_camera(SelfTestCamera([0.0, 0.1]), SelfTestCamera([0.0, 0.1]))
            @test !SMLMCore.is_same_camera(SelfTestCamera([0.0, 0.1]), SelfTestCamera([0.0, 0.2]))

            # A mutable object without == (an instrument handle) matches only itself
            inst = TestInstrument("A")
            @test SMLMCore.is_same_camera(InstrumentTestCamera(e2, e2, inst), InstrumentTestCamera(copy(e2), copy(e2), inst))
            @test !SMLMCore.is_same_camera(InstrumentTestCamera(e2, e2, inst), InstrumentTestCamera(e2, e2, TestInstrument("A")))

            # A field whose == returns missing is compared by its fields
            @test SMLMCore.is_same_camera(MissingEqTestCamera(MissingEqSetting([1.0])), MissingEqTestCamera(MissingEqSetting([1.0])))
            @test !SMLMCore.is_same_camera(MissingEqTestCamera(MissingEqSetting([1.0])), MissingEqTestCamera(MissingEqSetting([2.0])))
        end

        @testset "Metadata Handling" begin
            smld1 = create_test_smld(1:2)
            smld1.metadata["key1"] = "value1"
            
            smld2 = create_test_smld(3:4)
            smld2.metadata["key2"] = "value2"
            
            result = cat_smld(smld1, smld2)
            @test haskey(result.metadata, "key1")
            @test haskey(result.metadata, "concatenated_from")
            @test result.metadata["concatenated_from"] == 2
        end

        @testset "Empty and Single SMLD" begin
            # Test concatenating empty vector of SMLDs
            @test_throws ErrorException cat_smld(SMLD[])
            
            # Create a test SMLD
            cam = IdealCamera(1:512, 1:512, 0.1)
            emitters = [
                Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0, frame=1)
            ]
            smld = BasicSMLD(emitters, cam, 1, 1, Dict{String,Any}())
            
            # Test single SMLD
            result = cat_smld([smld])
            @test length(result.emitters) == 1
            
            # Test concatenation with empty emitters but valid SMLD
            empty_emitters = Emitter2DFit{Float64}[]
            empty_smld = BasicSMLD(empty_emitters, cam, 0, 1, Dict{String,Any}())
            result = cat_smld([smld, empty_smld])
            @test length(result.emitters) == 1

            # Varargs form with an empty SMLD
            smld2 = create_test_smld(1:2)
            result = cat_smld(smld2, empty_smld)
            @test length(result.emitters) == 2
            @test result.n_frames == 2
        end
    end

    @testset "merge_smld" begin
        @testset "Basic Merging" begin
            smld1 = create_test_smld(1:2, 1)
            smld2 = create_test_smld(1:2, 2)
            
            # Test without adjustments
            result = merge_smld(smld1, smld2)
            @test length(result.emitters) == 4
            @test result.n_frames == 2
            @test result.n_datasets == 2
            
            # Test with frame adjustment
            result = merge_smld(smld1, smld2, adjust_frames=true)
            @test result.n_frames == 4
            @test result.emitters[3].frame == 3  # Should be adjusted
            
            # Test with dataset adjustment. smld2 declares 2 datasets (its emitters are in
            # dataset 2), so it moves by smld1's 1 dataset: datasets 1 and 3 of 3.
            result = merge_smld(smld1, smld2, adjust_datasets=true)
            @test result.n_datasets == 3
            @test sort(unique(e.dataset for e in result.emitters)) == [1, 3]
        end

        @testset "Renumbering by Running Totals, Inputs Unchanged" begin
            cam = IdealCamera(1:512, 1:512, 0.1)
            mk(fd, nf, nd) = BasicSMLD(
                [Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0,
                    frame=f, dataset=d, id=i) for (i, (f, d)) in enumerate(fd)],
                cam, nf, nd, Dict{String,Any}())
            numbers(s) = [(e.frame, e.dataset) for e in s.emitters]
            a = mk([(1, 1), (10, 2)], 10, 2)            # 2 datasets of 10 frames
            b = mk([(1, 1), (5, 2), (5, 3)], 5, 3)      # 3 datasets of 5 frames
            c = mk([(2, 1)], 4, 1)
            a0, b0, c0 = numbers(a), numbers(b), numbers(c)

            m = merge_smld([a, b, c]; adjust_frames=true, adjust_datasets=true)
            @test numbers(m) == [(1, 1), (10, 2),
                (11, 3), (15, 4), (15, 5),              # b: frames + 10, datasets + 2
                (17, 6)]                                # c: frames + 15, datasets + 5
            @test m.n_frames == 19
            @test m.n_datasets == 6
            @test numbers(a) == a0 && numbers(b) == b0 && numbers(c) == c0

            # Merging again gives the same result and leaves the first result unchanged
            m0 = numbers(m)
            m2 = merge_smld([a, b, c]; adjust_frames=true, adjust_datasets=true)
            @test numbers(m2) == m0
            @test numbers(m) == m0

            # Only one kind of renumbering
            mf = merge_smld(a, b; adjust_frames=true)
            @test numbers(mf) == [(1, 1), (10, 2), (11, 1), (15, 2), (15, 3)]
            @test mf.n_frames == 15 && mf.n_datasets == 3
            md = merge_smld(a, b; adjust_datasets=true)
            @test numbers(md) == [(1, 1), (10, 2), (1, 3), (5, 4), (5, 5)]
            @test md.n_frames == 10 && md.n_datasets == 5
            @test numbers(a) == a0 && numbers(b) == b0

            # Without renumbering nothing is copied or changed
            mn = merge_smld(a, b)
            @test numbers(mn) == [a0; b0]
            @test mn.n_frames == 10 && mn.n_datasets == 3

            # A later input that lists one emitter object several times: each entry moves once
            s = mk([(1, 1), (2, 1)], 2, 1)
            twice = cat_smld(s, s)                       # entries 1 and 3 are one object
            @test twice.emitters[1] === twice.emitters[3]
            m = merge_smld(a, twice; adjust_frames=true, adjust_datasets=true)
            @test numbers(m)[3:end] == [(11, 3), (12, 3), (11, 3), (12, 3)]
            @test m.emitters[3] !== m.emitters[5]
            boot = BasicSMLD(s.emitters[[1, 1, 2]], cam, 2, 1, Dict{String,Any}())
            m = merge_smld(a, boot; adjust_datasets=true)
            @test [e.dataset for e in m.emitters[3:end]] == [3, 3, 3]
            @test m.n_datasets == 3
            @test numbers(s) == [(1, 1), (2, 1)]
        end

        @testset "Renumbering Other Emitter Types" begin
            cam = IdealCamera(1:16, 1:16, 0.1)
            mk_int(nf) = BasicSMLD([Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0,
                frame=1)], cam, nf, 1, Dict{String,Any}())
            sm(v, nf) = BasicSMLD(v, cam, nf, 1, Dict{String,Any}())
            # Each case is its own testset, so an error in one does not skip the others
            @testset "Immutable emitters, Int32 numbers" begin
                mkimm(fd, nf, nd) = BasicSMLD([ImmutableTestEmitter(1.0, 2.0, f, d) for (f, d) in fd],
                    cam, nf, nd, Dict{String,Any}())
                m = merge_smld(mkimm([(1, 1)], 5, 2), mkimm([(1, 1), (3, 2)], 5, 2);
                    adjust_frames=true, adjust_datasets=true)
                @test [(e.frame, e.dataset) for e in m.emitters] == [(1, 1), (6, 3), (8, 4)]
                @test eltype(m.emitters) == ImmutableTestEmitter
            end
            @testset "Numbers as properties only" begin
                # copied, then set through the properties
                p1 = BasicSMLD([PropertyTestEmitter(1.0, 2.0, 1, 1)], cam, 4, 1, Dict{String,Any}())
                p2 = BasicSMLD([PropertyTestEmitter(1.0, 2.0, 2, 1)], cam, 4, 1, Dict{String,Any}())
                m = merge_smld(p1, p2; adjust_frames=true, adjust_datasets=true)
                @test [(e.frame, e.dataset) for e in m.emitters] == [(1, 1), (6, 2)]
                @test (p2.emitters[1].frame, p2.emitters[1].dataset) == (2, 1)
            end

            @testset "Only the requested numbers are read or written" begin
                m = merge_smld(sm([FrameOnlyMutable(1.0, 1)], 10), sm([FrameOnlyMutable(1.0, 2)], 10); adjust_frames=true)
                @test [e.frame for e in m.emitters] == [1, 12]
                m = merge_smld(sm([FrameOnlyImmutable(1.0, 1)], 10), sm([FrameOnlyImmutable(1.0, 2)], 10); adjust_frames=true)
                @test [e.frame for e in m.emitters] == [1, 12]
                @test_throws ArgumentError merge_smld(sm([FrameOnlyImmutable(1.0, 1)], 10),
                    sm([FrameOnlyImmutable(1.0, 2)], 10); adjust_datasets=true)
                m = merge_smld(sm([MaybeDatasetEmitter(1, nothing)], 10), sm([MaybeDatasetEmitter(2, nothing)], 10);
                    adjust_frames=true)
                @test [(e.frame, e.dataset) for e in m.emitters] == [(1, nothing), (12, nothing)]
            end

            @testset "A type's own setter runs" begin
                # so a derived field stays in step
                t2 = TimedTestEmitter(2, 1, 0.02)
                m = merge_smld(sm([TimedTestEmitter(1, 1, 0.01)], 10), sm([t2], 10); adjust_frames=true)
                @test (m.emitters[2].frame, m.emitters[2].t) == (12, 0.12)
                @test (t2.frame, t2.t) == (2, 0.02)
            end

            @testset "Mutable emitter with a field left undefined" begin
                # copied by deepcopy; a defined object field stays shared
                m = merge_smld(sm([ExtraTestEmitter(1, 1)], 10), sm([ExtraTestEmitter(2, 1)], 10); adjust_frames=true)
                @test m.emitters[2].frame == 12 && !isdefined(m.emitters[2], :extra)
                v = [1.0]
                in2 = ExtraTestEmitter(2, 1, v)
                m = merge_smld(sm([ExtraTestEmitter(1, 1, [0.0])], 10), sm([in2], 10); adjust_frames=true)
                @test m.emitters[2].frame == 12 && m.emitters[2].extra === v && in2.frame == 2
            end

            @testset "Input vector of abstract element type" begin
                ab = AbstractSMLD[mk_int(10), mk_int(10)]
                @test [e.frame for e in merge_smld(ab; adjust_frames=true).emitters] == [1, 11]
            end

            @testset "Immutable emitter, number with no move not read" begin
                # dataset = nothing
                im1 = sm([ImmutableMaybeDataset(1, nothing)], 10)
                m = merge_smld(im1, sm([ImmutableMaybeDataset(2, nothing)], 10); adjust_frames=true)
                @test [(e.frame, e.dataset) for e in m.emitters] == [(1, nothing), (12, nothing)]
            end

            @testset "Immutable emitter with fields left unset" begin
                # a trailing field left unset stays unset; one that is set stays shared with the input
                m = merge_smld(sm([ImmutableExtraEmitter(1, 1)], 10), sm([ImmutableExtraEmitter(2, 1)], 10);
                    adjust_frames=true, adjust_datasets=true)
                @test (m.emitters[2].frame, m.emitters[2].dataset) == (12, 2)
                @test !isdefined(m.emitters[2], :extra)
                v = [1.0]
                m = merge_smld(sm([ImmutableExtraEmitter(1, 1, [0.0])], 10), sm([ImmutableExtraEmitter(2, 1, v)], 10);
                    adjust_frames=true)
                @test m.emitters[2].frame == 12 && m.emitters[2].extra === v
                # A move of a number the emitter leaves unset throws; a set one moves
                @test_throws ArgumentError merge_smld(sm([LateNumbersEmitter([0.0], 1, 1)], 10),
                    sm([LateNumbersEmitter()], 10); adjust_frames=true)
                @test_throws ArgumentError merge_smld(sm([LateNumbersEmitter([0.0], 1, 1)], 10),
                    sm([LateNumbersEmitter()], 10); adjust_datasets=true)
                m = merge_smld(sm([LateNumbersEmitter([0.0], 1, 1)], 10), sm([LateNumbersEmitter([0.0], 2, 1)], 10);
                    adjust_frames=true, adjust_datasets=true)
                @test (m.emitters[2].frame, m.emitters[2].dataset) == (12, 2)
            end

            @testset "SMLD counts of type $C, three inputs" for C in (Int32, UInt)
                sc(f) = CountTestSMLD([Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0,
                    frame=f)], cam, C(10), C(1), Dict{String,Any}())
                m = merge_smld(sc(1), sc(2), sc(3); adjust_frames=true, adjust_datasets=true)
                @test [(e.frame, e.dataset) for e in m.emitters] == [(1, 1), (12, 2), (23, 3)]
                @test (m.n_frames, m.n_datasets) == (30, 3)
                @test m.n_frames isa C
            end
        end

        @testset "Metadata Handling" begin
            smld1 = create_test_smld(1:2)
            smld2 = create_test_smld(3:4)
            
            smld1.metadata["unique1"] = "value1"
            smld2.metadata["unique2"] = "value2"
            
            result = merge_smld(smld1, smld2)
            @test haskey(result.metadata, "unique1")
            @test haskey(result.metadata, "merged_from")
            @test haskey(result.metadata, "frame_adjustment")
            @test result.metadata["merged_from"] == 2
        end

        @testset "Error Cases" begin
            smld1 = create_test_smld(1:2)
            # Create SMLD with different camera
            cam2 = IdealCamera(1:256, 1:256, 0.1)
            emitters2 = [
                Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0)
            ]
            smld2 = BasicSMLD(emitters2, cam2, 1, 1, Dict{String,Any}())
            
            # Should error on different cameras
            @test_throws ErrorException merge_smld(smld1, smld2)

            # Test empty input
            @test_throws ErrorException merge_smld(SMLD[])
        end
    end

    @testset "One input gives a new SMLD with the usual metadata" begin
        s = create_test_smld(1:3)
        s.metadata["sample"] = "A"
        keys_before = sort(collect(keys(s.metadata)))

        for c in (cat_smld([s]), cat_smld(s))
            @test c !== s
            @test c isa typeof(s)
            @test c.emitters == s.emitters && c.emitters !== s.emitters
            @test c.camera === s.camera
            @test (c.n_frames, c.n_datasets) == (s.n_frames, s.n_datasets)
            @test c.metadata["concatenated_from"] == 1
            @test c.metadata["sample"] == "A"
        end

        for m in (merge_smld([s]), merge_smld(s))
            @test m !== s
            @test m.emitters == s.emitters && m.emitters !== s.emitters
            @test m.metadata["merged_from"] == 1
            @test m.metadata["frame_adjustment"] == false
            @test m.metadata["dataset_adjustment"] == false
        end
        m = merge_smld([s]; adjust_frames = true, adjust_datasets = true)
        @test m !== s
        @test m.metadata["frame_adjustment"] == true
        @test m.metadata["dataset_adjustment"] == true
        @test (m.n_frames, m.n_datasets) == (s.n_frames, s.n_datasets)
        @test [e.frame for e in m.emitters] == [e.frame for e in s.emitters]

        # The input is unchanged: no metadata key added, and growing the result's emitter
        # vector does not grow the input's
        @test sort(collect(keys(s.metadata))) == keys_before
        c = cat_smld([s])
        push!(c.emitters, Emitter2DFit{Float64}(9.0, 9.0, 1.0, 1.0, 0.1, 0.1, 1.0, 1.0))
        @test length(s.emitters) == 3
    end
end
