# kis_build_system/modules/cache.cmake
#
# Centralized caching system for the KIS build system.
#
# This module provides in-memory caching for expensive operations:
# - JSON manifest parsing
# - Platform compatibility checks
# - Manifest fingerprinting (hash-based change detection)
#
# FEATURES:
# - Content-based cache keys (SHA256 hashing)
# - Cache hit/miss tracing with KIS_CACHE_DEBUG
# - Automatic cache invalidation on file changes
# - Memory-efficient storage using CMake CACHE INTERNAL

# =============================================================================
# CACHE DEBUG TRACING
# =============================================================================

option(KIS_CACHE_DEBUG "Enable detailed cache hit/miss tracing" OFF)

macro(_cache_trace)
    if(KIS_CACHE_DEBUG)
        message(STATUS "[CACHE] ${ARGN}")
    endif()
endmacro()

macro(_cache_hit CACHE_TYPE KEY)
    _cache_trace("✓ HIT  [${CACHE_TYPE}] ${KEY}")
endmacro()

macro(_cache_miss CACHE_TYPE KEY)
    _cache_trace("✗ MISS [${CACHE_TYPE}] ${KEY}")
endmacro()

macro(_cache_store CACHE_TYPE KEY)
    _cache_trace("→ STORE [${CACHE_TYPE}] ${KEY}")
endmacro()

# =============================================================================
# MANIFEST WATCHING (AUTO-RECONFIGURE ON CHANGE)
# =============================================================================

#
# kis_cache_watch_manifest
#
# Registers a manifest file with CMake's dependency tracking system.
# This causes automatic reconfiguration when the manifest changes.
#
# Args:
#   manifest_file: Path to kis.package.json to watch
#
function(kis_cache_watch_manifest manifest_file)
    if(NOT EXISTS "${manifest_file}")
        return()
    endif()
    
    # Use CMAKE_CONFIGURE_DEPENDS to register the dependency
    # CMake will track this file and trigger reconfiguration on changes
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${manifest_file}")
    
    _cache_trace("👁 WATCH  ${manifest_file}")
endfunction()

# =============================================================================
# FINGERPRINTING (HASH-BASED CHANGE DETECTION)
# =============================================================================

#
# kis_compute_file_fingerprint
#
# Computes a SHA256 hash of a file's contents for change detection.
# This is more reliable than timestamp-based checks.
#
# Args:
#   file_path: Absolute path to the file
#   out_var: Output variable to store the hash
#
function(kis_compute_file_fingerprint file_path out_var)
    if(NOT EXISTS "${file_path}")
        set(${out_var} "FILE_NOT_FOUND" PARENT_SCOPE)
        return()
    endif()
    
    file(SHA256 "${file_path}" file_hash)
    set(${out_var} "${file_hash}" PARENT_SCOPE)
endfunction()

#
# kis_compute_content_fingerprint
#
# Computes a SHA256 hash of string content.
# Useful for caching results based on input parameters.
#
# Args:
#   content: String content to hash
#   out_var: Output variable to store the hash
#
function(kis_compute_content_fingerprint content out_var)
    string(SHA256 content_hash "${content}")
    set(${out_var} "${content_hash}" PARENT_SCOPE)
endfunction()

# =============================================================================
# JSON MANIFEST CACHE
# =============================================================================

# Cache structure: KIS_MANIFEST_CACHE_<fingerprint>_<field>
# Fields: NAME, VERSION, TYPE, FEATURES, PLATFORMS, etc.

#
# kis_cache_get_manifest
#
# Retrieves a cached manifest by file path and fingerprint.
# Returns TRUE if cached and valid, FALSE if cache miss.
#
# Args:
#   manifest_file: Path to kis.package.json
#   out_valid: Output TRUE if cache hit, FALSE if miss
#
# Side effect: Sets MANIFEST_* variables in CURRENT scope if cache hit
#
function(kis_cache_get_manifest manifest_file out_valid)
    # Compute current fingerprint
    kis_compute_file_fingerprint("${manifest_file}" current_fp)
    
    if(current_fp STREQUAL "FILE_NOT_FOUND")
        set(${out_valid} FALSE PARENT_SCOPE)
        return()
    endif()
    
    # Check if we have a cached fingerprint
    set(cached_fp "${KIS_MANIFEST_FP_${manifest_file}}")
    
    if(NOT cached_fp OR NOT cached_fp STREQUAL current_fp)
        _cache_miss("MANIFEST" "${manifest_file}")
        set(${out_valid} FALSE PARENT_SCOPE)
        return()
    endif()
    
    # Cache hit - restore all manifest variables to PARENT_SCOPE
    _cache_hit("MANIFEST" "${manifest_file}")
    
    set(manifest_vars NAME VERSION TYPE DESCRIPTION CATEGORY SEARCH_TAGS OVERRIDES 
                      PLATFORMS PLATFORM_TAGS PLATFORM_EXCLUDES REQUIRES_TAGS EXCLUDES_TAGS 
                      ABI_VARIANT SUPPORTED_VARIANTS CUSTOM_VARIANTS 
                      KIS_DEPENDENCIES TPL_DEPENDENCIES FEATURES)
    
    foreach(var ${manifest_vars})
        set(cached_value "${KIS_MANIFEST_CACHE_${current_fp}_${var}}")
        # Always set the variable, even if empty, to properly restore state
        set(MANIFEST_${var} "${cached_value}" PARENT_SCOPE)
    endforeach()
    
    set(${out_valid} TRUE PARENT_SCOPE)
endfunction()

#
# kis_cache_store_manifest
#
# Stores parsed manifest data in the cache with fingerprint.
#
# Args:
#   manifest_file: Path to kis.package.json
#
# Expects: MANIFEST_* variables to be set in current scope
#
function(kis_cache_store_manifest manifest_file)
    # Compute fingerprint
    kis_compute_file_fingerprint("${manifest_file}" fingerprint)
    
    if(fingerprint STREQUAL "FILE_NOT_FOUND")
        return()
    endif()
    
    _cache_store("MANIFEST" "${manifest_file}")
    
    # Store fingerprint
    set("KIS_MANIFEST_FP_${manifest_file}" "${fingerprint}" CACHE INTERNAL 
        "Fingerprint for ${manifest_file}")
    
    # Store all manifest variables
    set(manifest_vars NAME VERSION TYPE DESCRIPTION CATEGORY SEARCH_TAGS OVERRIDES 
                      PLATFORMS PLATFORM_TAGS PLATFORM_EXCLUDES REQUIRES_TAGS EXCLUDES_TAGS 
                      ABI_VARIANT SUPPORTED_VARIANTS CUSTOM_VARIANTS 
                      KIS_DEPENDENCIES TPL_DEPENDENCIES FEATURES)
    
    foreach(var ${manifest_vars})
        if(DEFINED MANIFEST_${var})
            # --- FIX: Sanitize value before caching to prevent newline warnings ---
            set(value_to_cache "${MANIFEST_${var}}")
            string(REPLACE "\n" " " value_to_cache "${value_to_cache}")
            set("KIS_MANIFEST_CACHE_${fingerprint}_${var}" "${value_to_cache}" 
                CACHE INTERNAL "Cached ${var} for ${manifest_file}")
        else()
            # Explicitly unset to handle empty values correctly
            unset("KIS_MANIFEST_CACHE_${fingerprint}_${var}" CACHE)
        endif()
    endforeach()
endfunction()

#
# kis_cache_invalidate_manifest
#
# Invalidates the cache for a specific manifest file.
#
function(kis_cache_invalidate_manifest manifest_file)
    _cache_trace("✗ INVALIDATE [MANIFEST] ${manifest_file}")
    
    get_property(cached_fp CACHE "KIS_MANIFEST_FP_${manifest_file}" PROPERTY VALUE)
    
    if(cached_fp)
        set(manifest_vars NAME VERSION TYPE DESCRIPTION CATEGORY SEARCH_TAGS OVERRIDES 
                          PLATFORMS PLATFORM_TAGS PLATFORM_EXCLUDES REQUIRES_TAGS EXCLUDES_TAGS 
                          ABI_VARIANT SUPPORTED_VARIANTS CUSTOM_VARIANTS 
                          KIS_DEPENDENCIES TPL_DEPENDENCIES FEATURES)
        
        foreach(var ${manifest_vars})
            unset("KIS_MANIFEST_CACHE_${cached_fp}_${var}" CACHE)
        endforeach()
    endif()
    
    unset("KIS_MANIFEST_FP_${manifest_file}" CACHE)
endfunction()

# =============================================================================
# PLATFORM COMPATIBILITY CACHE
# =============================================================================

# Cache structure: KIS_PLATFORM_COMPAT_<hash>
# Hash is computed from: package_path + platform + tags

#
# kis_cache_get_platform_compatibility
#
# Retrieves cached platform compatibility result.
#
# Args:
#   package_path: Path to the package
#   platform: Platform identifier (e.g., "windows-x64")
#   tags: List of platform tags
#   out_cached: Output TRUE if cached, FALSE if miss
#   out_compatible: Output compatibility result (only valid if out_cached=TRUE)
#   out_error: Output error message (only valid if out_cached=TRUE)
#
function(kis_cache_get_platform_compatibility package_path platform tags out_cached out_compatible out_error)
    # Compute cache key from inputs
    set(cache_input "${package_path}|${platform}|${tags}")
    kis_compute_content_fingerprint("${cache_input}" cache_key)
    
    # Check manifest fingerprint first - invalidate if manifest changed
    set(manifest_file "${package_path}/kis.package.json")
    kis_compute_file_fingerprint("${manifest_file}" current_manifest_fp)
    
    set(cached_manifest_fp "${KIS_PLATFORM_COMPAT_FP_${cache_key}}")
    
    if(NOT cached_manifest_fp OR NOT cached_manifest_fp STREQUAL current_manifest_fp)
        _cache_miss("PLATFORM_COMPAT" "${package_path} @ ${platform}")
        set(${out_cached} FALSE PARENT_SCOPE)
        return()
    endif()
    
    # Retrieve cached compatibility result
    set(cached_compat "${KIS_PLATFORM_COMPAT_${cache_key}}")
    set(cached_error "${KIS_PLATFORM_COMPAT_ERR_${cache_key}}")
    
    if(NOT DEFINED cached_compat)
        _cache_miss("PLATFORM_COMPAT" "${package_path} @ ${platform}")
        set(${out_cached} FALSE PARENT_SCOPE)
        return()
    endif()
    
    _cache_hit("PLATFORM_COMPAT" "${package_path} @ ${platform}")
    set(${out_cached} TRUE PARENT_SCOPE)
    set(${out_compatible} "${cached_compat}" PARENT_SCOPE)
    set(${out_error} "${cached_error}" PARENT_SCOPE)
endfunction()

#
# kis_cache_store_platform_compatibility
#
# Stores platform compatibility check result in cache.
#
# Args:
#   package_path: Path to the package
#   platform: Platform identifier
#   tags: List of platform tags
#   compatible: Compatibility result (TRUE/FALSE)
#   error_msg: Error message (empty if compatible)
#
function(kis_cache_store_platform_compatibility package_path platform tags compatible error_msg)
    # Compute cache key
    set(cache_input "${package_path}|${platform}|${tags}")
    kis_compute_content_fingerprint("${cache_input}" cache_key)
    
    # Store manifest fingerprint for invalidation detection
    set(manifest_file "${package_path}/kis.package.json")
    kis_compute_file_fingerprint("${manifest_file}" manifest_fp)
    
    _cache_store("PLATFORM_COMPAT" "${package_path} @ ${platform}")
    
    set("KIS_PLATFORM_COMPAT_FP_${cache_key}" "${manifest_fp}" CACHE INTERNAL
        "Manifest fingerprint for platform compat cache")
    set("KIS_PLATFORM_COMPAT_${cache_key}" "${compatible}" CACHE INTERNAL
        "Compatibility result for ${package_path}")
    set("KIS_PLATFORM_COMPAT_ERR_${cache_key}" "${error_msg}" CACHE INTERNAL
        "Error message for ${package_path}")
endfunction()

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

#
# kis_cache_clear_all
#
# Clears all KIS caches. Useful for forcing a clean rebuild.
#
function(kis_cache_clear_all)
    message(STATUS "[CACHE] Clearing all caches...")
    
    # Get all cache variables
    get_cmake_property(cache_vars CACHE_VARIABLES)
    
    set(cleared_count 0)
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_(MANIFEST|PLATFORM)_")
            unset(${var} CACHE)
            math(EXPR cleared_count "${cleared_count} + 1")
        endif()
    endforeach()
    
    message(STATUS "[CACHE] Cleared ${cleared_count} cache entries")
endfunction()

#
# kis_cache_get_stats
#
# Reports cache statistics for debugging.
#
function(kis_cache_get_stats)
    get_cmake_property(cache_vars CACHE_VARIABLES)
    
    set(manifest_count 0)
    set(platform_count 0)
    
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_MANIFEST_FP_")
            math(EXPR manifest_count "${manifest_count} + 1")
        elseif(var MATCHES "^KIS_PLATFORM_COMPAT_[^F]")
            math(EXPR platform_count "${platform_count} + 1")
        endif()
    endforeach()
    
    message(STATUS "[CACHE STATS]")
    message(STATUS "  Cached manifests:          ${manifest_count}")
    message(STATUS "  Cached platform checks:    ${platform_count}")
    message(STATUS "  Total cache entries:       ${manifest_count} + ${platform_count}")
endfunction()

# =============================================================================
# INITIALIZATION
# =============================================================================

if(KIS_CACHE_DEBUG)
    message(STATUS "[CACHE] Debug tracing enabled")
endif()

# Option to clear cache on configure
option(KIS_CACHE_CLEAR "Clear all caches before configuration" OFF)
mark_as_advanced(KIS_CACHE_CLEAR)

if(KIS_CACHE_CLEAR)
    kis_cache_clear_all()
    set(KIS_CACHE_CLEAR OFF CACHE BOOL "Clear all caches before configuration" FORCE)
endif()