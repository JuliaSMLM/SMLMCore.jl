using SMLMCore, Test

# A vector and a matrix indexed from 0, standing in for offset arrays
struct ZeroBasedVector{T} <: AbstractVector{T}
    v::Vector{T}
end
Base.size(z::ZeroBasedVector) = size(z.v)
Base.axes(z::ZeroBasedVector) = (0:length(z.v)-1,)
Base.getindex(z::ZeroBasedVector, i::Int) = z.v[i+1]
struct ZeroBasedMatrix{T} <: AbstractMatrix{T}
    m::Matrix{T}
end
Base.size(z::ZeroBasedMatrix) = size(z.m)
Base.axes(z::ZeroBasedMatrix) = map(n -> 0:n-1, size(z.m))
Base.getindex(z::ZeroBasedMatrix, i::Int, j::Int) = z.m[i+1, j+1]

@testset "Coordinate Conversion" begin
    @testset "Basic Conversions" begin
        pixel_size = 0.1  # 100nm pixels

        # Test pixel center to physical coordinates
        x, y = pixel_to_physical(1.0, 1.0, pixel_size)
        @test x ≈ 0.05
        @test y ≈ 0.05

        # Test physical back to pixel coordinates
        px, py = physical_to_pixel(0.05, 0.05, pixel_size)
        @test px ≈ 1.0
        @test py ≈ 1.0

        # Test corner cases
        x, y = pixel_to_physical(0.5, 0.5, pixel_size)
        @test x ≈ 0.0
        @test y ≈ 0.0
    end

    @testset "Round Trip Conversions" begin
        pixel_size = 0.1

        # Test pixel → physical → pixel
        original_px, original_py = 1.5, 2.5
        x, y = pixel_to_physical(original_px, original_py, pixel_size)
        px, py = physical_to_pixel(x, y, pixel_size)
        @test px ≈ original_px
        @test py ≈ original_py

        # Test physical → pixel → physical
        original_x, original_y = 0.15, 0.25
        px, py = physical_to_pixel(original_x, original_y, pixel_size)
        x, y = pixel_to_physical(px, py, pixel_size)
        @test x ≈ original_x
        @test y ≈ original_y
    end

    @testset "Pixel Indexing" begin
        pixel_size = 0.1

        # Test center of pixels
        px, py = physical_to_pixel_index(0.05, 0.05, pixel_size)
        @test px == 1
        @test py == 1

        # Test edges
        px, py = physical_to_pixel_index(0.09, 0.09, pixel_size)
        @test px == 1
        @test py == 1

        px, py = physical_to_pixel_index(0.11, 0.11, pixel_size)
        @test px == 2
        @test py == 2
    end

    @testset "Pixel index of a position on a pixel edge" begin
        # Pixel i covers [(i-1)·pixel_size, i·pixel_size): a position on an edge belongs to the
        # pixel that starts there, and the camera's corner (0, 0) is in pixel (1, 1). 0.125 is
        # exact in binary, so every edge below is exactly representable.
        ps = 0.125
        @test physical_to_pixel_index(0.0, 0.0, ps) == (1, 1)
        @test physical_to_pixel_index(0.125, 0.0, ps) == (2, 1)
        @test physical_to_pixel_index(0.25, 0.375, ps) == (3, 4)
        @test physical_to_pixel_index(0.5, 0.25, ps) == (5, 3)
        @test physical_to_pixel_index(0.124, 0.249, ps) == (1, 2)
        # A 512-pixel camera's right edge is outside it, at pixel 513 (no bounds check)
        @test physical_to_pixel_index(64.0, 63.99, ps) == (513, 512)
        @test physical_to_pixel_index(-0.01, 0.0, ps) == (0, 1)
    end

    @testset "physical_to_pixel keeps the input's float type" begin
        px, py = physical_to_pixel(0.05f0, 0.15f0, 0.1f0)
        @test px isa Float32 && py isa Float32
        @test px ≈ 1.0f0 && py ≈ 2.0f0
        @test physical_to_pixel(0.05, 0.15, 0.1) isa Tuple{Float64,Float64}
        # Rational inputs give Float64, as in SMLMData 0.7.1; they gave Rationals, which can
        # overflow (1//typemax(Int) + 1//2 threw an OverflowError)
        @test physical_to_pixel(1//3, 2//3, 1//1) isa Tuple{Float64,Float64}
        @test all(physical_to_pixel(1//3, 2//3, 1//1) .≈ (5 / 6, 7 / 6))
        @test physical_to_pixel(1//typemax(Int), 2//3, 1//1)[1] ≈ 0.5
        # The quotient itself must not overflow either, and a Rational{BigInt} gives Float64
        @test physical_to_pixel(1//typemax(Int), 1//1, 2//1) == (0.5, 1.0)
        @test physical_to_pixel(1//typemax(Int), 1//3, 2//3) == (0.5, 1.0)
        @test physical_to_pixel(big(1)//3, big(1)//4, big(1)//1) isa Tuple{Float64,Float64}
        @test physical_to_pixel(1, 2, 1//2) === (2.5, 4.5)
        @test physical_to_pixel(1//2, 1//4, 1) === (1.0, 0.75)
        # The exact value, half included, rounded once to the nearest Float64, at any BigFloat
        # precision
        @test physical_to_pixel(1//3, 0//1, 1)[1] === 5 / 6
        @test physical_to_pixel(-200//1, -200//1, 24//1)[1] === -47 / 6
        @test physical_to_pixel(-1//2 + 1//2^60, 0//1, 1)[1] === 2.0^-60
        @test setprecision(() -> physical_to_pixel(1//3, 0//1, 1)[1], BigFloat, 24) === 5 / 6
        @test SMLMCore._nearest_float64(big(3) // big(2)^1075) === 2 * nextfloat(0.0)  # tie to even
        @test SMLMCore._nearest_float64(big(2)^1100 // 1) === Inf
        @test physical_to_pixel(-200, 0, 24//1)[1] === -47 / 6               # integer over Rational
        @test physical_to_pixel(1//0, -1//0, 1) === (Inf, -Inf)              # Rational infinities
        # Other number types keep the quotient's type, as in 0.1.0
        @test physical_to_pixel(big(1.0), big(2.0), big(1.0)) isa Tuple{BigFloat,BigFloat}
        @test physical_to_pixel(big(1), big(2), big(1)) isa Tuple{BigFloat,BigFloat}
        @test physical_to_pixel(Float16(0.1), Float16(0.3), Float16(0.1)) isa Tuple{Float16,Float16}
        @test physical_to_pixel(0.5f0, 1//2, 1//1) isa Tuple{Float32,Float64}
        @test physical_to_pixel(1, 2, 1) === (1.5, 2.5)
        # A Float32 position with a Float64 pixel size promotes as division does
        @test physical_to_pixel(0.05f0, 0.15f0, 0.1) isa Tuple{Float64,Float64}
    end
end

@testset "Camera" begin
    @testset "IdealCamera Construction" begin
        # Test square pixels
        cam = IdealCamera(1:512, 1:512, 0.1)
        @test length(cam.pixel_edges_x) == 513  # N+1 edges
        @test length(cam.pixel_edges_y) == 513
        
        # Test edge positions
        @test cam.pixel_edges_x[1] ≈ 0.0  # First edge at 0
        @test cam.pixel_edges_x[2] ≈ 0.1  # Second edge at pixel_size
        @test cam.pixel_edges_x[3] ≈ 0.2  # Third edge at 2*pixel_size
        
        # Verify first pixel center is at pixel_size/2
        centers_x, centers_y = get_pixel_centers(cam)
        @test centers_x[1] ≈ 0.05
        @test centers_y[1] ≈ 0.05
        
        # Test rectangular pixels
        cam_rect = IdealCamera(1:512, 1:256, (0.1, 0.2))
        @test cam_rect.pixel_edges_x[1] ≈ 0.0
        @test cam_rect.pixel_edges_y[1] ≈ 0.0
        @test cam_rect.pixel_edges_x[2] ≈ 0.1
        @test cam_rect.pixel_edges_y[2] ≈ 0.2
        
        # Test different numeric types
        cam_32 = IdealCamera(1:3, 1:3, 0.1f0)
        @test eltype(cam_32.pixel_edges_x) === Float32
        @test cam_32.pixel_edges_x[1] ≈ 0.0f0
        @test cam_32.pixel_edges_x[2] ≈ 0.1f0
    end

    @testset "Pixel Centers" begin
        cam = IdealCamera(1:3, 1:3, 0.1)
        centers_x, centers_y = get_pixel_centers(cam)

        # Test number of centers
        @test length(centers_x) == 3
        @test length(centers_y) == 3

        # Test center positions
        @test centers_x[1] ≈ 0.05
        @test centers_x[2] ≈ 0.15
        @test centers_x[3] ≈ 0.25

        # Test with rectangular pixels
        cam_rect = IdealCamera(1:3, 1:3, (0.1, 0.2))
        centers_x, centers_y = get_pixel_centers(cam_rect)
        @test centers_x[2] ≈ 0.15
        @test centers_y[2] ≈ 0.3
    end

    @testset "Type Stability" begin
        @testset "Float32" begin
            # Test camera construction with Float32
            cam_32 = IdealCamera(1:3, 1:3, 0.1f0)
            @test eltype(cam_32.pixel_edges_x) === Float32
            @test eltype(cam_32.pixel_edges_y) === Float32

            # Verify edge values
            @test cam_32.pixel_edges_x[1] ≈ 0.0f0
            @test cam_32.pixel_edges_x[2] ≈ 0.1f0
        end

        @testset "Float64" begin
            # Test default Float64 behavior
            cam_64 = IdealCamera(1:3, 1:3, 0.1)
            @test eltype(cam_64.pixel_edges_x) === Float64
            @test eltype(cam_64.pixel_edges_y) === Float64
        end

        @testset "Coordinate Conversions" begin
            # Test type stability in coordinate conversions
            x32, y32 = pixel_to_physical(1, 1, 0.1f0)
            @test typeof(x32) === Float32
            @test typeof(y32) === Float32

            x64, y64 = pixel_to_physical(1, 1, 0.1)
            @test typeof(x64) === Float64
            @test typeof(y64) === Float64
        end
    end

    @testset "Edge Cases" begin
        # Test single pixel camera
        cam_single = IdealCamera(1:1, 1:1, 0.1)
        @test length(cam_single.pixel_edges_x) == 2
        @test cam_single.pixel_edges_x[1] ≈ 0.0
        @test cam_single.pixel_edges_x[2] ≈ 0.1

        # Test different numeric types
        cam_32 = IdealCamera(1:3, 1:3, 0.1f0)
        @test eltype(cam_32.pixel_edges_x) === Float32

        # Test different x/y dimensions
        cam_rect = IdealCamera(1:10, 1:5, 0.1)
        @test length(cam_rect.pixel_edges_x) == 11
        @test length(cam_rect.pixel_edges_y) == 6
    end
end

@testset "Bin Edge Computation" begin
    @testset "Square Pixels" begin
        edges_x, edges_y = compute_bin_edges(1:3, 1:3, 0.1)

        # Test number of edges
        @test length(edges_x) == 4  # N+1 edges for N pixels
        @test length(edges_y) == 4

        # Test edge positions
        @test edges_x[1] ≈ 0.0
        @test edges_x[2] ≈ 0.1
        @test edges_x[3] ≈ 0.2
        @test edges_x[4] ≈ 0.3
    end

    @testset "Rectangular Pixels" begin
        edges_x, edges_y = compute_bin_edges(1:3, 1:3, (0.1, 0.2))

        # Test edge spacing
        @test edges_x[2] - edges_x[1] ≈ 0.1
        @test edges_y[2] - edges_y[1] ≈ 0.2

        # Test total size
        @test edges_x[end] - edges_x[1] ≈ 0.3
        @test edges_y[end] - edges_y[1] ≈ 0.6
    end
end

@testset "Pixel ranges number the whole sensor from 0 or 1" begin
    # A range from 0 or 1 is the whole sensor, edges from 0 µm, as in 0.1.0
    ref = IdealCamera(64, 32, 0.1)
    for (rx, ry) in ((1:64, 1:32), (0:63, 0:31), (Base.OneTo(64), Base.OneTo(32)), (0:63, 1:32))
        cam = IdealCamera(rx, ry, 0.1)
        @test cam.pixel_edges_x == ref.pixel_edges_x
        @test cam.pixel_edges_y == ref.pixel_edges_y
    end
    @test IdealCamera(0:63, 0:31, (0.1, 0.2)).pixel_edges_y == IdealCamera(64, 32, (0.1, 0.2)).pixel_edges_y
    @test compute_bin_edges(0:2, 0:1, 0.5) == compute_bin_edges(1:3, 1:2, 0.5)
    empty = IdealCamera(0, 0, 0.1)                       # no pixels: 1:0 starts at 1
    @test empty.pixel_edges_x == [0.0]
    # and it displays (both displays read the second edge, which it lacks)
    @test sprint(show, empty) == "IdealCamera{Float64}(0×0, no pixels)"
    @test occursin("Pixel size: none", sprint(show, MIME("text/plain"), empty))
    @test sprint(show, SCMOSCamera(0, 0, 0.1, 1.6)) == "SCMOSCamera{Float64}(0×0, no pixels)"
    @test occursin("Dimensions: 0 × 0", sprint(show, MIME("text/plain"), SCMOSCamera(0, 0, 0.1, 1.6)))
    @test sprint(show, IdealCamera(4, 2, (0.1, 0.2))) == "IdealCamera{Float64}(4×2, 0.1×0.2μm)"

    # Any other start was silently a camera at 0 µm; it is refused, in each axis and form
    @test_throws ArgumentError IdealCamera(101:200, 1:100, 0.1)
    @test_throws ArgumentError IdealCamera(1:100, 101:200, 0.1)
    @test_throws ArgumentError IdealCamera(2:65, 1:64, (0.1, 0.2))
    @test_throws ArgumentError IdealCamera(-1:62, 0:63, 0.1)
    @test_throws ArgumentError compute_bin_edges(65:128, 1:128, 0.12)
    @test_throws ArgumentError compute_bin_edges(1:3, 3:5, (0.1, 0.2))
    err = try
        IdealCamera(101:200, 1:100, 0.1); nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("101:200", err.msg)
    @test occursin("cropped camera", err.msg)
    @test occursin("pixel edges", err.msg)

    # A cropped camera is built from its edges
    crop = IdealCamera(collect(range(7.68, step = 0.12, length = 65)), collect(range(0.0, step = 0.12, length = 129)))
    @test crop.pixel_edges_x[1] == 7.68
    @test length(crop.pixel_edges_x) == 65
end

@testset "SCMOSCamera" begin
    @testset "Construction with scalar parameters" begin
        # Minimal constructor (readnoise only)
        cam = SCMOSCamera(512, 512, 0.1, 1.6)
        @test length(cam.pixel_edges_x) == 513
        @test length(cam.pixel_edges_y) == 513
        @test cam.offset === 0.0
        @test cam.gain === 1.0
        @test cam.readnoise === 1.6
        @test cam.qe === 1.0

        # With all parameters
        cam_full = SCMOSCamera(512, 512, 0.1, 1.6, offset=100.0, gain=0.46, qe=0.72)
        @test cam_full.offset === 100.0
        @test cam_full.gain === 0.46
        @test cam_full.readnoise === 1.6
        @test cam_full.qe === 0.72

        # Rectangular pixels
        cam_rect = SCMOSCamera(512, 256, (0.1, 0.15), 1.8)
        @test cam_rect.pixel_edges_x[2] ≈ 0.1
        @test cam_rect.pixel_edges_y[2] ≈ 0.15
        @test cam_rect.readnoise === 1.8
    end

    @testset "Construction with matrix parameters" begin
        # Create calibration maps
        readnoise_map = ones(Float64, 10, 10) .* 1.5
        readnoise_map[5, 5] = 2.0  # Hot pixel

        gain_map = ones(Float64, 10, 10) .* 0.5
        qe_map = ones(Float64, 10, 10) .* 0.85

        # With readnoise map only
        cam1 = SCMOSCamera(10, 10, 0.1, readnoise_map)
        @test cam1.readnoise isa Matrix{Float64}
        @test size(cam1.readnoise) == (10, 10)
        @test cam1.readnoise[5, 5] ≈ 2.0
        @test cam1.offset === 0.0  # Scalar default
        @test cam1.gain === 1.0

        # With all matrix parameters
        offset_map = ones(Float64, 10, 10) .* 100.0
        cam2 = SCMOSCamera(10, 10, 0.1, readnoise_map,
                          offset=offset_map, gain=gain_map, qe=qe_map)
        @test cam2.offset isa Matrix{Float64}
        @test cam2.gain isa Matrix{Float64}
        @test cam2.qe isa Matrix{Float64}
        @test size(cam2.offset) == (10, 10)

        # Mixed scalar and matrix
        cam3 = SCMOSCamera(10, 10, 0.1, readnoise_map,
                          offset=100.0, gain=gain_map, qe=0.85)
        @test cam3.offset isa Float64
        @test cam3.gain isa Matrix{Float64}
        @test cam3.qe isa Float64
    end

    @testset "Construction with custom edges" begin
        edges_x = collect(range(0.0, 1.0, length=11))
        edges_y = collect(range(0.0, 0.5, length=6))

        # Scalar parameters
        cam = SCMOSCamera(edges_x, edges_y, readnoise=1.5, gain=0.5)
        @test length(cam.pixel_edges_x) == 11
        @test length(cam.pixel_edges_y) == 6
        @test cam.readnoise === 1.5
        @test cam.gain === 0.5

        # Matrix parameters - size must be (ny, nx) = (rows, cols) following Julia convention
        # edges_x has 11 elements → nx = 10 columns
        # edges_y has 6 elements → ny = 5 rows
        noise_map = ones(Float64, 5, 10) .* 1.2  # (ny, nx) = (5, 10)
        cam2 = SCMOSCamera(edges_x, edges_y, readnoise=noise_map)
        @test size(cam2.readnoise) == (5, 10)
    end

    @testset "Type stability" begin
        # Float32
        cam32 = SCMOSCamera(10, 10, 0.1f0, 1.6f0)
        @test eltype(cam32.pixel_edges_x) === Float32
        @test eltype(cam32.pixel_edges_y) === Float32
        @test cam32.offset === 0.0f0
        @test cam32.readnoise === 1.6f0

        # Float64
        cam64 = SCMOSCamera(10, 10, 0.1, 1.6)
        @test eltype(cam64.pixel_edges_x) === Float64
        @test cam64.offset === 0.0

        # Matrix type matching
        noise_map32 = ones(Float32, 10, 10)
        cam_mat32 = SCMOSCamera(10, 10, 0.1f0, noise_map32)
        @test eltype(cam_mat32.readnoise) === Float32
    end

    @testset "Dimension validation" begin
        # Wrong matrix size should error
        wrong_size_map = ones(Float64, 5, 5)
        @test_throws DimensionMismatch SCMOSCamera(10, 10, 0.1, wrong_size_map)
        @test_throws DimensionMismatch SCMOSCamera(10, 10, 0.1, 1.5, gain=wrong_size_map)
        @test_throws DimensionMismatch SCMOSCamera(10, 10, 0.1, 1.5, offset=wrong_size_map)
        @test_throws DimensionMismatch SCMOSCamera(10, 10, 0.1, 1.5, qe=wrong_size_map)
    end

    @testset "Matrix convention (ny, nx) for rectangular cameras" begin
        # Rectangular camera: 512 columns (x), 256 rows (y)
        # Matrix must be (ny, nx) = (256, 512) following Julia [row, col] convention
        nx, ny = 512, 256

        # Create noise map with a marker at known position
        noise_map = ones(Float64, ny, nx)  # (256, 512) = (rows, cols)
        noise_map[100, 300] = 5.0  # row 100, col 300 → pixel (x=300, y=100)

        cam = SCMOSCamera(nx, ny, 0.1, noise_map)
        @test size(cam.readnoise) == (ny, nx)
        @test size(cam.readnoise) == (256, 512)

        # Verify semantic access: map[y, x] gives value for pixel at (x, y)
        @test cam.readnoise[100, 300] == 5.0

        # Transposed matrix should fail
        wrong_map = ones(Float64, nx, ny)  # (512, 256) - WRONG
        @test_throws DimensionMismatch SCMOSCamera(nx, ny, 0.1, wrong_map)
    end

    @testset "Realistic use cases" begin
        # ORCA-Flash4.0 V3
        cam_flash = SCMOSCamera(
            2048, 2048, 0.065,
            1.6,
            offset = 100.0,
            gain = 0.46,
            qe = 0.72
        )
        @test length(cam_flash.pixel_edges_x) == 2049
        @test cam_flash.readnoise === 1.6
        @test cam_flash.gain === 0.46

        # Low-noise camera, 4096 × 2304 pixels, 0.077 µm at the sample
        cam_quest = SCMOSCamera(4096, 2304, 0.077, 0.27, gain=0.5, qe=0.85)
        @test cam_quest.readnoise === 0.27
        @test cam_quest.qe === 0.85

        # With per-pixel calibration
        nx, ny = 512, 512
        readnoise_map = randn(nx, ny) .* 0.2 .+ 1.5  # ~1.5 ± 0.2 e⁻ rms
        gain_map = randn(nx, ny) .* 0.05 .+ 0.5      # ~0.5 ± 0.05 e⁻/ADU
        qe_map = randn(nx, ny) .* 0.02 .+ 0.85       # ~0.85 ± 0.02

        cam_calibrated = SCMOSCamera(
            nx, ny, 0.1, readnoise_map,
            offset = 100.0,
            gain = gain_map,
            qe = qe_map
        )
        @test size(cam_calibrated.readnoise) == (nx, ny)
        @test size(cam_calibrated.gain) == (nx, ny)
        @test cam_calibrated.offset === 100.0  # Scalar
    end

    @testset "Display methods" begin
        # Compact display (scalar)
        cam = SCMOSCamera(512, 512, 0.1, 1.6)
        str = sprint(show, cam)
        @test contains(str, "SCMOSCamera{Float64}")
        @test contains(str, "512×512")
        @test contains(str, "0.1μm")

        # Detailed display
        io = IOBuffer()
        show(io, MIME("text/plain"), cam)
        detailed = String(take!(io))
        @test contains(detailed, "SCMOSCamera{Float64}")
        @test contains(detailed, "Dimensions: 512 × 512 pixels")
        @test contains(detailed, "Pixel size: 0.1 μm")
        @test contains(detailed, "Offset: uniform")
        @test contains(detailed, "Gain: uniform")
        @test contains(detailed, "Read noise: uniform")
        @test contains(detailed, "QE: uniform")

        # With matrix parameters
        noise_map = ones(Float64, 10, 10)
        gain_map = ones(Float64, 10, 10)
        cam_matrix = SCMOSCamera(10, 10, 0.1, noise_map,
                                 offset=100.0, gain=gain_map, qe=0.85)
        io = IOBuffer()
        show(io, MIME("text/plain"), cam_matrix)
        detailed_matrix = String(take!(io))
        @test contains(detailed_matrix, "Offset: uniform")
        @test contains(detailed_matrix, "Gain: per-pixel")
        @test contains(detailed_matrix, "Read noise: per-pixel")
        @test contains(detailed_matrix, "QE: uniform")

        # Rectangular pixels
        cam_rect = SCMOSCamera(512, 256, (0.1, 0.15), 1.8)
        str_rect = sprint(show, cam_rect)
        @test contains(str_rect, "0.1×0.15μm")
    end

    # Arguments of any real number type are promoted to one camera type; 0.1.0 refused a whole
    # number or a mix of Float32 and Float64 with an UndefVarError, TypeError or MethodError.
    @testset "Number types are promoted" begin
        c = SCMOSCamera(64, 64, 0.1, 1.6; offset = 100, gain = 2, qe = 1)
        @test c isa SCMOSCamera{Float64}
        @test c.offset === 100.0 && c.gain === 2.0 && c.qe === 1.0
        c = SCMOSCamera(64, 64, 0.1, 2)
        @test c isa SCMOSCamera{Float64} && c.readnoise === 2.0
        c = SCMOSCamera(64, 64, 0.1f0, 1.6)
        @test c isa SCMOSCamera{Float64} && c.readnoise === 1.6
        @test c.pixel_edges_x[2] == Float64(0.1f0)
        m32 = fill(1.5f0, 64, 64)
        c = SCMOSCamera(64, 64, 0.1, m32)
        @test c isa SCMOSCamera{Float64} && c.readnoise isa Matrix{Float64} && c.readnoise == m32
        @test SCMOSCamera(10, 10, (0.1f0, 0.2), 1.6f0) isa SCMOSCamera{Float64}

        # All Float32 stays Float32, whole numbers included; a map of type T is stored as given
        c = SCMOSCamera(64, 64, 0.1f0, m32; offset = 100, gain = 0.5f0)
        @test c isa SCMOSCamera{Float32}
        @test c.readnoise === m32 && c.offset === 100.0f0 && c.qe === 1.0f0
        @test SCMOSCamera(10, 10, (0.1f0, 0.2f0), 1.6f0) isa SCMOSCamera{Float32}
        @test @inferred(SCMOSCamera(64, 64, 0.1f0, 1.6f0; offset = 100)) isa SCMOSCamera{Float32}

        # A call of one number type gives what 0.1.0 gave, whole numbers included
        c = SCMOSCamera(10, 10, 0.1, 1.6)
        @test c.offset === 0.0 && c.gain === 1.0 && c.qe === 1.0
        @test c.pixel_edges_x == collect(range(0.0, 10 * 0.1, length = 11))
        c = SCMOSCamera(10, 10, 1, 2)
        @test c isa SCMOSCamera{Int} && c.pixel_edges_x == collect(0:10) && c.readnoise === 2
        @test c.offset === 0 && c.gain === 1 && c.qe === 1
        @test SCMOSCamera(4, 2, (1, 2), 2).pixel_edges_y == [0, 2, 4]
        @test SCMOSCamera(4, 4, Int16(1), Int16(2)) isa SCMOSCamera{Int16}
        @test SCMOSCamera(4, 4, 1, 2; offset = 1.5) isa SCMOSCamera{Float64}
        # Whole-number edges are exact, and an edge that does not fit throws
        @test SCMOSCamera(2, 2, 2^53 + 1, 1).pixel_edges_x == [0, 2^53 + 1, 2 * (2^53 + 1)]
        @test SCMOSCamera(3, 1, Int8(40), Int8(2)).pixel_edges_x == Int8[0, 40, 80, 120]
        @test_throws OverflowError SCMOSCamera(2, 2, Int8(100), Int8(1))
        # A union of float types promotes; counts below 0 and missing edges are refused
        v = Union{Float32,Float64}[0f0, 1.0]
        @test SCMOSCamera(v, v; readnoise = 1f0) isa SCMOSCamera{Float64}
        @test SCMOSCamera(1, 1, 0.1, Union{Float32,Float64}[1f0;;]) isa SCMOSCamera{Float64}
        @test_throws ArgumentError SCMOSCamera(-1, 2, 1, 1)
        @test_throws ArgumentError SCMOSCamera(Float64[], [0.0, 1.0]; readnoise = 1.0)
        @test_throws ArgumentError IdealCamera(-1, 2, 0.1)
        @test_throws ArgumentError IdealCamera(2, -1, (0.1, 0.2))
        # IdealCamera's whole-number edges are checked too
        @test IdealCamera(3, 1, Int8(40)).pixel_edges_x == Int8[0, 40, 80, 120]
        @test_throws OverflowError IdealCamera(4, 1, Int8(40))
        @test_throws OverflowError IdealCamera(4096, 1, Int16(10))
        # Edges and maps with other indices are taken in order
        zv = ZeroBasedVector([0.0, 0.1, 0.2])
        c = SCMOSCamera(zv, zv; readnoise = ZeroBasedMatrix(fill(1.5, 2, 2)))
        @test c.pixel_edges_x == [0.0, 0.1, 0.2] && c.readnoise == fill(1.5, 2, 2)

        # The edges form promotes the same way, and takes any vector of edges
        ex32 = collect(range(0.0f0, 1.0f0, length = 11))
        c = SCMOSCamera(ex32, collect(range(0.0, 1.0, length = 11)); readnoise = 1)
        @test c isa SCMOSCamera{Float64} && c.readnoise === 1.0 && c.pixel_edges_x == Float64.(ex32)
        c = SCMOSCamera(ex32, copy(ex32); readnoise = 1.6f0)
        @test c isa SCMOSCamera{Float32} && c.pixel_edges_x === ex32
        @test SCMOSCamera(0:0.1:1, 0:0.1:1; readnoise = 1.6) isa SCMOSCamera{Float64}

        # A map of another matrix type is stored as a Matrix{T}
        c = SCMOSCamera(4, 2, 0.1, view(fill(2.0, 2, 8), :, 1:4))
        @test c.readnoise isa Matrix{Float64} && c.readnoise == fill(2.0, 2, 4)

        # A value that is not a number or a map of numbers, or a map of the wrong size, still fails
        @test_throws TypeError SCMOSCamera(4, 4, 0.1, 1.6; offset = "100")
        @test_throws DimensionMismatch SCMOSCamera(4, 4, 0.1, 1.6; gain = fill(1, 3, 3))
    end
end
