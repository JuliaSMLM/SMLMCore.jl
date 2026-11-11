# SMLMCore.jl

SMLMCore defines the data types of single molecule localization microscopy (SMLM) in Julia:
emitters (localizations), cameras, ROI batches and SMLD containers. It converts between pixel
coordinates and positions, selects emitters by property, region or frame, and combines data sets.

!!! info "Units"
    Lengths (positions, pixel sizes and edges, position uncertainties) are in µm. In an
    `Emitter2D` or `Emitter3D`, `photons` counts photons, before QE; fitted `photons` and `bg` are
    in the units of the data the fitter received. sCMOS calibration uses the units of a camera's
    specification sheet: offset in ADU, gain in e⁻/ADU, read noise in e⁻ rms. Frames, datasets
    and pixels are numbered from 1. [Conventions](guide/conventions.md) has the details.

## Where it fits

SMLMCore holds the types that the JuliaSMLM packages share. SMLMData 0.7.2 and later load
SMLMCore and re-export its names, so packages that depend on those versions of SMLMData, and
their users, get SMLMCore's types without loading it. GaussMLE re-exports `ROIBatch`,
`SingleROI`, `IdealCamera`, `SCMOSCamera` and `@filter`, SMLMBoxer re-exports `ROIBatch` and
`SingleROI`, and SMLMAnalysis re-exports `IdealCamera` and `SCMOSCamera`. A package that needs
only the types depends on SMLMCore directly. File reading and writing (SMITE `.mat`) is in
[SMLMio](https://github.com/JuliaSMLM/SMLMio.jl).

## Installation

```julia
using Pkg
Pkg.add("SMLMCore")
```

An environment that holds SMLMData 0.7.1 or earlier, directly or through a package that depends
on it (GaussMLE, SMLMSim, SMLMBoxer, SMLMAnalysis and others), cannot add SMLMCore, because
those versions define the same types: Pkg reports unsatisfiable requirements for SMLMData.

## Quick start

```@example quickstart
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

```@example quickstart
bright.emitters, region.emitters
```

## Next

- [Tutorial](tutorial.md): one worked example, from a camera and emitters to merged data sets,
  pixel coordinates and an ROI batch.
- [Conventions](guide/conventions.md): units, pixel coordinates, array order, ROIs, sCMOS
  calibration and emitter uncertainties.
- [API](api.md): every exported name, grouped by task.
