# SMLMCore.jl

SMLMCore defines the data types of single molecule localization microscopy (SMLM) in Julia:
emitters (localizations), cameras, ROI batches and SMLD containers. It converts between pixel
coordinates and positions, selects emitters by property, region or frame, and combines data sets.

!!! info "Units"
    Lengths (positions, pixel sizes and edges, position uncertainties) are in µm, intensities in
    photons, and backgrounds in photons per pixel. sCMOS calibration uses the units of a camera's
    specification sheet: offset in ADU, gain in e⁻/ADU, read noise in e⁻ rms. Frames, datasets
    and pixels are numbered from 1. [Conventions](guide/conventions.md) has the details.

## Where it fits

SMLMCore holds the types that the JuliaSMLM packages share. Analysis packages such as GaussMLE,
SMLMBoxer and SMLMAnalysis depend on SMLMData, which from 0.7.2 loads SMLMCore and re-exports its
names, so their users get SMLMCore's types without loading it. GaussMLE re-exports `ROIBatch`,
`SingleROI`, `IdealCamera`, `SCMOSCamera` and `@filter`, SMLMBoxer re-exports `ROIBatch` and
`SingleROI`, and SMLMAnalysis re-exports `IdealCamera` and `SCMOSCamera`. A package that needs
only the types depends on SMLMCore directly. File reading and writing (SMITE `.mat`) is in
[SMLMio](https://github.com/JuliaSMLM/SMLMio.jl).

## Installation

```julia
using Pkg
Pkg.add("SMLMCore")
```

SMLMCore cannot share an environment with SMLMData 0.7.1 or earlier, which defines the same
types; its compat on SMLMData (a weak dependency) is `>= 0.7.2`. Until SMLMData 0.7.2 is
released, use SMLMCore in an environment without SMLMData, GaussMLE, SMLMBoxer or SMLMAnalysis.

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
