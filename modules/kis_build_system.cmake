# kis_build_system/modules/kis_build_system.cmake (Master Module)

# This file is the main module that gets included by consumers.
# It makes all the build system functions available.
get_filename_component(KIS_BUILD_SYSTEM_MODULE_PATH "${CMAKE_CURRENT_LIST_FILE}" PATH)

# By adding our own directory to the module path, commands like include()
# will now work correctly from any script that has included this file.
list(APPEND CMAKE_MODULE_PATH "${KIS_BUILD_SYSTEM_MODULE_PATH}")

# --- Include all build system components ---
include(utils)                  # Load utility functions first

# Dependency Handling
include(first_party_deps)       # Functions for handling KIS package dependencies
include(third_party_deps)       # Functions for FetchContent and third-party libs
include(dependency_linking)     # The deferred linking system

# Package Discovery and Configuration
include(package_discovery)      # Finds packages on disk
include(imported_targets)       # Creates IMPORTED targets for variant fallbacks
include(package_configuration)  # Configures/builds/imports packages and links them

# Core Build System Infrastructure
include(components)
include(dependency_resolution)
include(diagnostics)
include(env_setup)
include(installation)
include(packaging)
include(paths)
include(platforms)
include(sdk_variants)
include(targets)
include(presets_logic)
include(manifest_validation)
# Note: platform_setup.cmake is NOT included here, it's a superbuild-only setup script.

# --- Provide a consistent target for FetchContent ---
if(NOT TARGET kis_build_system_pkg)
    add_library(kis_build_system_pkg INTERFACE)
    add_library(kis::build_system ALIAS kis_build_system_pkg)
endif()