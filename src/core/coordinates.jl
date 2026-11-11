"""
    pixel_to_physical(px, py, pixel_size) -> (x, y)

Convert pixel coordinates to positions in µm, for square pixels of `pixel_size` µm at the sample
with the camera's edges starting at 0.

Pixel coordinates are 1-based: `px` is the column and `py` the row, and `(1, 1)` is the center
of the top-left pixel, so `x = (px - 0.5) * pixel_size`. The result has `pixel_size`'s type, so
`pixel_size` must be a float. For rectangular pixels or a camera with its own edges, use
[`get_pixel_centers`](@ref). [Pixels and coordinates](@ref) gives the convention.

# Example
```jldoctest
julia> pixel_to_physical(1, 1, 0.1)   # the center of the top-left pixel
(0.05, 0.05)

julia> pixel_to_physical(10.5, 3, 0.1)
(1.0, 0.25)
```

# See also
[`physical_to_pixel`](@ref), [`physical_to_pixel_index`](@ref)
"""
function pixel_to_physical(px::Real, py::Real, pixel_size::T) where T
    x_physical = T((px - 0.5) * pixel_size)
    y_physical = T((py - 0.5) * pixel_size)
    return (x_physical, y_physical)
end

"""
    physical_to_pixel(x, y, pixel_size) -> (px, py)

Convert a position in µm to pixel coordinates, the inverse of [`pixel_to_physical`](@ref), for
square pixels of `pixel_size` µm at the sample with the camera's edges starting at 0.

`px` is the column and `py` the row, 1-based, and `(1, 1)` is the center of the top-left pixel,
so `px = x / pixel_size + 0.5`; the camera's corner, `(0, 0)` µm, is at `(0.5, 0.5)`. The result
has the type of `x / pixel_size`, so Float32 inputs give Float32. For the integer index of the
pixel that holds a position, use [`physical_to_pixel_index`](@ref).

# Example
```jldoctest
julia> physical_to_pixel(0.05, 0.25, 0.1)
(1.0, 3.0)
```
"""
function physical_to_pixel(x::Real, y::Real, pixel_size::Real)
    # (0, 0) µm is the top-left corner of pixel (1, 1), at pixel coordinate (0.5, 0.5). The
    # half is converted to the quotient's type so a Float32 input gives a Float32 result.
    px = x / pixel_size
    py = y / pixel_size
    return (px + oftype(px, 0.5), py + oftype(py, 0.5))
end

"""
    physical_to_pixel_index(x, y, pixel_size) -> (px, py)

Return the 1-based (column, row) index of the pixel that contains the position, for square
pixels of `pixel_size` µm with the camera's edges starting at 0.

Along each axis, pixel `n` covers the half-open interval `[(n - 1)·pixel_size, n·pixel_size)`,
up to floating-point rounding: a position computed as `(n - 1) * pixel_size` can fall in pixel
`n - 1`. A position outside the camera gives an index outside `1:N`; the function does not check
bounds.

# Example
```jldoctest
julia> physical_to_pixel_index(0.0, 0.0, 0.1)   # the camera's corner is in pixel (1, 1)
(1, 1)

julia> physical_to_pixel_index(0.25, 0.05, 0.125)   # 0.25 µm is the left edge of pixel 3
(3, 1)

julia> physical_to_pixel_index(0.3, 0.05, 0.1)   # 0.3 / 0.1 rounds to just below 3
(3, 1)
```
"""
function physical_to_pixel_index(x::Real, y::Real, pixel_size::Real)
    return (floor(Int, x / pixel_size) + 1, floor(Int, y / pixel_size) + 1)
end

"""
    get_pixel_centers(cam::AbstractCamera) -> (centers_x, centers_y)

Return the positions (µm) of a camera's pixel centers along x and along y, each midway between
two edges.

It works for any camera with `pixel_edges_x` and `pixel_edges_y` fields, uniform or not, and
for rectangular pixels.

# Example
```jldoctest
julia> centers_x, centers_y = get_pixel_centers(IdealCamera(4, 3, (0.5, 0.25)));

julia> centers_x
4-element Vector{Float64}:
 0.25
 0.75
 1.25
 1.75

julia> centers_y
3-element Vector{Float64}:
 0.125
 0.375
 0.625
```
"""
function get_pixel_centers(cam::AbstractCamera)
    # Centers are midway between edges
    centers_x = [(cam.pixel_edges_x[i] + cam.pixel_edges_x[i+1])/2 for i in 1:length(cam.pixel_edges_x)-1]
    centers_y = [(cam.pixel_edges_y[i] + cam.pixel_edges_y[i+1])/2 for i in 1:length(cam.pixel_edges_y)-1]
    return centers_x, centers_y
end
