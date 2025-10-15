# kis_build_system/modules/incremental_dependencies.cmake
#
# Smart incremental detection for third-party dependencies.
# Only re-fetches/re-builds dependencies when necessary.

# ==============================================================================
#           DEPENDENCY FINGERPRINTING
# ==============================================================================

#
# kis_compute_dependency_fingerprint
#
# Computes a fingerprint for a dependency based on:
#   1. GIT_REPOSITORY URL
#   2. GIT_TAG/GIT_COMMIT
#   3. URL (for non-git dependencies)
#   4. URL_HASH
#
# This fingerprint is used to detect if dependency configuration has changed.
#
function(kis_compute_dependency_fingerprint dep_name dep_args out_fingerprint_var)
    set(fingerprint_parts "")
    
    # Parse the dependency arguments
    set(git_repo "")
    set(git_tag "")
    set(url "")
    set(url_hash "")
    
    list(LENGTH dep_args args_len)
    set(i 0)
    while(i LESS args_len)
        list(GET dep_args ${i} key)
        math(EXPR i "${i} + 1")
        
        if(key STREQUAL "GIT_REPOSITORY" AND i LESS args_len)
            list(GET dep_args ${i} git_repo)
            math(EXPR i "${i} + 1")
        elseif(key STREQUAL "GIT_TAG" AND i LESS args_len)
            list(GET dep_args ${i} git_tag)
            math(EXPR i "${i} + 1")
        elseif(key STREQUAL "GIT_COMMIT" AND i LESS args_len)
            list(GET dep_args ${i} git_tag)  # Use commit as tag
            math(EXPR i "${i} + 1")
        elseif(key STREQUAL "URL" AND i LESS args_len)
            list(GET dep_args ${i} url)
            math(EXPR i "${i} + 1")
        elseif(key STREQUAL "URL_HASH" AND i LESS args_len)
            list(GET dep_args ${i} url_hash)
            math(EXPR i "${i} + 1")
        else()
            math(EXPR i "${i} + 1")
        endif()
    endwhile()
    
    # Build fingerprint from parsed values
    if(git_repo)
        list(APPEND fingerprint_parts "git:${git_repo}")
    endif()
    if(git_tag)
        list(APPEND fingerprint_parts "tag:${git_tag}")
    endif()
    if(url)
        list(APPEND fingerprint_parts "url:${url}")
    endif()
    if(url_hash)
        list(APPEND fingerprint_parts "hash:${url_hash}")
    endif()
    
    # Combine all parts
    list(JOIN fingerprint_parts "|" final_fingerprint)
    set(${out_fingerprint_var} "${final_fingerprint}" PARENT_SCOPE)
endfunction()

#
# kis_dependency_needs_fetch
#
# Determines if a dependency needs to be fetched/built by checking:
#   1. If source directory exists
#   2. If fingerprint has changed
#   3. If force rebuild is enabled
#
function(kis_dependency_needs_fetch dep_name dep_args out_needs_fetch)
    # Check 1: Force rebuild mode
    if(KIS_FORCE_DEPENDENCY_REBUILD)
        set(${out_needs_fetch} TRUE PARENT_SCOPE)
        return()
    endif()
    
    # Check 2: Check if already populated (source dir exists)
    # FetchContent uses FETCHCONTENT_BASE_DIR/_deps/<name>-src
    if(NOT DEFINED FETCHCONTENT_BASE_DIR)
        set(FETCHCONTENT_BASE_DIR "${CMAKE_BINARY_DIR}/_deps")
    endif()
    
    set(source_dir "${FETCHCONTENT_BASE_DIR}/${dep_name}-src")
    
    # Override with explicit SOURCE_DIR if provided
    list(FIND dep_args "SOURCE_DIR" source_dir_idx)
    if(source_dir_idx GREATER -1)
        math(EXPR value_idx "${source_dir_idx} + 1")
        list(GET dep_args ${value_idx} source_dir)
    endif()
    
    if(NOT EXISTS "${source_dir}")
        # Source doesn't exist - need to fetch
        message(STATUS "[INCREMENTAL] '${dep_name}' not found - will fetch")
        set(${out_needs_fetch} TRUE PARENT_SCOPE)
        return()
    endif()
    
    # Check 3: Compare fingerprints
    kis_compute_dependency_fingerprint("${dep_name}" "${dep_args}" current_fingerprint)
    
    set(cache_var "KIS_DEP_FINGERPRINT_${dep_name}")
    if(DEFINED CACHE{${cache_var}})
        set(cached_fingerprint "${${cache_var}}")
        
        if("${current_fingerprint}" STREQUAL "${cached_fingerprint}")
            # No changes detected - skip fetch
            message(STATUS "[INCREMENTAL] Skipping '${dep_name}' (already populated)")
            set(${out_needs_fetch} FALSE PARENT_SCOPE)
            return()
        else()
            # Fingerprint changed - need to re-fetch
            message(STATUS "[INCREMENTAL] Re-fetching '${dep_name}' (version/URL changed)")
        endif()
    else()
        # First run - fetch
        message(STATUS "[INCREMENTAL] First fetch for '${dep_name}'")
    endif()
    
    # Update cached fingerprint
    set(${cache_var} "${current_fingerprint}" CACHE INTERNAL "Fingerprint for ${dep_name}")
    
    set(${out_needs_fetch} TRUE PARENT_SCOPE)
endfunction()

# ==============================================================================
#           SMART FETCHCONTENT WRAPPER
# ==============================================================================

#
# kis_fetch_content_make_available_incremental
#
# Wrapper around FetchContent_MakeAvailable that only fetches/builds
# dependencies that have changed or don't exist.
#
# For dependencies that already exist with matching fingerprint:
#   - Skips FetchContent_MakeAvailable (saves time)
#   - Manually adds the source directory to access targets
#
function(kis_fetch_content_make_available_incremental dep_names_list)
    set(deps_to_fetch "")
    set(deps_to_load "")
    
    # Categorize dependencies
    foreach(dep_name ${dep_names_list})
        get_property(dep_args GLOBAL PROPERTY KIS_ARGS_${dep_name})
        
        kis_dependency_needs_fetch("${dep_name}" "${dep_args}" needs_fetch)
        
        if(needs_fetch)
            list(APPEND deps_to_fetch "${dep_name}")
        else()
            list(APPEND deps_to_load "${dep_name}")
        endif()
    endforeach()
    
    # Statistics
    list(LENGTH deps_to_fetch fetch_count)
    list(LENGTH deps_to_load load_count)
    
    if(load_count GREATER 0)
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "Incremental Dependency Fetch")
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        message(STATUS "  Dependencies to fetch:  ${fetch_count}")
        message(STATUS "  Dependencies to reuse:  ${load_count}")
        message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    endif()
    
    # Fetch new/changed dependencies
    if(deps_to_fetch)
        # First declare them
        foreach(dep_name ${deps_to_fetch})
            get_property(dep_args GLOBAL PROPERTY KIS_ARGS_${dep_name})
            FetchContent_Declare(${dep_name} ${dep_args})
        endforeach()
        
        # Then make available (this downloads and configures)
        FetchContent_MakeAvailable(${deps_to_fetch})
    endif()
    
    # Load existing dependencies without rebuilding
    if(deps_to_load)
        foreach(dep_name ${deps_to_load})
            get_property(dep_args GLOBAL PROPERTY KIS_ARGS_${dep_name})
            
            # Get source and binary directories
            if(NOT DEFINED FETCHCONTENT_BASE_DIR)
                set(FETCHCONTENT_BASE_DIR "${CMAKE_BINARY_DIR}/_deps")
            endif()
            
            set(source_dir "${FETCHCONTENT_BASE_DIR}/${dep_name}-src")
            set(binary_dir "${FETCHCONTENT_BASE_DIR}/${dep_name}-build")
            
            # Override with explicit directories if provided
            list(FIND dep_args "SOURCE_DIR" source_dir_idx)
            if(source_dir_idx GREATER -1)
                math(EXPR value_idx "${source_dir_idx} + 1")
                list(GET dep_args ${value_idx} source_dir)
            endif()
            
            list(FIND dep_args "BINARY_DIR" binary_dir_idx)
            if(binary_dir_idx GREATER -1)
                math(EXPR value_idx "${binary_dir_idx} + 1")
                list(GET dep_args ${value_idx} binary_dir)
            endif()
            
            # Check if already added to avoid duplicate add_subdirectory
            get_property(is_populated GLOBAL PROPERTY _FetchContent_${dep_name}_populated)
            
            if(NOT is_populated AND EXISTS "${source_dir}/CMakeLists.txt")
                # Manually add the dependency (equivalent to FetchContent_MakeAvailable but without fetch)
                message(STATUS "  -> Reusing existing '${dep_name}' from ${source_dir}")
                add_subdirectory("${source_dir}" "${binary_dir}" EXCLUDE_FROM_ALL)
                
                # Mark as populated to prevent FetchContent from trying to fetch it
                set_property(GLOBAL PROPERTY _FetchContent_${dep_name}_populated TRUE)
                set_property(GLOBAL PROPERTY _FetchContent_${dep_name}_sourceDir "${source_dir}")
                set_property(GLOBAL PROPERTY _FetchContent_${dep_name}_binaryDir "${binary_dir}")
            elseif(is_populated)
                message(STATUS "  -> Dependency '${dep_name}' already loaded")
            else()
                message(WARNING "  -> Cannot reuse '${dep_name}': source dir missing or invalid")
                # Fall back to normal fetch
                get_property(dep_args GLOBAL PROPERTY KIS_ARGS_${dep_name})
                FetchContent_Declare(${dep_name} ${dep_args})
                FetchContent_MakeAvailable(${dep_name})
            endif()
        endforeach()
    endif()
endfunction()

# ==============================================================================
#           STATISTICS AND UTILITIES
# ==============================================================================

#
# kis_clear_dependency_cache
#
# Clears all cached dependency fingerprints.
#
function(kis_clear_dependency_cache)
    get_cmake_property(cache_vars CACHE_VARIABLES)
    
    set(cleared_count 0)
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_DEP_FINGERPRINT_")
            unset(${var} CACHE)
            math(EXPR cleared_count "${cleared_count} + 1")
        endif()
    endforeach()
    
    if(cleared_count GREATER 0)
        message(STATUS "[INCREMENTAL] Cleared ${cleared_count} cached dependency fingerprints")
    endif()
endfunction()

#
# kis_show_dependency_cache
#
# Shows all cached dependency fingerprints (for debugging).
#
function(kis_show_dependency_cache)
    message(STATUS "")
    message(STATUS "Cached Dependency Fingerprints:")
    message(STATUS "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    get_cmake_property(cache_vars CACHE_VARIABLES)
    set(found_any FALSE)
    
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_DEP_FINGERPRINT_(.+)$")
            set(dep_name "${CMAKE_MATCH_1}")
            message(STATUS "  ${dep_name}:")
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
