# Conventions

SMLMCore defines the types that the JuliaSMLM packages share, and with them the conventions on
this page: units, pixel coordinates, array order, ROIs, sCMOS calibration, numbering, and
emitter uncertainties.

## Units

| Quantity | Unit |
|:--|:--|
| positions `x`, `y`, `z`; pixel sizes and pixel edges | µm |
| position standard deviations `σ_x`, `σ_y`, `σ_z` | µm |
| position covariances `σ_xy`, `σ_xz`, `σ_yz` | µm² |
| `photons` of an [`Emitter2D`](@ref) or [`Emitter3D`](@ref) | photons |
| fitted `photons` (total in the frame) and `σ_photons` | the fitter's working units: photons, or photoelectrons for sCMOS data (below) |
| fitted `bg` and `σ_bg` | the same units, per pixel |
| sCMOS `offset` | ADU |
| sCMOS `gain` | e⁻/ADU |
| sCMOS `readnoise` | e⁻ rms |
| sCMOS `qe` | 0 to 1 |
| ROI data | the camera's raw units (ADU for an [`SCMOSCamera`](@ref)) |
| ROI sizes and corners, pixel indices | pixels |

Typical sCMOS values: offset 100 to 500 ADU, gain 0.1 to 2 e⁻/ADU depending on the readout mode,
read noise 0.3 to 5 e⁻ rms, QE 0.5 to 0.95.

The `photons` of an [`Emitter2D`](@ref) or [`Emitter3D`](@ref) are the photons from the emitter
that reach the camera in the frame, before QE.

In the fit types ([`Emitter2DFit`](@ref), [`Emitter3DFit`](@ref)), fitted `photons` (the total
in the frame) and `bg` (per pixel) are in the units the fitter works in: photons when the data
are in photons (an [`IdealCamera`](@ref), or an [`SCMOSCamera`](@ref) with `qe = 1`), and
photoelectrons (photons × `qe`) when the fitter converts `SCMOSCamera` ADU with
`(ADU - offset) * gain`, as GaussMLE does. A simulator that fills these types with ground truth,
as SMLMSim does, stores `photons` before QE, as in `Emitter2D`.

`pixel_size` is the size of a pixel at the sample: the sensor pixel divided by the
magnification. A 6.5 µm sensor pixel behind a 100× objective is 0.065 µm.

## Pixels and coordinates

Pixels are labeled `(x, y) = (col, row)`; arrays are indexed `[row, col]`.

- The origin, `(0, 0)` µm, is the top-left corner of the camera. x increases to the right, along
  the columns; y increases downward, along the rows.
- Columns and rows are numbered from 1, so pixel `(1, 1)` is the top-left pixel.
- A camera stores its pixel edges, `pixel_edges_x` and `pixel_edges_y`: `N + 1` edges per axis
  for `N` pixels, increasing from 0. Constructors do not check this; `physical_to_pixel*` and the
  uniform-pixel formulas assume it, and the cameras' displays assume uniform pixels (they report
  the first pixel's width).
- With uniform pixels of `Δx` × `Δy`, pixel `(col, row)` covers
  `[(col - 1)·Δx, col·Δx) × [(row - 1)·Δy, row·Δy)` µm and its center is at
  `((col - 0.5)·Δx, (row - 0.5)·Δy)` µm. In pixel coordinates the center of pixel `(col, row)`
  is `(col, row)`, and the camera's corner is `(0.5, 0.5)`.
- A position on a pixel edge belongs to the pixel that starts there, so `(0, 0)` µm is in pixel
  `(1, 1)` ([`physical_to_pixel_index`](@ref)). This holds up to floating-point rounding: a
  position computed as `(n - 1) * pixel_size` can fall in pixel `n - 1`.
- [`pixel_to_physical`](@ref), [`physical_to_pixel`](@ref) and
  [`physical_to_pixel_index`](@ref) take one scalar pixel size: they hold for square pixels with
  the edges starting at 0. For rectangular pixels or a camera with its own edges, use
  [`get_pixel_centers`](@ref) and the camera's edges. None of them checks that a position lies
  inside the camera.

## Array order

Images and every per-pixel array are indexed `[row, col] = [y, x]`, the order of a camera frame
in Julia:

- An sCMOS calibration map has size `(ny, nx)`, and `map[row, col]` belongs to pixel
  `(x, y) = (col, row)`. A map of the wrong size throws a `DimensionMismatch`, but a square
  sensor's map cannot be checked for orientation: a transposed map is accepted silently.
- ROI data are indexed `[row, col]` ([`SingleROI`](@ref)) and `[row, col, roi]`
  ([`ROIBatch`](@ref)).

## ROIs

- An ROI is a square of `roi_size` × `roi_size` pixels cut from one camera frame.
- Its corner is the camera pixel `(x, y) = (col, row)` of its top-left pixel, numbered from 1:
  `corner` in a [`SingleROI`](@ref), `x_corners[k]` and `y_corners[k]` in an [`ROIBatch`](@ref).
- Inside the ROI, `[1, 1]` is the top-left pixel. ROI pixel `data[row, col, k]` is camera pixel
  `(x, y) = (x_corners[k] + col - 1, y_corners[k] + row - 1)`. For uniform pixels of `Δx` × `Δy`
  its center is at `((x_corners[k] + col - 1.5)·Δx, (y_corners[k] + row - 1.5)·Δy)` µm.
- ROI data are in the camera's raw units: ADU for an [`SCMOSCamera`](@ref), which a fitter
  converts to electrons with the `offset` and `gain` of the camera pixels under the ROI. That
  conversion relies on the map order above and on the corner convention.

## sCMOS calibration

An [`SCMOSCamera`](@ref) describes how the photons that reach a pixel become its reading:

```
photons reaching the pixel   N
photoelectrons               n ~ Poisson(N × qe)
read noise (electrons)       ε ~ Normal(0, readnoise²)
reading (ADU)                (n + ε) / gain + offset
```

Each of `offset`, `gain`, `readnoise` and `qe` is a scalar, the same for every pixel, or a map of
size `(ny, nx)`. Spec-sheet values give scalars; per-pixel calibration gives maps. The defaults,
`offset = 0`, `gain = 1` and `qe = 1`, describe data already in photons. A scalar and a uniform map
of the same value make different cameras: [`cat_smld`](@ref) and [`merge_smld`](@ref) refuse to
combine them.

## Frames, datasets and tracks

- Frame and dataset numbers start at 1. An SMLD's `n_frames` and `n_datasets` count them.
- In the fit types, `track_id = 0` means the localization is not linked into a track, and
  `id = 0` that no identifier is set.

## Emitter uncertainties

`σ_x`, `σ_y` and `σ_z` are standard deviations (µm), and `σ_xy`, `σ_xz` and `σ_yz` are
covariances (µm²). The position covariance of an [`Emitter2DFit`](@ref) is

```math
\Sigma = \begin{pmatrix} \sigma_x^2 & \sigma_{xy} \\ \sigma_{xy} & \sigma_y^2 \end{pmatrix},
```

and of an [`Emitter3DFit`](@ref)

```math
\Sigma = \begin{pmatrix}
\sigma_x^2 & \sigma_{xy} & \sigma_{xz} \\
\sigma_{xy} & \sigma_y^2 & \sigma_{yz} \\
\sigma_{xz} & \sigma_{yz} & \sigma_z^2
\end{pmatrix}.
```

A covariance of 0 means the uncertainty ellipse (or ellipsoid) is aligned with the axes.
