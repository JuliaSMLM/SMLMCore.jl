# Tutorial

This tutorial builds two small localization data sets from constructed values, selects
emitters from them, merges them, converts between positions and pixels, and cuts an ROI batch
from an image. Every block runs as written with only SMLMCore loaded.

## A camera

A camera gives the pixel geometry. Here: 128 × 128 pixels of 0.1 µm at the sample (a 10 µm
sensor pixel behind a 100× objective), so the field of view is 12.8 µm across.

```@example tutorial
using SMLMCore

cam = IdealCamera(128, 128, 0.1)
```

Positions are in µm with `(0, 0)` at the camera's top-left corner; x runs along the columns and
y down the rows ([Conventions](guide/conventions.md)).

## Emitters and an SMLD

Each localization is an [`Emitter2DFit`](@ref): position (µm), fitted signal and background
per pixel (in the units of the data the fitter received; photons here), their standard
deviations, and the frame and dataset it belongs to. These two acquisitions of the same field
each have three frames; the second is shifted by 0.05 µm in x.

```@example tutorial
#               x      y     photons σ (µm) frame
const SPOTS = [(1.04,  2.02, 1500.0, 0.010, 1),
               (3.24,  4.16,  800.0, 0.025, 1),
               (5.53,  1.34, 2000.0, 0.008, 2),
               (7.42,  9.95,  600.0, 0.030, 3),
               (10.13, 6.68, 1200.0, 0.012, 3)]

acquisition(shift) = [
    Emitter2DFit{Float64}(x + shift, y, photons, 10.0, σ, σ, sqrt(photons), 1.0; frame = f)
    for (x, y, photons, σ, f) in SPOTS
]

a = BasicSMLD(acquisition(0.0), cam, 3, 1)    # 3 frames, 1 dataset
b = BasicSMLD(acquisition(0.05), cam, 3, 1)
a
```

## Selecting emitters

[`@filter`](@ref) keeps the emitters for which a condition on their properties holds:

```@example tutorial
precise = @filter(a, σ_x < 0.02 && photons > 1000)
[(e.x, e.y) for e in precise.emitters]
```

A condition holds only property names, number literals and tuples. A threshold held in a
variable is read as a property, so filter the emitter vector directly instead:

```@example tutorial
threshold = 1000.0
kept = filter(e -> e.photons > threshold, a.emitters)
bright = BasicSMLD(kept, a.camera, a.n_frames, a.n_datasets, copy(a.metadata))
length(bright)
```

[`filter_frames`](@ref) selects frames, and [`filter_roi`](@ref) a region, with inclusive
bounds in µm:

```@example tutorial
early = filter_frames(a, 1:2)
[e.frame for e in early.emitters]
```

```@example tutorial
region = filter_roi(a, (0.0, 6.0), (0.0, 5.0))
[(e.x, e.y) for e in region.emitters]
```

Each result is a new SMLD, but its emitters are the input's own objects: changing a field of
`region.emitters[1]` changes `a.emitters[1]` too. `deepcopy` a result before changing its
emitters.

## Merging data sets

[`merge_smld`](@ref) combines SMLDs from the same camera. With `adjust_frames` and
`adjust_datasets`, the second input's frames follow the first's, and each input keeps its own
dataset number:

```@example tutorial
both = merge_smld(a, b; adjust_frames = true, adjust_datasets = true)
[(e.frame, e.dataset) for e in both.emitters]
```

```@example tutorial
both.n_frames, both.n_datasets, both.metadata
```

The inputs are not changed:

```@example tutorial
[e.frame for e in b.emitters]
```

[`cat_smld`](@ref) concatenates without renumbering.

## Positions and pixels

For square pixels with the camera's edges at 0, [`physical_to_pixel`](@ref) gives pixel
coordinates (column, row), with `(1, 1)` at the center of the top-left pixel, and
[`physical_to_pixel_index`](@ref) the pixel that holds a position:

```@example tutorial
e = a.emitters[2]
physical_to_pixel(e.x, e.y, 0.1), physical_to_pixel_index(e.x, e.y, 0.1)
```

[`pixel_to_physical`](@ref) goes back, and [`get_pixel_centers`](@ref) lists every pixel
center of a camera:

```@example tutorial
centers_x, centers_y = get_pixel_centers(cam)
pixel_to_physical(33, 42, 0.1), (centers_x[33], centers_y[42])
```

## An ROI batch

A fitter takes square ROIs cut from camera frames, as an [`ROIBatch`](@ref). Images are indexed
`[row, column] = [y, x]`, and an ROI's corner is the camera pixel `(column, row)` of its top-left
pixel. This frame has one bright pixel at each emitter of frame 1, and a 7 × 7 ROI is cut
around each:

```@example tutorial
image = zeros(Float32, 128, 128)      # one frame, [y, x]
frame1 = filter_frames(a, 1)
pixels = [physical_to_pixel_index(e.x, e.y, 0.1) for e in frame1.emitters]   # (column, row)
for (col, row) in pixels
    image[row, col] = 100.0f0
end

roi_size = 7
x_corners = [col - roi_size ÷ 2 for (col, row) in pixels]
y_corners = [row - roi_size ÷ 2 for (col, row) in pixels]
data = cat([image[y:y+roi_size-1, x:x+roi_size-1] for (x, y) in zip(x_corners, y_corners)]...;
           dims = 3)                  # [y, x, roi]
batch = ROIBatch(data, x_corners, y_corners, fill(1, length(pixels)), cam)
```

Each bright pixel sits at the center of its ROI, `(row, column) = (4, 4)`:

```@example tutorial
[Tuple(argmax(roi.data)) for roi in batch]
```
