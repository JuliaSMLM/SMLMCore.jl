"""
    SMLMCore

Types for single molecule localization microscopy (SMLM) data: emitters (localizations),
cameras, ROI batches and SMLD containers, with coordinate conversions, filters, and functions
that combine data sets. Lengths are in µm.

# Example
```jldoctest
julia> cam = IdealCamera(512, 512, 0.1);

julia> emitters = [
           Emitter2DFit{Float64}(1.0, 2.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0),
           Emitter2DFit{Float64}(3.0, 4.0, 1200.0, 12.0, 0.01, 0.01, 60.0, 2.0),
       ];

julia> smld = BasicSMLD(emitters, cam, 1, 1);

julia> length(@filter(smld, photons > 1100)), length(filter_roi(smld, (0.0, 2.0), (1.0, 3.0)))
(1, 1)
```

`SMLMCore.api_overview()` returns an overview of the whole API as a `String`; the same text is
its help entry:

```julia-repl
help?> SMLMCore.api_overview
```
"""
module SMLMCore

# Type definitions
export
    # Abstract types
    AbstractEmitter,
    AbstractCamera,
    AbstractSMLD,
    SMLD,  # Alias of AbstractSMLD, kept for code written against SMLMData

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