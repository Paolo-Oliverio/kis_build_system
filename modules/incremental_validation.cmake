# kis_build_system/modules/incremental_validation.cmake
#
# Smart incremental package detection and validation.
# Only re-validates packages when necessary, but with multiple safety checks
# to ensure active development isn't hindered.

# ==============================================================================
#           CHANGE DETECTION
# ==============================================================================

#
# kis_compute_package_fingerprint
#
# Computes a fingerprint for a package based on:
#   1. Manifest file content (kis.package.cmake)
#   2. CMakeLists.txt modification time
#   3. Source file count (to detect new/deleted files)
#   4. Header file count
#   5. Subdirectory structure
#
# This fingerprint is used to detect if a package has changed since last configure.
#
function(kis_compute_package_fingerprint package_path out_fingerprint_var)
    set(fingerprint_parts "")
    
    # 1. Manifest content hash (most important - tracks dependency changes)
    set(manifest_file "${package_path}/kis.package.cmake")
    if(EXISTS "${manifest_file}")
        file(READ "${manifest_file}" manifest_content)
        string(MD5 manifest_hash "${manifest_content}")
        list(APPEND fingerprint_parts "manifest:${manifest_hash}")
    else()
        list(APPEND fingerprint_parts "manifest:none")
    endif()
    
    # 2. CMakeLists.txt modification time (tracks build logic changes)
    set(cmakelists_file "${package_path}/CMakeLists.txt")
    if(EXISTS "${cmakelists_file}")
        file(TIMESTAMP "${cmakelists_file}" cmakelists_time "%Y%m%d%H%M%S")
        list(APPEND fingerprint_parts "cmake:${cmakelists_time}")
    endif()
    
    # 3. Source file count (detects added/removed .cpp/.c files)
    file(GLOB_RECURSE source_files 
        "${package_path}/*.cpp"
        "${package_path}/*.c"
        "${package_path}/*.cc"
        "${package_path}/*.cxx"
    )
    list(LENGTH source_files source_count)
    list(APPEND fingerprint_parts "sources:${source_count}")
    
    # 4. Header file count (detects added/removed .h/.hpp files)
    file(GLOB_RECURSE header_files 
        "${package_path}/*.h"
        "${package_path}/*.hpp"
        "${package_path}/*.hxx"
    )
    list(LENGTH header_files header_count)
    list(APPEND fingerprint_parts "headers:${header_count}")
    
    # 5. Directory structure (detects new subdirectories like src/, include/, platform/)
    file(GLOB subdirs RELATIVE "${package_path}" "${package_path}/*")
    set(dir_list "")
    foreach(subdir ${subdirs})
        if(IS_DIRECTORY "${package_path}/${subdir}")
            list(APPEND dir_list "${subdir}")
        endif()
    endforeach()
    list(SORT dir_list)
    list(JOIN dir_list "," dirs_str)
    list(APPEND fingerprint_parts "dirs:${dirs_str}")
    
    # Combine all parts into final fingerprint
    list(JOIN fingerprint_parts "|" final_fingerprint)
    set(${out_fingerprint_var} "${final_fingerprint}" PARENT_SCOPE)
endfunction()

#
# kis_package_needs_validation
#
# Determines if a package needs re-validation by comparing its current
# fingerprint with the cached fingerprint from the previous configure.
#
# Returns TRUE if:
#   - No cached fingerprint exists (first run)
#   - Fingerprint has changed
#   - Force validation mode is enabled
#   - Development mode is enabled (KIS_INCREMENTAL_SKIP_ACTIVE_DEV)
#
function(kis_package_needs_validation package_path out_needs_validation)
    kis_get_package_name_from_path("${package_path}" package_name)
    
    # Check 1: Force validation mode (user override)
    if(KIS_FORCE_FULL_VALIDATION)
        set(${out_needs_validation} TRUE PARENT_SCOPE)
        return()
    endif()
    
    # Check 2: Development mode - skip validation for packages with recent changes
    # This is CRITICAL for active development workflow
    if(KIS_INCREMENTAL_SKIP_ACTIVE_DEV)
        set(cmakelists_file "${package_path}/CMakeLists.txt")
        if(EXISTS "${cmakelists_file}")
            file(TIMESTAMP "${cmakelists_file}" file_time "%s")
            string(TIMESTAMP current_time "%s")
            math(EXPR time_diff "${current_time} - ${file_time}")
            
            # If modified within last hour (3600 seconds), always validate
            if(time_diff LESS 3600)
                message(STATUS "[INCREMENTAL] '${package_name}' modified recently - forcing validation")
                set(${out_needs_validation} TRUE PARENT_SCOPE)
                return()
            endif()
        endif()
    endif()
    
    # Check 3: Compare fingerprints
    kis_compute_package_fingerprint("${package_path}" current_fingerprint)
    
    # Retrieve cached fingerprint from previous configure
    set(cache_var "KIS_PKG_FINGERPRINT_${package_name}")
    if(DEFINED CACHE{${cache_var}})
        set(cached_fingerprint "${${cache_var}}")
        
        if("${current_fingerprint}" STREQUAL "${cached_fingerprint}")
            # No changes detected
            set(${out_needs_validation} FALSE PARENT_SCOPE)
            message(STATUS "[INCREMENTAL] Skipping validation for '${package_name}' (unchanged)")
            return()
        else()
            # Changes detected
            message(STATUS "[INCREMENTAL] Re-validating '${package_name}' (changed)")
        endif()
    else()
        # First run or cache cleared
        message(STATUS "[INCREMENTAL] First validation for '${package_name}'")
    endif()
    
    # Update cached fingerprint
    set(${cache_var} "${current_fingerprint}" CACHE INTERNAL "Fingerprint for ${package_name}")
    
    set(${out_needs_validation} TRUE PARENT_SCOPE)
endfunction()

# ==============================================================================
#           VALIDATION WRAPPER
# ==============================================================================

#
# kis_validate_package_if_needed
#
# Smart validation wrapper that only validates if the package has changed.
# Used by discovery.cmake to replace unconditional kis_validate_package_manifest().
#
function(kis_validate_package_if_needed package_path)
    # Skip incremental validation if disabled
    if(NOT KIS_ENABLE_INCREMENTAL_VALIDATION)
        kis_validate_package_manifest("${package_path}")
        return()
    endif()
    
    # Check if validation is needed
    kis_package_needs_validation("${package_path}" needs_validation)
    
    if(needs_validation)
        kis_validate_package_manifest("${package_path}")
        
        # Update statistics
        kis_increment_validation_stat(validated)
    else()
        # Update statistics
        kis_increment_validation_stat(skipped)
    endif()
endfunction()

# ==============================================================================
#           STATISTICS TRACKING
# ==============================================================================

#
# kis_init_validation_stats
#
# Initializes incremental validation statistics tracking.
#
function(kis_init_validation_stats)
    set_property(GLOBAL PROPERTY KIS_VALIDATION_STATS_VALIDATED 0)
    set_property(GLOBAL PROPERTY KIS_VALIDATION_STATS_SKIPPED 0)
endfunction()

#
# kis_increment_validation_stat
#
# Increments a validation statistic counter.
#
function(kis_increment_validation_stat stat_name)
    get_property(current_value GLOBAL PROPERTY KIS_VALIDATION_STATS_${stat_name})
    if(NOT current_value)
        set(current_value 0)
    endif()
    math(EXPR new_value "${current_value} + 1")
    set_property(GLOBAL PROPERTY KIS_VALIDATION_STATS_${stat_name} ${new_value})
endfunction()

#
# kis_report_validation_stats
#
# Reports incremental validation statistics at end of configure.
#
function(kis_report_validation_stats)
    if(NOT KIS_ENABLE_INCREMENTAL_VALIDATION)
        return()
    endif()
    
    get_property(validated GLOBAL PROPERTY KIS_VALIDATION_STATS_VALIDATED)
    get_property(skipped GLOBAL PROPERTY KIS_VALIDATION_STATS_SKIPPED)
    
    if(NOT validated)
        set(validated 0)
    endif()
    if(NOT skipped)
        set(skipped 0)
    endif()
    
    math(EXPR total "${validated} + ${skipped}")
    
    if(total GREATER 0)
        message(STATUS "")
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "Incremental Validation Summary")
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "  Packages validated:  ${validated}")
        message(STATUS "  Packages skipped:    ${skipped}")
        
        if(skipped GREATER 0)
            math(EXPR skip_percent "(${skipped} * 100) / ${total}")
            message(STATUS "  Time saved:          ~${skip_percent}% of validation time")
        endif()
        
        if(KIS_FORCE_FULL_VALIDATION)
            message(STATUS "  Mode:                Full validation (forced)")
        elseif(KIS_INCREMENTAL_SKIP_ACTIVE_DEV)
            message(STATUS "  Mode:                Smart (skips active dev)")
        else()
            message(STATUS "  Mode:                Standard incremental")
        endif()
        
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "")
    endif()
endfunction()

# ==============================================================================
#           CACHE MANAGEMENT
# ==============================================================================

#
# kis_clear_validation_cache
#
# Clears all cached package fingerprints.
# Useful when you want to force full re-validation.
#
function(kis_clear_validation_cache)
    # Get all cache variables
    get_cmake_property(cache_vars CACHE_VARIABLES)
    
    # Remove all KIS_PKG_FINGERPRINT_* variables
    set(cleared_count 0)
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_PKG_FINGERPRINT_")
            unset(${var} CACHE)
            math(EXPR cleared_count "${cleared_count} + 1")
        endif()
    endforeach()
    
    if(cleared_count GREATER 0)
        message(STATUS "[INCREMENTAL] Cleared ${cleared_count} cached package fingerprints")
    endif()
endfunction()

#
# kis_show_validation_cache
#
# Shows all cached package fingerprints (for debugging).
#
function(kis_show_validation_cache)
    message(STATUS "")
    message(STATUS "Cached Package Fingerprints:")
    message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    get_cmake_property(cache_vars CACHE_VARIABLES)
    set(found_any FALSE)
    
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_PKG_FINGERPRINT_(.+)$")
            set(package_name "${CMAKE_MATCH_1}")
            message(STATUS "  ${package_name}:")
            message(STATUS "    ${${var}}")
            set(found_any TRUE)
        endif()
    endforeach()
    
    if(NOT found_any)
        message(STATUS "  (none cached yet)")
    endif()
    
    message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    message(STATUS "")
endfunction()
