# kis_build_system/modules/cache_validation.cmake
#
# Provides cache variable validation to detect stale or misconfigured CMake cache.
# Helps users avoid common pitfalls like switching platforms or variants without
# cleaning the cache.

# ==============================================================================
#           CACHE STALENESS DETECTION
# ==============================================================================

#
# kis_check_cache_staleness
#
# Detects when the CMake cache contains stale configuration that conflicts with
# current user settings. This happens when:
#   - Platform changes (e.g., windows -> linux)
#   - Variant changes (e.g., release -> debug)
#   - CMake version changes
#   - Build tool changes (e.g., Ninja -> Unix Makefiles)
#
# Warnings are collected and displayed at the end of configuration.
#
function(kis_check_cache_staleness)
    # Only run staleness checks if cache already exists
    if(NOT EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt")
        return()
    endif()
    
    set(issues_found FALSE)
    
    # Check 1: Platform consistency
    if(DEFINED CACHE{KIS_PLATFORM_CACHED})
        if(NOT "${KIS_PLATFORM}" STREQUAL "${KIS_PLATFORM_CACHED}")
            kis_collect_warning(
                "Cache Staleness"
                "Platform changed from '${KIS_PLATFORM_CACHED}' to '${KIS_PLATFORM}' without clearing cache"
                "Delete build directory and reconfigure:\n     cmake --fresh -B build --preset <your_preset>"
            )
            set(issues_found TRUE)
        endif()
    else()
        # First run with new validation system - cache the platform
        set(KIS_PLATFORM_CACHED "${KIS_PLATFORM}" CACHE INTERNAL "Cached platform for staleness detection")
    endif()
    
    # Check 2: Variant consistency
    if(DEFINED CACHE{KIS_ACTIVE_VARIANTS_CACHED})
        # Convert lists to strings for comparison
        set(current_variants_str "${KIS_ACTIVE_VARIANTS}")
        list(SORT current_variants_str)
        list(JOIN current_variants_str ";" current_variants_sorted)
        
        set(cached_variants_str "${KIS_ACTIVE_VARIANTS_CACHED}")
        list(SORT cached_variants_str)
        list(JOIN cached_variants_str ";" cached_variants_sorted)
        
        if(NOT "${current_variants_sorted}" STREQUAL "${cached_variants_sorted}")
            kis_collect_warning(
                "Cache Staleness"
                "Active variants changed from '${KIS_ACTIVE_VARIANTS_CACHED}' to '${KIS_ACTIVE_VARIANTS}' without clearing cache"
                "Delete build directory and reconfigure:\n     cmake --fresh -B build --preset <your_preset>"
            )
            set(issues_found TRUE)
        endif()
    else()
        set(KIS_ACTIVE_VARIANTS_CACHED "${KIS_ACTIVE_VARIANTS}" CACHE INTERNAL "Cached variants for staleness detection")
    endif()
    
    # Check 3: CMake version consistency
    if(DEFINED CACHE{KIS_CMAKE_VERSION_CACHED})
        if(NOT "${CMAKE_VERSION}" STREQUAL "${KIS_CMAKE_VERSION_CACHED}")
            # Version changes are less critical, just inform the user
            message(STATUS "CMake version changed from ${KIS_CMAKE_VERSION_CACHED} to ${CMAKE_VERSION}")
            message(STATUS "Consider a fresh configuration if you encounter issues")
        endif()
    else()
        set(KIS_CMAKE_VERSION_CACHED "${CMAKE_VERSION}" CACHE INTERNAL "Cached CMake version for staleness detection")
    endif()
    
    # Check 4: Generator consistency
    if(DEFINED CACHE{KIS_GENERATOR_CACHED})
        if(NOT "${CMAKE_GENERATOR}" STREQUAL "${KIS_GENERATOR_CACHED}")
            kis_collect_warning(
                "Cache Staleness"
                "Generator changed from '${KIS_GENERATOR_CACHED}' to '${CMAKE_GENERATOR}' without clearing cache"
                "Delete build directory and reconfigure:\n     cmake --fresh -B build --preset <your_preset>"
            )
            set(issues_found TRUE)
        endif()
    else()
        set(KIS_GENERATOR_CACHED "${CMAKE_GENERATOR}" CACHE INTERNAL "Cached generator for staleness detection")
    endif()
    
    # Check 5: Source directory consistency (detects moved workspace)
    if(DEFINED CACHE{KIS_SOURCE_DIR_CACHED})
        if(NOT "${CMAKE_SOURCE_DIR}" STREQUAL "${KIS_SOURCE_DIR_CACHED}")
            kis_collect_warning(
                "Cache Staleness"
                "Source directory changed from '${KIS_SOURCE_DIR_CACHED}' to '${CMAKE_SOURCE_DIR}'"
                "This usually means the workspace was moved. Delete build directory and reconfigure:\n     cmake --fresh -B build --preset <your_preset>"
            )
            set(issues_found TRUE)
        endif()
    else()
        set(KIS_SOURCE_DIR_CACHED "${CMAKE_SOURCE_DIR}" CACHE INTERNAL "Cached source directory for staleness detection")
    endif()
    
    if(issues_found)
        message(STATUS "")
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "⚠️  CACHE STALENESS DETECTED")
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "Configuration changes detected that require a fresh build.")
        message(STATUS "Continuing may lead to build errors or unexpected behavior.")
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "")
    endif()
endfunction()

# ==============================================================================
#           ENVIRONMENT VALIDATION
# ==============================================================================

#
# kis_validate_environment
#
# Validates the build environment configuration for common issues:
#   - Missing required cache variables
#   - Conflicting settings
#   - Platform/compiler mismatches
#
function(kis_validate_environment)
    # Check 1: Verify required SDK variables are set
    set(required_vars
        KIS_PLATFORM
        KIS_ACTIVE_VARIANTS
        CMAKE_INSTALL_PREFIX
    )
    
    set(missing_vars "")
    foreach(var ${required_vars})
        if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
            list(APPEND missing_vars ${var})
        endif()
    endforeach()
    
    if(missing_vars)
        kis_collect_warning(
            "Environment Validation"
            "Required SDK variables not set: ${missing_vars}"
            "This indicates an incomplete build system initialization.\n     Report this issue with your CMakeLists.txt configuration."
        )
    endif()
    
    # Check 2: Verify install prefix is writable
    if(EXISTS "${CMAKE_INSTALL_PREFIX}")
        file(WRITE "${CMAKE_INSTALL_PREFIX}/.kis_write_test" "test")
        if(NOT EXISTS "${CMAKE_INSTALL_PREFIX}/.kis_write_test")
            kis_collect_warning(
                "Environment Validation"
                "Install prefix '${CMAKE_INSTALL_PREFIX}' is not writable"
                "Choose a different install location or run with appropriate permissions:\n     cmake -DCMAKE_INSTALL_PREFIX=<writable_path> ..."
            )
        else()
            file(REMOVE "${CMAKE_INSTALL_PREFIX}/.kis_write_test")
        endif()
    endif()
    
    # Check 3: Detect common misconfigurations
    if(WIN32 AND CMAKE_GENERATOR MATCHES "Unix Makefiles")
        kis_collect_warning(
            "Environment Validation"
            "Unix Makefiles generator detected on Windows - this usually indicates misconfiguration"
            "Use a Windows-appropriate generator:\n     cmake -G \"Visual Studio 17 2022\" ...\n     cmake -G \"Ninja\" ..."
        )
    endif()
    
    if(UNIX AND CMAKE_GENERATOR MATCHES "Visual Studio")
        kis_collect_warning(
            "Environment Validation"
            "Visual Studio generator detected on Unix - this usually indicates misconfiguration"
            "Use a Unix-appropriate generator:\n     cmake -G \"Unix Makefiles\" ...\n     cmake -G \"Ninja\" ..."
        )
    endif()
    
    # Check 4: Warn about in-source builds
    if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_BINARY_DIR}")
        kis_collect_warning(
            "Environment Validation"
            "In-source build detected - this pollutes the source tree"
            "Use an out-of-source build:\n     cmake -B build\n     cmake --build build"
        )
    endif()
endfunction()

# ==============================================================================
#           DIAGNOSTIC UTILITIES
# ==============================================================================

#
# kis_dump_cache_variables
#
# Dumps all CMake cache variables to the console for debugging.
# Only enabled when KIS_DIAGNOSTIC_MODE is ON.
#
function(kis_dump_cache_variables)
    if(NOT KIS_DIAGNOSTIC_MODE)
        return()
    endif()
    
    message(STATUS "")
    message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    message(STATUS "CACHE VARIABLE DUMP (KIS_DIAGNOSTIC_MODE=ON)")
    message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    get_cmake_property(cache_vars CACHE_VARIABLES)
    list(SORT cache_vars)
    
    foreach(var ${cache_vars})
        # Filter to only show KIS_ prefixed variables and key CMake variables
        if(var MATCHES "^KIS_" OR var MATCHES "^CMAKE_(INSTALL|BUILD|SOURCE|BINARY|GENERATOR)")
            get_property(var_type CACHE ${var} PROPERTY TYPE)
            message(STATUS "${var} (${var_type}) = ${${var}}")
        endif()
    endforeach()
    
    message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    message(STATUS "")
endfunction()

#
# kis_report_cache_size
#
# Reports the size of the CMake cache for diagnostic purposes.
#
function(kis_report_cache_size)
    if(EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt")
        file(SIZE "${CMAKE_BINARY_DIR}/CMakeCache.txt" cache_size)
        math(EXPR cache_size_kb "${cache_size} / 1024")
        message(STATUS "CMake cache size: ${cache_size_kb} KB")
    endif()
endfunction()
