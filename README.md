# SMLMCore

SMLMCore defines the data types of single molecule localization microscopy (SMLM) in Julia:
emitters (localizations), cameras, ROI batches and SMLD containers, with coordinate conversions,
filters, and functions that combine data sets. Lengths are in µm.

[![CI](https://github.com/JuliaSMLM/SMLMCore.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaSMLM/SMLMCore.jl/actions/workflows/CI.yml)
[![Docs: stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSMLM.github.io/SMLMCore.jl/stable)

## Installation

```julia
using Pkg
Pkg.add("SMLMCore")
```

An environment that holds SMLMData 0.7.1 or earlier, directly or through a package that depends
on it, cannot add SMLMCore; see
[Installation](https://JuliaSMLM.github.io/SMLMCore.jl/stable/#Installation).

## Quick start

```julia
using SMLMCore

cam = IdealCamera(512, 512, 0.1)   # 512 × 512 pixels of 0.1 µm

emitters = [
    Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0),
    Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.02, 0.02, 60.0, 2.0),
]
smld = BasicSMLD(emitters, cam, 1, 1)   # 1 frame, 1 dataset

bright = @filter(smld, photons > 1100)              # the second emitter
region = filter_roi(smld, (0.0, 2.0), (1.0, 3.0))   # x and y bounds in µm: the first
```

## Where it fits

SMLMCore holds the types that the JuliaSMLM packages share; SMLMData 0.7.2 and later load it and
re-export its names. File reading and writing (SMITE `.mat`) is in
[SMLMio](https://github.com/JuliaSMLM/SMLMio.jl). The documentation's
[Where it fits](https://JuliaSMLM.github.io/SMLMCore.jl/stable/#Where-it-fits) says which
packages re-export which names.

## Documentation

The [documentation](https://JuliaSMLM.github.io/SMLMCore.jl/stable) has a tutorial, the
conventions (units, pixel coordinates, array order, ROIs and sCMOS calibration), and the API.

## License

MIT; see [LICENSE](LICENSE).
