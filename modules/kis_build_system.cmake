# kis_build_system/modules/kis_build_system.cmake (Master Module)

# This file is the main module that gets included by consumers.
# It makes all the build system functions available.
get_filename_component(KIS_BUILD_SYSTEM_MODULE_PATH "${CMAKE_CURRENT_LIST_FILE}" PATH)

# By adding our own directory to the module path, commands like include(sdk_options)
# will now work correctly from any script that has included this file.
list(APPEND CMAKE_MODULE_PATH "${KIS_BUILD_SYSTEM_MODULE_PATH}")

# --- Include all build system components ---
# These are now included directly by the functions/scripts that need them,
# or by the main superbuild script. The key is that they are *findable*.
# We only need to include the function definitions here.
include(components)
include(dependencies)
include(dependency_resolution)
include(discovery)
include(env_setup)
include(installation)
include(packaging)
include(paths)
include(presets_logic)
# sdk_options, sdk_presets, and sdk_versions are included by the top-level
# project, not globally here as just needed by sdk consumers.

# --- Provide a consistent target for FetchContent ---
if(NOT TARGET kis_build_system_pkg)
    add_library(kis_build_system_pkg INTERFACE)
    add_library(kis::build_system ALIAS kis_build_system_pkg)
endif()