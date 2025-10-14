# kis_build_system/modules/sdk_presets.cmake

message(STATUS "Loading SDK compiler presets...")

set(CMAKE_DEBUG_POSTFIX "_d" CACHE STRING "Default suffix for debug-mode library files.")

include(presets_logic)

# --- THE KEY CHANGE ---
# Instead of creating a new 'kis_sdk_presets' target, we find the existing
# 'kis::build_system' target (which is guaranteed to exist by now) and
# apply all the compiler settings directly to it.
message(STATUS "--> Applying presets to the central kis::build_system target")
apply_kis_build_presets(kis::build_system)