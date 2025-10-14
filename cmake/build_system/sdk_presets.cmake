# cmake/build_system/sdk_presets.cmake

message(STATUS "Loading SDK compiler presets...")

set(CMAKE_DEBUG_POSTFIX "_d" CACHE STRING "Default suffix for debug-mode library files.")

include(presets_logic)

add_library(kis_sdk_presets INTERFACE)
apply_kis_build_presets(kis_sdk_presets)