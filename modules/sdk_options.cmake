# cmake/build_system/sdk_options.cmake
# Defines all user-configurable options for the SDK build.

message(STATUS "Loading SDK build options...")

option(KIS_BUILD_COMPONENTS_IN_ALL "If ON, tests, samples, etc., will be part of the default build target ('all'). If OFF, they must be built explicitly or via CTest." ON)
option(KIS_BUILD_TESTS "Build all test projects." ON)
option(KIS_BUILD_SAMPLES "Build all sample projects." ON)
option(KIS_BUILD_BENCHMARKS "Build all benchmark projects." OFF)
option(KIS_SDK_RESOLVE_PACKAGES "Automatically resolve and clone missing first-party packages." ON)
# Development and debugging
option(KIS_DIAGNOSTIC_MODE "Enable detailed diagnostic output during configuration" OFF)
option(KIS_VERBOSE_BUILD "Enable verbose build messages (package imports, linking details)" OFF)
option(KIS_EXPORT_DEPENDENCY_GRAPH "Export dependency graph to DOT format for visualization" OFF)
option(KIS_PROFILE_BUILD "Enable build time profiling to identify slow packages" OFF)
option(KIS_DISABLE_COMPILER_CACHE "Disable automatic compiler cache (ccache/sccache) detection" OFF)
option(KIS_SKIP_MANIFEST_CHECKS "Skip validation of package manifests (kis.package.json) rely on user schema validation" OFF)

# Incremental validation options
option(KIS_ENABLE_INCREMENTAL_VALIDATION "Only re-validate packages that have changed" ON)
option(KIS_INCREMENTAL_SKIP_ACTIVE_DEV "Force validation for recently modified packages (last hour)" ON)
option(KIS_FORCE_FULL_VALIDATION "Force full validation of all packages (ignores cache)" OFF)

# Incremental dependency options
option(KIS_ENABLE_INCREMENTAL_DEPENDENCIES "Only re-fetch changed third-party dependencies" ON)
option(KIS_FORCE_DEPENDENCY_REBUILD "Force re-fetch of all dependencies (ignores cache)" OFF)

# Parallel fetch options
option(KIS_ENABLE_PARALLEL_FETCH "Fetch dependencies in parallel using Python threading" ON)
set(KIS_PARALLEL_FETCH_WORKERS "0" CACHE STRING "Number of parallel workers (0 = auto-detect based on CPU cores)")

# === FEATURE OPTIONS (control which packages get built) ===
option(KIS_BUILD_TOOLS "Build development tools and utilities" ON)
option(KIS_BUILD_EDITOR "Build editor integration packages" OFF)
option(KIS_BUILD_EXPERIMENTAL "Build experimental features" OFF)

# === ABI-AFFECTING OPTIONS (should set KIS_CONFIG_SUFFIX in preset) ===
option(KIS_ENABLE_PROFILING "Enable profiling instrumentation (requires PER_CONFIG packages)" OFF)

# List of trusted URL prefixes for package cloning.
# Can be set from command line: -DKIS_TRUSTED_URL_PREFIXES="url1;url2;url3"
# Using FORCE to ensure sdk_options.cmake changes always take effect
set(KIS_TRUSTED_URL_PREFIXES 
    "https://github.com/Paolo-Oliverio/;https://github.com/doctest;https://github.com/glfw/"
    CACHE STRING "Semicolon-separated list of trusted URL prefixes for package cloning." FORCE
)

# Convert to proper list if it's a single string
if(KIS_TRUSTED_URL_PREFIXES)
    # Ensure it's treated as a list
    set(KIS_TRUSTED_URL_PREFIXES ${KIS_TRUSTED_URL_PREFIXES})
endif()

list(APPEND CMAKE_MESSAGE_INDENT "  ")
if(KIS_DIAGNOSTIC_MODE)
    message(STATUS "🔍 DIAGNOSTIC MODE ENABLED")
    message(STATUS "CMAKE_VERSION: ${CMAKE_VERSION}")
    message(STATUS "CMAKE_GENERATOR: ${CMAKE_GENERATOR}")
    message(STATUS "CMAKE_PREFIX_PATH: ${CMAKE_PREFIX_PATH}")
endif()

message(STATUS "Trusted URL Prefixes for auto-cloning:")
if(NOT KIS_TRUSTED_URL_PREFIXES)
    kis_collect_warning("No trusted URL prefixes configured! Auto-cloning will fail.")
endif()
foreach(prefix ${KIS_TRUSTED_URL_PREFIXES})
    message(STATUS "  ✓ ${prefix}")
endforeach()

if(KIS_DIAGNOSTIC_MODE)
    message(STATUS "Raw CACHE value: ${CACHE{KIS_TRUSTED_URL_PREFIXES}}")
endif()

# Auto-detect parallel worker count based on CPU cores
if(KIS_PARALLEL_FETCH_WORKERS EQUAL 0)
    include(ProcessorCount)
    ProcessorCount(num_cores)
    if(num_cores EQUAL 0)
        set(KIS_PARALLEL_FETCH_WORKERS 4 CACHE STRING "" FORCE)
    else()
        # Use min(cores, 8) to avoid overwhelming network/disk
        if(num_cores GREATER 8)
            set(worker_count 8)
        else()
            set(worker_count ${num_cores})
        endif()
        set(KIS_PARALLEL_FETCH_WORKERS ${worker_count} CACHE STRING "" FORCE)
    endif()
    message(STATUS "Auto-detected parallel workers: ${KIS_PARALLEL_FETCH_WORKERS} (based on ${num_cores} CPU cores)")
endif()

list(REMOVE_ITEM CMAKE_MESSAGE_INDENT "  ")