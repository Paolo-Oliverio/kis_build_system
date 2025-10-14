# kis_build_system.cmake (Master Module)

# This file is the main module that gets included by consumers.
# It makes all the build system functions available.
# It uses CMAKE_CURRENT_LIST_DIR to robustly find other modules relative to itself.

# Get the path to the build_system directory
get_filename_component(KIS_BUILD_SYSTEM_MODULE_PATH "${CMAKE_CURRENT_LIST_FILE}" PATH)
set(KIS_BUILD_SYSTEM_BUILD_DIR "${KIS_BUILD_SYSTEM_MODULE_PATH}/cmake/build_system")

include(${KIS_BUILD_SYSTEM_BUILD_DIR}/components.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/dependencies.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/dependency_resolution.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/discovery.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/env_setup.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/installation.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/packaging.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/paths.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/presets_logic.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/sdk_options.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/sdk_presets.cmake)
include(${KIS_BUILD_SYSTEM_BUILD_DIR}/sdk_versions.cmake)

# Define an INTERFACE target. This is a clean way for other CMake logic
# (including FetchContent) to know that this package has been processed.
if(NOT TARGET kis::build_system)
    add_library(kis::build_system INTERFACE)
endif()