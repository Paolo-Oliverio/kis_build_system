# kis_build_system/modules/sdk_presets.cmake

message(STATUS "Loading SDK compiler presets...")

set(CMAKE_DEBUG_POSTFIX "_d" CACHE STRING "Default suffix for debug-mode library files.")

# --- THE NEW APPROACH: Define settings in global properties ---
# This is the ONLY responsibility of this file in a superbuild context.
# It sets the canonical build settings that all packages will later read.

# 1. Define properties that should be PUBLIC on consuming packages.
set_property(GLOBAL PROPERTY KIS_SDK_PUBLIC_COMPILE_FEATURES cxx_std_17)
set_property(GLOBAL PROPERTY KIS_SDK_PUBLIC_COMPILE_DEFINITIONS
    $<$<PLATFORM_ID:Windows>:UNICODE;_UNICODE>
    KIS_DISABLE_DEPRECATED
)

# 2. Define properties that should be PRIVATE to our SDK packages' build.
set_property(GLOBAL PROPERTY KIS_SDK_PRIVATE_COMPILE_OPTIONS
    $<$<CXX_COMPILER_ID:MSVC>:/W4 /WX>
    $<$<AND:$<CXX_COMPILER_ID:GNU,Clang>,$<NOT:$<CXX_COMPILER_ID:AppleClang>>>:-Wall -Wextra -Wpedantic -Werror>
)