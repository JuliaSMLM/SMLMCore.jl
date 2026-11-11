# ROI batch types: square image regions cut from camera frames, in the form ROI finders hand to
# fitters across the JuliaSMLM packages.

using StaticArrays: SVector
import Adapt

"""
    SingleROI{T}

One region of interest (ROI): a square image cut from a camera frame, with where and when it was
cut.

# Fields
- `data::Matrix{T}`: the ROI pixels as cut from the camera image, indexed `[row, col] = [y, x]`,
  in the camera's raw units (ADU for an [`SCMOSCamera`](@ref))
- `corner::SVector{2,Int32}`: camera pixel `(x, y) = (column, row)` of the ROI's top-left pixel,
  1-based
- `frame_idx::Int32`: frame number, 1-based

ROI pixel `data[i, j]` is camera pixel (column `corner[1] + j - 1`, row `corner[2] + i - 1`);
see [ROIs](@ref).

# Constructors
- `SingleROI{T}(data, corner, frame_idx)`: converts its arguments, so `corner` can be a tuple
  and `frame_idx` any integer.
- `SingleROI(data::Matrix{T}, corner::SVector{2,Int32}, frame_idx::Int32)`

# Example
```jldoctest
julia> roi = SingleROI{Float32}(zeros(Float32, 11, 11), (100, 200), 5)
SingleROI{Float32}:
  Size: 11 × 11 pixels
  Corner: (100, 200) = (col, row)
  Frame: 5
```
"""
struct SingleROI{T}
    data::Matrix{T}
    corner::SVector{2,Int32}
    frame_idx::Int32
end

# Define eltype for SingleROI
Base.eltype(::Type{SingleROI{T}}) where {T} = T
Base.eltype(::SingleROI{T}) where {T} = T

"""
    ROIBatch{T,N,A,C}

A batch of square ROIs from one camera, stored as one array: the form in which ROI finders hand
ROIs to fitters (SMLMBoxer to GaussMLE, for example).

# Fields
- `data::A`: the ROI pixels, an `AbstractArray{T,3}` of size `(roi_size, roi_size, n_rois)`
  indexed `[row, col, roi] = [y, x, roi]`, as cut from the camera image, in the camera's raw
  units (ADU for an [`SCMOSCamera`](@ref), which a fitter converts with the camera's `offset`
  and `gain`)
- `x_corners::Vector{Int32}`: camera column of each ROI's top-left pixel, 1-based
- `y_corners::Vector{Int32}`: camera row of each ROI's top-left pixel, 1-based
- `frame_indices::Vector{Int32}`: frame number of each ROI, 1-based
- `camera::C`: the camera of the full image (an `AbstractCamera`)
- `roi_size::Int`: side of each ROI (pixels)

`T` is the element type of `data`, `N` is 3, `A` is the array type (`Array`, or a GPU array) and
`C` the camera type.

ROI pixel `data[i, j, k]` is camera pixel (column `x_corners[k] + j - 1`, row
`y_corners[k] + i - 1`). For uniform pixels of size `Δx` × `Δy` (µm) its center is at
`((x_corners[k] + j - 1.5)·Δx, (y_corners[k] + i - 1.5)·Δy)` µm; see [ROIs](@ref).

# Constructors
- `ROIBatch(data, x_corners, y_corners, frame_indices, camera)`: the corner and frame vectors
  may hold any integer type and are converted to `Int32`. ROIs must be square (else an
  `ArgumentError`), and each vector needs one entry per ROI (else a `DimensionMismatch`).
- `ROIBatch(rois::Vector{SingleROI{T}}, camera)`: from single ROIs of one size; an empty vector
  gives an empty batch.

# Notes
- `batch[k]` returns ROI `k` as a [`SingleROI`](@ref), `length(batch)` is the number of ROIs,
  and iterating a batch gives its ROIs in order.
- `Adapt.adapt(CuArray, batch)` (after `using Adapt, CUDA`; both must be added to the
  environment, `Pkg.add(["Adapt", "CUDA"])`) moves `data` to the GPU. The corners, frame indices
  and camera stay on the host.
  ```julia
  using Adapt, CUDA
  batch_gpu = Adapt.adapt(CuArray, batch)
  ```

# Example
```jldoctest
julia> camera = IdealCamera(512, 512, 0.1);

julia> data = zeros(Float32, 11, 11, 3);   # 3 ROIs of 11 × 11 pixels, [y, x, roi]

julia> batch = ROIBatch(data, [100, 200, 300], [50, 60, 70], [1, 1, 2], camera);

julia> length(batch), batch.roi_size
(3, 11)

julia> Tuple(batch[3].corner), batch[3].frame_idx
((300, 70), 2)
```

# See also
[`SingleROI`](@ref), [`IdealCamera`](@ref), [`SCMOSCamera`](@ref)
"""
struct ROIBatch{T,N,A<:AbstractArray{T,N},C<:AbstractCamera}
    data::A
    x_corners::Vector{Int32}
    y_corners::Vector{Int32}
    frame_indices::Vector{Int32}
    camera::C
    roi_size::Int

    function ROIBatch(data::A, x_corners::Vector{Int32}, y_corners::Vector{Int32},
                     frame_indices::Vector{Int32}, camera::C) where {T,A<:AbstractArray{T,3},C<:AbstractCamera}
        n_rois = size(data, 3)
        roi_size = size(data, 1)

        size(data, 1) == size(data, 2) || throw(ArgumentError(
            "ROIs must be square (got $(size(data, 1))×$(size(data, 2)))"))
        length(x_corners) == n_rois || throw(DimensionMismatch(
            "Must have one x_corner per ROI (got $(length(x_corners)) for $n_rois ROIs)"))
        length(y_corners) == n_rois || throw(DimensionMismatch(
            "Must have one y_corner per ROI (got $(length(y_corners)) for $n_rois ROIs)"))
        length(frame_indices) == n_rois || throw(DimensionMismatch(
            "Must have one frame index per ROI (got $(length(frame_indices)) for $n_rois ROIs)"))

        new{T,3,A,C}(data, x_corners, y_corners, frame_indices, camera, roi_size)
    end
end

function ROIBatch(data::AbstractArray{T,3}, x_corners::Vector, y_corners::Vector,
                  frame_indices::Vector, camera::C) where {T,C<:AbstractCamera}
    # Convert to Int32 and call inner constructor
    ROIBatch(data, Int32.(x_corners), Int32.(y_corners), Int32.(frame_indices), camera)
end

function ROIBatch(rois::Vector{SingleROI{T}}, camera::C) where {T,C<:AbstractCamera}
    if isempty(rois)
        # Empty batch - use provided camera
        return ROIBatch(zeros(T, 0, 0, 0), Int32[], Int32[], Int32[], camera)
    end

    roi_size = size(first(rois).data, 1)
    n_rois = length(rois)

    # Pre-allocate arrays
    data = Array{T,3}(undef, roi_size, roi_size, n_rois)
    x_corners = Vector{Int32}(undef, n_rois)
    y_corners = Vector{Int32}(undef, n_rois)
    frame_indices = Vector{Int32}(undef, n_rois)

    # Fill arrays
    for (i, roi) in enumerate(rois)
        data[:, :, i] = roi.data
        x_corners[i] = roi.corner[1]
        y_corners[i] = roi.corner[2]
        frame_indices[i] = roi.frame_idx
    end

    ROIBatch(data, x_corners, y_corners, frame_indices, camera)
end

# ===== Indexing and Iteration =====

Base.getindex(batch::ROIBatch, i::Int) = SingleROI(
    batch.data[:, :, i],
    SVector{2,Int32}(batch.x_corners[i], batch.y_corners[i]),
    batch.frame_indices[i]
)

Base.length(batch::ROIBatch) = size(batch.data, 3)

Base.size(batch::ROIBatch) = (length(batch),)

Base.iterate(batch::ROIBatch, state=1) = state > length(batch) ? nothing : (batch[state], state + 1)

# ===== GPU Adaptation =====

# `Adapt.adapt(to, batch)` moves only `data` (to a GPU, for `to = CuArray`). The corners, frame
# indices and camera stay on the host: their fields are `Vector{Int32}` and the camera, which a
# device array is not.
function Adapt.adapt_structure(to, batch::ROIBatch)
    ROIBatch(
        Adapt.adapt(to, batch.data),
        batch.x_corners,
        batch.y_corners,
        batch.frame_indices,
        batch.camera
    )
end

# ===== Display Methods =====

function Base.show(io::IO, roi::SingleROI{T}) where T
    print(io, "SingleROI{$T}($(size(roi.data, 1))×$(size(roi.data, 2)), ")
    print(io, "corner=($(roi.corner[1]), $(roi.corner[2])), ")
    print(io, "frame=$(roi.frame_idx))")
end

function Base.show(io::IO, ::MIME"text/plain", roi::SingleROI{T}) where T
    println(io, "SingleROI{$T}:")
    println(io, "  Size: $(size(roi.data, 1)) × $(size(roi.data, 2)) pixels")
    println(io, "  Corner: ($(roi.corner[1]), $(roi.corner[2])) = (col, row)")
    print(io, "  Frame: $(roi.frame_idx)")
end

function Base.show(io::IO, batch::ROIBatch{T}) where T
    n_rois = length(batch)
    print(io, "ROIBatch{$T}($(batch.roi_size)×$(batch.roi_size), $n_rois ROIs)")
end

function Base.show(io::IO, ::MIME"text/plain", batch::ROIBatch{T,N,A,C}) where {T,N,A,C}
    n_rois = length(batch)

    println(io, "ROIBatch{$T} with:")
    println(io, "  ROI size: $(batch.roi_size) × $(batch.roi_size) pixels")
    println(io, "  Number of ROIs: $n_rois")
    println(io, "  Data type: $A")
    println(io, "  Camera: $C")

    if n_rois > 0
        # Frame statistics
        frame_range = extrema(batch.frame_indices)
        n_frames = frame_range[2] - frame_range[1] + 1
        println(io, "  Frames: $(frame_range[1]) to $(frame_range[2]) (spanning $n_frames frames)")

        # Corner statistics
        x_range = extrema(batch.x_corners)
        y_range = extrema(batch.y_corners)
        print(io, "  Corner range: x=$(x_range[1]) to $(x_range[2]), y=$(y_range[1]) to $(y_range[2])")
    end
end
