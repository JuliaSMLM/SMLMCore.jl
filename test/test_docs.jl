using SMLMCore, Test

# Docs.hasdoc is Julia 1.11+; a docstring is an entry for the name's binding in its module's docs.
_hasdoc(m, s) = (b = Base.Docs.Binding(m, s); haskey(Base.Docs.meta(b.mod), b))

@testset "every exported name has a docstring" begin
    # ?name and the @autodocs API page need each exported name's docstring attached to it.
    undocumented = [n for n in names(SMLMCore) if n !== :SMLMCore && !_hasdoc(SMLMCore, n)]
    @test undocumented == Symbol[]
end

@testset "README's quick start is Home's, and it runs" begin
    # The style guide asks for the same quick start on both pages; the docs build runs Home's.
    root = dirname(@__DIR__)
    quickstart(file, fence) = (m = match(
        Regex("## Quick start\\n\\n" * fence * "\\n(.*?)\\n```", "s"),
        read(joinpath(root, file), String)); m === nothing ? nothing : m[1])
    readme = quickstart("README.md", "```julia")
    home = quickstart(joinpath("docs", "src", "index.md"), "```@example quickstart")
    @test readme isa AbstractString
    @test readme == home
    m = Module()
    Base.include_string(m, readme)
    @test length(m.bright) == 1 && m.bright.emitters[1].photons == 1200.0
    @test length(m.region) == 1 && m.region.emitters[1].x == 1.0
end

@testset "Home and api_overview.md give the same install and ecosystem text" begin
    # Home holds the full "Where it fits" and "Installation" text, api_overview.md a copy of
    # each, and the README a short form of the install limit.
    root = dirname(@__DIR__)
    section(text, name) = (m = match(Regex("## " * name * "\\n\\n(.*?)\\n(?=## )", "s"), text);
        m === nothing ? nothing : m[1])
    home = read(joinpath(root, "docs", "src", "index.md"), String)
    overview = read(joinpath(root, "api_overview.md"), String)
    for name in ("Where it fits", "Installation")
        @test section(home, name) isa AbstractString
        @test section(home, name) == section(overview, name)
    end
    @test occursin("SMLMData 0.7.1 or earlier", section(home, "Installation"))
    readme = read(joinpath(root, "README.md"), String)
    @test occursin("SMLMData 0.7.1 or earlier", section(readme, "Installation"))
end

const OVERVIEW = read(joinpath(dirname(@__DIR__), "api_overview.md"), String)
const JULIA_BLOCK = r"```julia\n(.*?)\n```"s
# The one hand-written listing of the types: the first julia block after its heading
const LISTING = match(JULIA_BLOCK, split(OVERVIEW, "## Type Definitions"; limit = 2)[end])[1]

@testset "api_overview.md: the type listing matches the code" begin
    sandbox = Module()
    Core.eval(sandbox, :(using SMLMCore: AbstractEmitter, AbstractCamera, AbstractSMLD))
    Core.eval(sandbox, :(using StaticArrays: SVector))
    Base.include_string(sandbox, LISTING, "api_overview.md listing")

    istype(m, n) = isdefined(m, n) && getfield(m, n) isa Type
    listed = Set(n for n in names(sandbox; all = true)
        if istype(sandbox, n) && parentmodule(getfield(sandbox, n)) === sandbox)
    # Every exported concrete type is listed, and nothing else
    structs = Set(n for n in names(SMLMCore)
        if istype(SMLMCore, n) && isstructtype(Base.unwrap_unionall(getfield(SMLMCore, n))))
    @test listed == structs

    # Type parameters used to compare field types
    params = Dict(
        :Emitter2D => (Float64,), :Emitter3D => (Float64,),
        :Emitter2DFit => (Float64,), :Emitter3DFit => (Float64,),
        :IdealCamera => (Float64,), :SCMOSCamera => (Float64,), :SingleROI => (Float32,),
        :ROIBatch => (Float32, 3, Array{Float32,3}, IdealCamera{Float64}),
        :BasicSMLD => (Float64, Emitter2DFit{Float64}),
    )
    typevars(T) = T isa UnionAll ? TypeVar[T.var; typevars(T.body)] : TypeVar[]
    for n in sort!(collect(structs))
        @testset "$n" begin
            doc, code = getfield(sandbox, n), getfield(SMLMCore, n)
            @test ismutabletype(Base.unwrap_unionall(doc)) == ismutabletype(Base.unwrap_unionall(code))
            @test supertype(doc) == supertype(code)
            @test fieldnames(doc) == fieldnames(code)
            @test fieldtypes(doc{params[n]...}) == fieldtypes(code{params[n]...})
            tv_doc, tv_code = typevars(doc), typevars(code)
            @test length(tv_doc) == length(tv_code)
            for (a, b) in zip(tv_doc, tv_code)
                # A bound that refers to another parameter (A<:AbstractArray{T,N}) is covered
                # by the field types above.
                Base.has_free_typevars(b.ub) || @test a.ub == b.ub
            end
        end
    end
end

@testset "api_overview.md: every example runs" begin
    # Blocks run in order in one module, as a reader would. Skipped: the type listing, and
    # blocks that load another package (GaussMLE, CUDA).
    other_package(b) = any(m -> m[1] != "SMLMCore",
        eachmatch(r"^\s*(?:using|import)\s+([A-Za-z_]\w*)"m, b))
    blocks = [m[1] for m in eachmatch(JULIA_BLOCK, OVERVIEW)]
    runnable = [b for b in blocks if b != LISTING && !other_package(b)]
    @test length(runnable) >= 10
    m = Module()
    for (i, b) in enumerate(runnable)
        ran = try
            redirect_stdout(() -> Base.include_string(m, b, "api_overview.md block $i"), devnull)
            true
        catch err
            @error "api_overview.md: runnable block $i failed" exception = err
            false
        end
        @test ran
    end
end

@testset "api_overview.md is a precompile dependency" begin
    # api.jl reads api_overview.md at precompile time; unless the file is listed among the
    # cache's dependencies, editing it leaves `SMLMCore.api_overview()` stale.
    origin = get(Base.pkgorigins, Base.PkgId(SMLMCore), nothing)
    cachepath = origin === nothing ? nothing : origin.cachepath
    if cachepath === nothing
        @test_skip "SMLMCore was loaded without a precompile cache"
    else
        # Julia 1.10 lists (filename, mtime) pairs, later versions file names
        deps = Base.cache_dependencies(cachepath)[2]
        files = [d isa AbstractString ? d : first(d) for d in deps]
        @test any(f -> basename(f) == "api_overview.md", files)
    end
end
