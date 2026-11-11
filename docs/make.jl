using SMLMCore
using Documenter

DocMeta.setdocmeta!(SMLMCore, :DocTestSetup, :(using SMLMCore); recursive=true)

makedocs(;
    modules=[SMLMCore],
    doctest = false, # QA runs every docstring jldoctest (admiral decision 0018)
    sitename="SMLMCore.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaSMLM.github.io/SMLMCore.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaSMLM/SMLMCore.jl",
    devbranch = "main" 
)