using SMLMCore, Test

# Docs.hasdoc is Julia 1.11+; a docstring is an entry for the name's binding in its module's docs.
_hasdoc(m, s) = (b = Base.Docs.Binding(m, s); haskey(Base.Docs.meta(b.mod), b))

@testset "every exported name has a docstring" begin
    # ?name and the @autodocs API page need each exported name's docstring attached to it.
    undocumented = [n for n in names(SMLMCore) if n !== :SMLMCore && !_hasdoc(SMLMCore, n)]
    @test undocumented == Symbol[]
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
