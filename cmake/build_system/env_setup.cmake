# cmake/build_system/cache_setup.cmake
#
# This file is included automatically before the top-level project() command.
# Its purpose is to configure the build environment, including environment
# variables and the persistent cache for FetchContent.

# This guard ensures this logic only runs when our SDK is the top-level project.
if(PROJECT_IS_TOP_LEVEL)
    message(STATUS "Performing first-time environment setup...")

    # --- 1. Set KIS_SDK Environment Variable ---
    # Set an environment variable pointing to the root of the SDK.
    # This is useful for external scripts or tools run during the build.
    # Note: This only affects the current CMake process and its children.
    set(ENV{KIS_SDK} "${CMAKE_CURRENT_SOURCE_DIR}")
    message(STATUS "--> Set ENV{KIS_SDK} = ${CMAKE_CURRENT_SOURCE_DIR}")

    # --- 2. Intelligently Set KIS_DEPS_CACHE Environment Variable ---
    # If the user has not already defined a cache location, create a default one.
    # The "first to set it wins" principle applies.
    if(NOT DEFINED ENV{KIS_DEPS_CACHE})
        # Calculate the default path (e.g., /path/to/sdk/_deps_cache)
        get_filename_component(DEFAULT_CACHE_DIR "${CMAKE_BINARY_DIR}/../_deps_cache" ABSOLUTE)
        set(ENV{KIS_DEPS_CACHE} "${DEFAULT_CACHE_DIR}")
        message(STATUS "--> ENV{KIS_DEPS_CACHE} was not set, defaulting to: ${DEFAULT_CACHE_DIR}")
    else()
        message(STATUS "--> Using existing ENV{KIS_DEPS_CACHE} = $ENV{KIS_DEPS_CACHE}")
    endif()

    # --- 3. Configure CMake's FetchContent to use the cache ---
    # Now that ENV{KIS_DEPS_CACHE} is guaranteed to be set, use it to configure
    # FetchContent's persistent storage location.
    set(FETCHCONTENT_BASE_DIR "$ENV{KIS_DEPS_CACHE}" CACHE PATH "Persistent cache for dependencies")
    message(STATUS "--> FetchContent will use cache location: ${FETCHCONTENT_BASE_DIR}")

endif()