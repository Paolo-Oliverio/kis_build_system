# kis_build_system/modules/platform_setup.cmake
#
# PURPOSE: Bootstraps the global platform state for the superbuild.
# This script should be included ONCE at the top level of the root CMakeLists.txt.
# It defines the KIS_PLATFORM and KIS_PLATFORM_TAGS variables that the rest of
# the build configuration depends on.

# --- 1. Determine the Target Platform ---
# This can be set by a user, a preset, or a toolchain file.
# If not set, we provide a sensible default.
if(NOT DEFINED KIS_PLATFORM OR KIS_PLATFORM STREQUAL "")
    if(WIN32)
        set(KIS_PLATFORM "windows")
    elseif(UNIX AND NOT APPLE AND NOT ANDROID)
        set(KIS_PLATFORM "linux")
    elseif(ANDROID)
        set(KIS_PLATFORM "android")
    else()
        message(FATAL_ERROR "Could not determine a default KIS_PLATFORM. Please specify it with -DKIS_PLATFORM=<...>")
    endif()
endif()
set(KIS_PLATFORM "${KIS_PLATFORM}" CACHE STRING "Target platform for the build (e.g., windows, linux, android)")

# --- 1.5 Determine the Target Architecture ---
if(NOT DEFINED KIS_ARCH OR KIS_ARCH STREQUAL "")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64)$")
        set(KIS_ARCH "x64")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
        set(KIS_ARCH "arm64")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm)$")
        set(KIS_ARCH "arm32")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(i.86)$")
        set(KIS_ARCH "x86")
    else()
        # Fallback to the raw value if unknown
        set(KIS_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
        kis_collect_warning("Unknown processor '${CMAKE_SYSTEM_PROCESSOR}'. Using it directly as KIS_ARCH.")
    endif()
endif()
set(KIS_ARCH "${KIS_ARCH}" CACHE STRING "Target architecture for the build (e.g., x64, arm64)")

# Create platform identifier for paths: "platform-arch"
set(KIS_PLATFORM_ID "${KIS_PLATFORM}-${KIS_ARCH}" CACHE INTERNAL "Platform identifier")

# --- 2. Define Platform Abstraction Group Tags (for filtering only) ---
# The specific platform is always the first and most important tag.
# The order here defines the search order for packages (general to specific).
# These are used for PACKAGE FILTERING, NOT for paths.
set(KIS_PLATFORM_TAGS "")

if(KIS_PLATFORM STREQUAL "windows")
    list(APPEND KIS_PLATFORM_TAGS "desktop")
elseif(KIS_PLATFORM STREQUAL "linux")
    list(APPEND KIS_PLATFORM_TAGS "posix" "unix" "desktop")
elseif(KIS_PLATFORM STREQUAL "android")
    list(APPEND KIS_PLATFORM_TAGS "unix" "mobile")
endif()
# Add other platform mappings for macOS, iOS, etc. here

# Prepend the specific platform to make it the most specific tag.
list(PREPEND KIS_PLATFORM_TAGS ${KIS_PLATFORM})
list(REVERSE KIS_PLATFORM_TAGS) # Now sorted general -> specific
list(REMOVE_DUPLICATES KIS_PLATFORM_TAGS)

# --- 3. Determine Config Suffix (ABI-Affecting Only) ---
# Config suffix is explicitly set by presets for configurations that change ABI
# Examples: -debug, -profiling, -asan
# Default (empty) = Release build

set(KIS_CONFIG_SUFFIX "" CACHE STRING "Configuration suffix for ABI-affecting builds (e.g., debug, profiling, asan)")

# Validate config suffix format (lowercase, alphanumeric + hyphen)
if(KIS_CONFIG_SUFFIX AND NOT KIS_CONFIG_SUFFIX MATCHES "^[a-z0-9-]+$")
    message(FATAL_ERROR 
        "Invalid KIS_CONFIG_SUFFIX '${KIS_CONFIG_SUFFIX}'. "
        "Must be lowercase alphanumeric with hyphens only (e.g., 'debug', 'profiling', 'asan')")
endif()

# Determine the ABI group for the current variant
# This is used to force third-party dependencies to use plain Debug/Release builds
kis_get_current_variant_name(current_variant)
kis_get_variant_abi_group("${current_variant}" current_abi_group)
set(KIS_CURRENT_VARIANT_ABI_GROUP "${current_abi_group}" CACHE INTERNAL "ABI group of current variant")

# Create full path suffix
if(KIS_CONFIG_SUFFIX)
    set(KIS_PATH_SUFFIX "-${KIS_CONFIG_SUFFIX}" CACHE INTERNAL "Path suffix for install directories")
else()
    set(KIS_PATH_SUFFIX "" CACHE INTERNAL "Path suffix for install directories")
endif()

# --- 4. Feature Flags (for package filtering only, don't affect paths) ---
# These control WHICH packages get built, not WHERE they're installed

set(KIS_ACTIVE_FEATURES "")

if(KIS_BUILD_TOOLS)
    list(APPEND KIS_ACTIVE_FEATURES "tools")
endif()

if(KIS_BUILD_EDITOR)
    list(APPEND KIS_ACTIVE_FEATURES "editor")
endif()

if(KIS_BUILD_SAMPLES)
    list(APPEND KIS_ACTIVE_FEATURES "samples")
endif()

if(KIS_BUILD_TESTS)
    list(APPEND KIS_ACTIVE_FEATURES "tests")
endif()

if(KIS_BUILD_EXPERIMENTAL)
    list(APPEND KIS_ACTIVE_FEATURES "experimental")
endif()

if(KIS_ENABLE_PROFILING)
    list(APPEND KIS_ACTIVE_FEATURES "profiling")
endif()

list(REMOVE_DUPLICATES KIS_ACTIVE_FEATURES)

# --- 5. Display Configuration ---
message(STATUS "Configuring for Platform: ${KIS_PLATFORM_ID}")
message(STATUS "--> Platform tags (filtering): ${KIS_PLATFORM_TAGS}")
if(KIS_ACTIVE_FEATURES)
    message(STATUS "--> Active features (filtering): ${KIS_ACTIVE_FEATURES}")
endif()
if(KIS_CONFIG_SUFFIX)
    message(STATUS "--> Config suffix (ABI): ${KIS_CONFIG_SUFFIX} (${KIS_CURRENT_VARIANT_ABI_GROUP} ABI group)")
else()
    message(STATUS "--> Config suffix (ABI): (default/release, ${KIS_CURRENT_VARIANT_ABI_GROUP} ABI group)")
endif()
message(STATUS "--> Install path suffix: ${KIS_PATH_SUFFIX}")
message(STATUS "--> Third-party libs will use: CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} (mapped from ${KIS_CURRENT_VARIANT_ABI_GROUP} ABI)")
message(STATUS "")