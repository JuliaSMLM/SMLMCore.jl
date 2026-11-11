using SMLMCore
using Documenter

DocMeta.setdocmeta!(SMLMCore, :DocTestSetup, :(using SMLMCore); recursive=true)

makedocs(;
    modules=[SMLMCore],
    doctest = false, # QA runs every docstring jldoctest (admiral decision 0018)
    checkdocs = :exports, # every export is on the API page; internal docstrings are not
    sitename="SMLMCore.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaSMLM.github.io/SMLMCore.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Tutorial" => "tutorial.md",
        "Guide" => ["Conventions" => "guide/conventions.md"],
        "API" => "api.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaSMLM/SMLMCore.jl",
    devbranch = "main"
)
