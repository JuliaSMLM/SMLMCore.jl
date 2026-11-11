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
