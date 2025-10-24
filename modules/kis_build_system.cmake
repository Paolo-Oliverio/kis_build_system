# kis_build_system/modules/kis_build_system.cmake (Master Module - CORE ENGINE)

# This file is the main module that gets included by consumers.
# It makes all CORE build system functions available.
get_filename_component(KIS_BUILD_SYSTEM_MODULE_PATH "${CMAKE_CURRENT_LIST_FILE}" PATH)

# By adding our own directory to the module path, commands like include()
# will now work correctly from any script that has included this file.
list(APPEND CMAKE_MODULE_PATH "${KIS_BUILD_SYSTEM_MODULE_PATH}")

# --- Include all CORE build system components ---
# These modules are required by ALL build modes (SDK, Standalone, Bootstrap).

# CMake Policy Configuration (MUST BE FIRST)
include(policies)

# Caching System (MUST BE EARLY)
include(cache)

# Foundational Utilities
include(utils)
include(kis_state)
include(file_utils)
include(entrypoints)

# Dependency Declaration & Linking
include(first_party_deps)       # Handles manifest parsing for KIS deps
include(third_party_deps)       # Handles manifest parsing for TPL deps
include(dependency_linking)     # The deferred linking system (kis_link_from_manifest)

# Package Discovery and Configuration
include(package_discovery)      # Finds packages on disk
include(imported_targets)       # Creates IMPORTED targets for variant fallbacks
include(package_configuration)  # Configures/builds/imports packages

# Core Build Infrastructure
include(components)             # kis_add_test, kis_add_sample
include(diagnostics)            # Warning collection, cache checks
include(installation)           # Installation helpers
include(packaging)              # kis_install_package
include(paths)                  # setup_sdk_paths
include(platforms)              # kis_add_platform_specializations
include(sdk_variants)           # ABI groups and variant logic
include(targets)                # kis_add_library
include(presets_logic)          # apply_kis_build_presets
include(manifest_validation)    # kis_validate_package_manifest
include(build_profiling)
include(build_summary)
include(compiler_cache)
include(dependency_graph)
include(incremental_validation)
include(incremental_dependencies)
include(parallel_fetch)

# HOST-SPECIFIC modules are NOT included here.
# The "host" (e.g., the root CMakeLists.txt or a standalone package)
# is responsible for including modules like:
# - platform_setup.cmake (Superbuild-only)
# - dependency_resolution.cmake (Superbuild-only)
# - standalone.cmake (Standalone-only)
# - env_setup.cmake (Superbuild-only)


# --- Provide a consistent target for FetchContent ---
# This block should ONLY run in project configuration mode, not script mode.
if(CMAKE_PROJECT_NAME)
    if(NOT TARGET kis_build_system_pkg)
        add_library(kis_build_system_pkg INTERFACE)
        add_library(kis::build_system ALIAS kis_build_system_pkg)
    endif()
endif()