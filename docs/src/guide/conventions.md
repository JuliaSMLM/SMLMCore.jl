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
| `photons`, `σ_photons` | photons |
| `bg`, `σ_bg` | photons per pixel |
| sCMOS `offset` | ADU |
| sCMOS `gain` | e⁻/ADU |
| sCMOS `readnoise` | e⁻ rms |
| sCMOS `qe` | 0 to 1 |
| ROI data | the camera's raw units (ADU for an [`SCMOSCamera`](@ref)) |
| ROI sizes and corners, pixel indices | pixels |

`photons` is the number of photons from the emitter that reach the camera in the frame, before
QE.

`pixel_size` is the size of a pixel at the sample: the sensor pixel divided by the
magnification. A 6.5 µm sensor pixel behind a 100× objective is 0.065 µm.

## Pixels and coordinates

- The origin, `(0, 0)` µm, is the top-left corner of the camera. x increases to the right, along
  the columns; y increases downward, along the rows.
- Pixel `(i, j)` is column `i` and row `j`, both numbered from 1, so `(1, 1)` is the top-left
  pixel.
- A camera stores its pixel edges, `pixel_edges_x` and `pixel_edges_y`: `N + 1` edges per axis
  for `N` pixels, increasing from 0. With uniform pixels of `Δx` × `Δy`, pixel `(i, j)` covers
  `[(i - 1)·Δx, i·Δx) × [(j - 1)·Δy, j·Δy)` and its center is at `((i - 0.5)·Δx, (j - 0.5)·Δy)`.
  In pixel coordinates the center of pixel `(i, j)` is `(i, j)`, and the camera's corner is
  `(0.5, 0.5)`.
- A position on a pixel edge belongs to the pixel that starts there, so `(0, 0)` µm is in pixel
  `(1, 1)` ([`physical_to_pixel_index`](@ref)).
- [`pixel_to_physical`](@ref), [`physical_to_pixel`](@ref) and
  [`physical_to_pixel_index`](@ref) take one scalar pixel size: they hold for square pixels with
  the edges starting at 0. For rectangular pixels or a camera with its own edges, use
  [`get_pixel_centers`](@ref) and the camera's edges. None of them checks that a position lies
  inside the camera.

## Array order

Images and every per-pixel array are indexed `[row, column] = [y, x]`, the order of a camera
frame in Julia:

- An sCMOS calibration map has size `(ny, nx)`, and `map[j, i]` belongs to pixel (column `i`,
  row `j`). A map of the wrong size throws a `DimensionMismatch`, but a square sensor's map
  cannot be checked for orientation: a transposed map is accepted silently.
- ROI data are indexed `[y, x]` ([`SingleROI`](@ref)) and `[y, x, roi]` ([`ROIBatch`](@ref)).

## ROIs

- An ROI is a square of `roi_size` × `roi_size` pixels cut from one camera frame.
- Its corner is the camera pixel `(x, y) = (column, row)` of its top-left pixel, numbered from 1:
  `corner` in a [`SingleROI`](@ref), `x_corners[k]` and `y_corners[k]` in an [`ROIBatch`](@ref).
- Inside the ROI, `(1, 1)` is the top-left pixel. ROI pixel `data[i, j, k]` is camera pixel
  (column `x_corners[k] + j - 1`, row `y_corners[k] + i - 1`). For uniform pixels of `Δx` × `Δy`
  its center is at `((x_corners[k] + j - 1.5)·Δx, (y_corners[k] + i - 1.5)·Δy)` µm.
- ROI data are in the camera's raw units: ADU for an [`SCMOSCamera`](@ref), which a fitter
  converts to electrons with the `offset` and `gain` of the camera pixels under the ROI. That
  conversion relies on the map order above and on the corner convention.

## sCMOS calibration

An [`SCMOSCamera`](@ref) describes how the photons that reach a pixel become its reading:

```
photons reaching the pixel   N
photoelectrons               N × qe
plus read noise              N × qe + ε,  where ε ~ Normal(0, readnoise²)
reading (ADU)                (N × qe + ε) / gain + offset
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
