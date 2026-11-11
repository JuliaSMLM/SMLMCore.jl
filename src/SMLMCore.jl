"""
    SMLMCore

A Julia package for working with Single Molecule Localization Microscopy (SMLM) data.

File io (SMITE) is in SMLMio, and SMLMData loads both SMLMCore and SMLMio.

# Features
- Type system for emitters, cameras, and localization data
- Physical coordinate handling (microns) with camera pixel mappings
- Filtering and ROI selection tools
- Memory-efficient data structures

# Basic Usage
```julia
using SMLMCore

# Create a camera
cam = IdealCamera(1:512, 1:512, 0.1)  # 512x512 camera with 0.1 micron pixels

# Create some emitters
emitters = [
    Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0),
    Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0)
]

# Create SMLD object
smld = BasicSMLD(emitters, cam, 1, 1, Dict{String,Any}())

# Filter operations
roi = filter_roi(smld, 0.0:2.0, 1.0:3.0)
bright = @filter(smld, photons > 1000)
```

# API Overview
For a comprehensive overview of the API, use the help mode on `SMLMCore.api_overview`:

```julia
?SMLMCore.api_overview
```

Or access the complete API documentation programmatically:

```julia
docs = SMLMCore.api_overview()
```
"""
module SMLMCore

# Type definitions
export
    # Abstract types
    AbstractEmitter,
    AbstractCamera,
    AbstractSMLD,
    SMLD,  # Deprecated alias for AbstractSMLD

    # Ecosystem abstract types (tuple pattern)
    AbstractSMLMConfig,
    AbstractSMLMInfo,

    # Concrete emitter types
    Emitter2D,
    Emitter3D,
    Emitter2DFit,
    Emitter3DFit,

    # Camera types
    IdealCamera,
    SCMOSCamera,

    # ROI batch types
    SingleROI,
    ROIBatch,

    # SMLD types
    BasicSMLD

# Coordinates and conversions
export 
    pixel_to_physical,
    physical_to_pixel,
    physical_to_pixel_index,
    compute_bin_edges,
    get_pixel_centers

# Filtering and operations
export
    @filter,
    filter_frames,
    filter_roi,
    emitter_ndims,
    cat_smld,
    merge_smld

# Ecosystem abstract types for the (Config, Info, Data) tuple pattern
"""
    AbstractSMLMConfig

Abstract supertype for configuration structs in the JuliaSMLM ecosystem.
Subtypes hold algorithm parameters (e.g., fit settings, simulation parameters).
"""
abstract type AbstractSMLMConfig end

"""
    AbstractSMLMInfo

Abstract supertype for information/results structs in the JuliaSMLM ecosystem.
Subtypes hold computed metadata or diagnostic output from algorithms.
"""
abstract type AbstractSMLMInfo end

# Include all source files
include("types/emitters.jl")  # Move from current location
include("types/cameras.jl")   # Move from current location
include("types/roi_batch.jl") # ROI batch types for ecosystem interop
include("types/smld.jl")      # Move from current location

include("core/coordinates.jl") # Move from coordinates.jl
include("core/filters.jl")    # Move from filters.jl
include("core/operations.jl") # Move from operations.jl

# Include the API overview functionality
include("api.jl")

end