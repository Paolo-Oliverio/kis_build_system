# kis_build_system/modules/sdk_variants.cmake
#
# Defines configuration variants and their ABI compatibility groups.
#
# Configuration variants are different ways to build the SDK (e.g., release, profiling, debug)
# that may or may not be binary-compatible with each other.
#
# ABI COMPATIBILITY GROUPS:
# Configurations in the same ABI group can be safely linked together.
# Mixing configurations from different ABI groups will cause linker errors or runtime issues.

message(STATUS "Loading SDK configuration variant system...")

# =============================================================================
# ABI COMPATIBILITY GROUP DEFINITIONS
# =============================================================================

# RELEASE ABI Group: Optimized builds with optional instrumentation
# - release: Standard optimized build
# - profiling: Release build with profiling instrumentation
# These are ABI-compatible because they use the same:
#   - Optimization level (-O3)
#   - Standard library (release iterators)
#   - Memory layout (no debug padding)
set(KIS_ABI_GROUP_RELEASE "release;profiling" CACHE INTERNAL 
    "Config suffixes that belong to the RELEASE ABI group")

# DEBUG ABI Group: Debug builds with optional sanitizers
# - debug: Debug build with symbols and checks
# - asan: Debug build with AddressSanitizer
# These are ABI-compatible because they use the same:
#   - Optimization level (-O0/-Od)
#   - Debug iterators and checks
#   - Debug standard library
set(KIS_ABI_GROUP_DEBUG "debug;asan" CACHE INTERNAL 
    "Config suffixes that belong to the DEBUG ABI group")

# =============================================================================
# CONFIG -> ABI GROUP MAPPING
# =============================================================================

# Map each configuration suffix to its ABI group name
set(KIS_CONFIG_ABI_GROUP_release "RELEASE" CACHE INTERNAL "ABI group for release config")
set(KIS_CONFIG_ABI_GROUP_profiling "RELEASE" CACHE INTERNAL "ABI group for profiling config")
set(KIS_CONFIG_ABI_GROUP_debug "DEBUG" CACHE INTERNAL "ABI group for debug config")
set(KIS_CONFIG_ABI_GROUP_asan "DEBUG" CACHE INTERNAL "ABI group for asan config")

# Default/empty config suffix is considered 'release'
set(KIS_CONFIG_ABI_GROUP_ "RELEASE" CACHE INTERNAL "ABI group for default/release config")

# =============================================================================
# VARIANT METADATA
# =============================================================================

# Human-readable descriptions for each variant
set(KIS_VARIANT_DESC_release "Optimized release build" CACHE INTERNAL "")
set(KIS_VARIANT_DESC_profiling "Release with profiling instrumentation" CACHE INTERNAL "")
set(KIS_VARIANT_DESC_debug "Debug build with symbols and checks" CACHE INTERNAL "")
set(KIS_VARIANT_DESC_asan "Debug build with AddressSanitizer" CACHE INTERNAL "")

# List all known built-in variant names
set(KIS_BUILTIN_VARIANTS "release;profiling;debug;asan" CACHE INTERNAL 
    "Built-in configuration variants")

# All variants (built-in + custom, populated during configure)
set(KIS_ALL_VARIANTS "${KIS_BUILTIN_VARIANTS}" CACHE INTERNAL 
    "Complete list of all known configuration variants")

# =============================================================================
# CUSTOM VARIANT REGISTRATION
# =============================================================================

#
# kis_prescan_custom_variants
#
# Pre-scans all package manifests to discover custom variants BEFORE any
# package configuration. This allows packages to use custom variants defined
# by other packages, regardless of discovery order.
#
# Called once during superbuild initialization (PHASE 1).
#
function(kis_prescan_custom_variants)
    message(STATUS "Pre-scanning packages for custom variant definitions...")
    
    set(scanned_count 0)
    set(custom_variants_found "")
    
    # Find all kis.package.json files in the workspace using unified utility
    kis_glob_package_manifests(
        "${CMAKE_CURRENT_SOURCE_DIR}/kis_packages"
        package_manifests
    )
    
    foreach(manifest_file ${package_manifests})
        # Extract package name from path using utility
        kis_get_package_name_from_path("${manifest_file}" package_name)
        
        file(READ "${manifest_file}" manifest_content)
        
        # Check if it defines custom variants
        string(JSON custom_variants_json ERROR_VARIABLE err GET "${manifest_content}" "abi" "customVariants")
        if(NOT err AND custom_variants_json)
            # Register the custom variants immediately
            kis_register_package_custom_variants("${package_name}" "${custom_variants_json}")
            list(APPEND custom_variants_found "${package_name}")
            math(EXPR scanned_count "${scanned_count} + 1")
        endif()
    endforeach()
    
    if(custom_variants_found)
        message(STATUS "Found custom variants in ${scanned_count} package(s): ${custom_variants_found}")
    else()
        message(STATUS "No custom variants found (using built-in variants only)")
    endif()
endfunction()

#
# kis_register_package_custom_variants
#
# Registers custom variants defined by a package.
# Called during package configuration.
#
# Args:
#   package_name: Name of the package
#   custom_variants_json: JSON array string of variant objects
#
function(kis_register_package_custom_variants package_name custom_variants_json)
    if(NOT custom_variants_json)
        return()
    endif()

    string(JSON num_variants LENGTH "${custom_variants_json}")
    if(num_variants EQUAL 0)
        return()
    endif()
    
    math(EXPR last_idx "${num_variants} - 1")
    foreach(i RANGE ${last_idx})
        string(JSON variant_obj GET "${custom_variants_json}" ${i})
        string(JSON variant_name GET "${variant_obj}" "name")
        string(JSON abi_group GET "${variant_obj}" "abiGroup")
        string(JSON description GET "${variant_obj}" "description")
        
        if(NOT variant_name OR NOT abi_group)
            kis_collect_warning("Invalid custom variant object in package ${package_name}: must have 'name' and 'abiGroup'")
            continue()
        endif()

        if(NOT description)
            set(description "Custom variant ${variant_name}")
        endif()
        
        # Register the variant globally
        string(TOUPPER "${abi_group}" abi_group_upper)
        set(KIS_CONFIG_ABI_GROUP_${variant_name} "${abi_group_upper}" CACHE INTERNAL "")
        set(KIS_VARIANT_DESC_${variant_name} "${description}" CACHE INTERNAL "")
        
        # Add to the appropriate ABI group
        set(abi_group_var "KIS_ABI_GROUP_${abi_group_upper}")
        if(DEFINED ${abi_group_var})
            set(group_list "${${abi_group_var}}")
            if(NOT variant_name IN_LIST group_list)
                list(APPEND group_list "${variant_name}")
                set(${abi_group_var} "${group_list}" CACHE INTERNAL "")
            endif()
        else()
            message(WARNING "Unknown ABI group '${abi_group}' for variant '${variant_name}' in package ${package_name}")
        endif()
        
        # Add to global variants list
        get_property(all_variants CACHE KIS_ALL_VARIANTS PROPERTY VALUE)
        if(NOT variant_name IN_LIST all_variants)
            list(APPEND all_variants "${variant_name}")
            set(KIS_ALL_VARIANTS "${all_variants}" CACHE INTERNAL "")
            message(STATUS "Registered custom variant '${variant_name}' → ${abi_group_upper} group (from ${package_name})")
        endif()
    endforeach()
endfunction()

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

#
# kis_get_variant_abi_group
#
# Returns the ABI group name for a given configuration variant.
#
# Args:
#   variant_name: The configuration variant (e.g., "release", "profiling", "debug")
#   out_var: Output variable to store the ABI group name
#
function(kis_get_variant_abi_group variant_name out_var)
    # Normalize empty string to "release"
    if(NOT variant_name OR variant_name STREQUAL "")
        set(variant_name "release")
    endif()
    
    # Look up the ABI group for this variant
    set(abi_group_var "KIS_CONFIG_ABI_GROUP_${variant_name}")
    if(DEFINED ${abi_group_var})
        set(${out_var} "${${abi_group_var}}" PARENT_SCOPE)
    else()
        kis_collect_warning("Unknown configuration variant '${variant_name}'. Known variants: ${KIS_ALL_VARIANTS}")
        set(${out_var} "UNKNOWN" PARENT_SCOPE)
    endif()
endfunction()

#
# kis_variants_are_compatible
#
# Checks if two configuration variants are ABI-compatible.
#
# Args:
#   variant_a: First variant name
#   variant_b: Second variant name
#   out_var: Output variable (set to TRUE if compatible, FALSE otherwise)
#
function(kis_variants_are_compatible variant_a variant_b out_var)
    kis_get_variant_abi_group("${variant_a}" abi_group_a)
    kis_get_variant_abi_group("${variant_b}" abi_group_b)
    
    if(abi_group_a STREQUAL abi_group_b)
        set(${out_var} TRUE PARENT_SCOPE)
    else()
        set(${out_var} FALSE PARENT_SCOPE)
    endif()
endfunction()

#
# kis_get_current_variant_name
#
# Returns the current build's variant name based on KIS_CONFIG_SUFFIX.
# If KIS_CONFIG_SUFFIX is empty, returns "release".
#
function(kis_get_current_variant_name out_var)
    if(KIS_CONFIG_SUFFIX)
        set(${out_var} "${KIS_CONFIG_SUFFIX}" PARENT_SCOPE)
    else()
        set(${out_var} "release" PARENT_SCOPE)
    endif()
endfunction()

#
# kis_normalize_variant_name
#
# Converts empty string or "default" to "release".
#
function(kis_normalize_variant_name variant_name out_var)
    if(NOT variant_name OR variant_name STREQUAL "" OR variant_name STREQUAL "default")
        set(${out_var} "release" PARENT_SCOPE)
    else()
        set(${out_var} "${variant_name}" PARENT_SCOPE)
    endif()
endfunction()

#
# kis_get_fallback_variant
#
# Finds a compatible fallback variant from an ABI group.
# Priority: "release" for RELEASE group, "debug" for DEBUG group.
#
# Args:
#   abi_group: The ABI group name (e.g., "RELEASE", "DEBUG")
#   available_variants: List of available variants
#   out_var: Output variable for the fallback variant (empty if none found)
#
function(kis_get_fallback_variant abi_group available_variants out_var)
    # Get all variants in this ABI group
    set(group_var "KIS_ABI_GROUP_${abi_group}")
    if(NOT DEFINED ${group_var})
        set(${out_var} "" PARENT_SCOPE)
        return()
    endif()
    
    set(group_variants "${${group_var}}")
    
    # Priority 1: "release" for RELEASE group
    if(abi_group STREQUAL "RELEASE" AND "release" IN_LIST available_variants)
        set(${out_var} "release" PARENT_SCOPE)
        return()
    endif()
    
    # Priority 2: "debug" for DEBUG group
    if(abi_group STREQUAL "DEBUG" AND "debug" IN_LIST available_variants)
        set(${out_var} "debug" PARENT_SCOPE)
        return()
    endif()
    
    # Priority 3: First available variant from the ABI group
    foreach(variant ${group_variants})
        if(variant IN_LIST available_variants)
            set(${out_var} "${variant}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    
    # No fallback found
    set(${out_var} "" PARENT_SCOPE)
endfunction()

# =============================================================================
# DIAGNOSTIC OUTPUT
# =============================================================================

if(KIS_DIAGNOSTIC_MODE)
    message(STATUS "")
    message(STATUS "=== Configuration Variant System ===")
    message(STATUS "ABI Groups:")
    message(STATUS "  RELEASE: ${KIS_ABI_GROUP_RELEASE}")
    message(STATUS "  DEBUG:   ${KIS_ABI_GROUP_DEBUG}")
    message(STATUS "")
    message(STATUS "Current Build Variant:")
    kis_get_current_variant_name(_current_variant)
    kis_get_variant_abi_group("${_current_variant}" _current_abi_group)
    message(STATUS "  Variant:   ${_current_variant}")
    message(STATUS "  ABI Group: ${_current_abi_group}")
    message(STATUS "====================================")
    message(STATUS "")
endif()

message(STATUS "Configuration variant system loaded.")