# API

Every exported name, grouped by task. `SMLMCore.api_overview()` returns a plain-text overview
of the whole API.

## The package

```@docs
SMLMCore
```

## Emitters

```@docs
AbstractEmitter
Emitter2D
Emitter3D
Emitter2DFit
Emitter3DFit
emitter_ndims
```

## Cameras

```@docs
AbstractCamera
IdealCamera
SCMOSCamera
compute_bin_edges
get_pixel_centers
```

## ROI batches

```@docs
SingleROI
ROIBatch
```

## SMLD containers

```@docs
AbstractSMLD
SMLD
BasicSMLD
```

## Coordinates

```@docs
pixel_to_physical
physical_to_pixel
physical_to_pixel_index
```

## Filtering

```@docs
@filter
filter_frames
filter_roi
```

## Combining

```@docs
cat_smld
merge_smld
```

## Ecosystem abstract types

```@docs
AbstractSMLMConfig
AbstractSMLMInfo
```

## Index

```@index
Pages = ["api.md"]
```
