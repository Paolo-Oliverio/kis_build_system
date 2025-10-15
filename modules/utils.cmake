# kis_build_system/modules/utils.cmake
#
# Common utility functions used across the KIS build system.
# These helpers reduce duplication and centralize commonly-used patterns.

#
# kis_regex_escape
#
# Escapes all regex metacharacters in a string for safe use in
# CMake's MATCHES or string(REGEX ...) operations.
#
# Example:
#   kis_regex_escape(escaped "https://github.com/user/repo.git")
#   # escaped => "https://github\\.com/user/repo\\.git"
#
function(kis_regex_escape OUTPUT_VAR INPUT_STRING)
    # Must escape backslash first or subsequent replacements will double-escape it.
    set(result "${INPUT_STRING}")

    # Order matters: escape '\' before everything else.
    string(REPLACE "\\" "\\\\" result "${result}")

    # Now escape all other regex metacharacters.
    foreach(char "." "*" "+" "?" "^" "$" "|" "(" ")" "[" "]" "{" "}")
        string(REPLACE "${char}" "\\${char}" result "${result}")
    endforeach()

    set(${OUTPUT_VAR} "${result}" PARENT_SCOPE)
endfunction()

#
# kis_is_url_trusted
#
# Checks if a URL starts with any of the trusted prefixes.
# Returns TRUE or FALSE via the OUTPUT_VAR.
#
# Usage:
#   kis_is_url_trusted(is_safe "https://github.com/Paolo-Oliverio/repo.git" "${KIS_TRUSTED_URL_PREFIXES}")
#   if(is_safe)
#       # proceed
#   endif()
#
function(kis_is_url_trusted OUTPUT_VAR URL PREFIX_LIST)
    set(result FALSE)
    foreach(prefix ${PREFIX_LIST})
        kis_regex_escape(prefix_escaped "${prefix}")
        if(URL MATCHES "^${prefix_escaped}")
            set(result TRUE)
            break()
        endif()
    endforeach()
    set(${OUTPUT_VAR} ${result} PARENT_SCOPE)
endfunction()


#
# kis_message_fatal_actionable
#
# Formats and prints a fatal error message with a clear structure:
# emoji + title, detailed message, and actionable hints.
#
# Usage:
#   kis_message_fatal_actionable(
#       "Security Error: Untrusted URL"
#       "The package URL is not in the trusted list."
#       "Add the prefix to KIS_TRUSTED_URL_PREFIXES in sdk_options.cmake"
#   )
#
function(kis_message_fatal_actionable TITLE MESSAGE HINT)
    message(FATAL_ERROR
        "\n[ERROR] ${TITLE}\n"
        "  ${MESSAGE}\n"
        "  \n"
        "  [SOLUTION] How to fix:\n"
        "     ${HINT}\n"
    )
endfunction()


#
# kis_message_warning_actionable
#
# Similar to kis_message_fatal_actionable but for warnings.
# Collects warnings for summary display at end of configuration.
#
function(kis_message_warning_actionable TITLE MESSAGE HINT)
    # Collect for summary
    kis_collect_warning("${TITLE}" "${MESSAGE}" "${HINT}")
    
    # Also print immediately for real-time feedback
    message(WARNING
        "\n[WARNING] ${TITLE}\n"
        "  ${MESSAGE}\n"
        "  \n"
        "  [TIP] Suggestion:\n"
        "     ${HINT}\n"
    )
endfunction()

#
# kis_message_verbose
#
# Prints a STATUS message only if KIS_VERBOSE_BUILD is enabled.
# Use this for detailed logging that clutters normal builds.
#
function(kis_message_verbose)
    if(KIS_VERBOSE_BUILD)
        message(STATUS ${ARGN})
    endif()
endfunction()

#
# kis_message_info
#
# Prints an important STATUS message (always shown).
# Use for key information users should see.
#
function(kis_message_info)
    message(STATUS ${ARGN})
endfunction()


#
# kis_list_to_string
#
# Converts a CMake list to a human-readable string with a separator.
# Useful for debug output.
#
# Usage:
#   kis_list_to_string(output_str "${my_list}" ", ")
#
function(kis_list_to_string OUTPUT_VAR INPUT_LIST SEPARATOR)
    string(REPLACE ";" "${SEPARATOR}" result "${INPUT_LIST}")
    set(${OUTPUT_VAR} "${result}" PARENT_SCOPE)
endfunction()


#
# kis_parse_triplet_list
#
# Parses a list of triplets (name;url;tag format) and extracts them.
# Used for PACKAGE_DEPENDENCIES parsing.
#
# Usage:
#   kis_parse_triplet_list(parsed_list "${PACKAGE_DEPENDENCIES}")
#   # parsed_list contains: name1 url1 tag1 name2 url2 tag2 ...
#
function(kis_parse_triplet_list OUTPUT_VAR INPUT_LIST CONTEXT_NAME)
    set(result "")
    list(LENGTH INPUT_LIST num_items)
    set(i 0)
    
    while(i LESS num_items)
        list(GET INPUT_LIST ${i} item_name)
        math(EXPR i "${i} + 1")
        
        # Skip if it looks like a URL (malformed entry)
        if(item_name MATCHES "^https?://")
            kis_collect_warning("Skipping malformed entry in ${CONTEXT_NAME}: '${item_name}' looks like a URL")
            continue()
        endif()
        
        # Get URL
        set(item_url "")
        if(i LESS num_items)
            list(GET INPUT_LIST ${i} potential_url)
            if(potential_url MATCHES "^https?://")
                set(item_url "${potential_url}")
                math(EXPR i "${i} + 1")
            endif()
        endif()
        
        # Get TAG
        set(item_tag "")
        if(i LESS num_items AND item_url)
            list(GET INPUT_LIST ${i} item_tag)
            math(EXPR i "${i} + 1")
        endif()
        
        # Validate we have all three components
        if(item_url AND item_tag)
            list(APPEND result "${item_name}" "${item_url}" "${item_tag}")
        elseif(NOT item_url)
            # Could be old-style format (just names), include name only
            list(APPEND result "${item_name}")
        endif()
    endwhile()
    
    set(${OUTPUT_VAR} ${result} PARENT_SCOPE)
endfunction()


#
# kis_build_override_map_parse
#
# Parses the KIS_DEPENDENCY_OVERRIDES variable into separate key/value lists.
# Returns map_keys and map_values via output variables.
#
# Usage:
#   kis_build_override_map_parse(keys_out values_out)
#
function(kis_build_override_map_parse KEYS_OUTPUT VALUES_OUTPUT)
    if(NOT DEFINED KIS_DEPENDENCY_OVERRIDES)
        set(${KEYS_OUTPUT} "" PARENT_SCOPE)
        set(${VALUES_OUTPUT} "" PARENT_SCOPE)
        return()
    endif()

    set(keys "")
    set(values "")
    set(is_key TRUE)
    foreach(item ${KIS_DEPENDENCY_OVERRIDES})
        if(is_key)
            list(APPEND keys ${item})
            set(is_key FALSE)
        else()
            list(APPEND values ${item})
            set(is_key TRUE)
        endif()
    endforeach()

    list(LENGTH keys num_keys)
    list(LENGTH values num_values)
    if(NOT num_keys EQUAL num_values)
        kis_collect_warning("KIS_DEPENDENCY_OVERRIDES list is malformed (odd number of items). Ignoring overrides.")
        set(${KEYS_OUTPUT} "" PARENT_SCOPE)
        set(${VALUES_OUTPUT} "" PARENT_SCOPE)
        return()
    endif()

    set(${KEYS_OUTPUT} ${keys} PARENT_SCOPE)
    set(${VALUES_OUTPUT} ${values} PARENT_SCOPE)
endfunction()


#
# kis_read_package_manifest
#
# Reads a package's kis.package.cmake file and extracts all metadata fields.
# Returns data via output variables with MANIFEST_ prefix.
#
# Usage:
#   kis_read_package_manifest("/path/to/package")
#   # Sets variables in PARENT_SCOPE:
#   #   MANIFEST_NAME, MANIFEST_VERSION, MANIFEST_DESCRIPTION,
#   #   MANIFEST_PLATFORMS, MANIFEST_PLATFORM_TAGS, MANIFEST_PLATFORM_EXCLUDES,
#   #   MANIFEST_DEPENDENCIES, MANIFEST_OVERRIDES
#
function(kis_read_package_manifest PACKAGE_PATH)
    set(manifest_file "${PACKAGE_PATH}/kis.package.cmake")
    
    if(NOT EXISTS "${manifest_file}")
        message(FATAL_ERROR "Package manifest not found: ${manifest_file}")
    endif()
    
    # Clear all output variables
    unset(PACKAGE_NAME)
    unset(PACKAGE_VERSION)
    unset(PACKAGE_DESCRIPTION)
    unset(PACKAGE_PLATFORMS)
    unset(PACKAGE_PLATFORM_TAGS)
    unset(PACKAGE_PLATFORM_EXCLUDES)
    unset(PACKAGE_REQUIRES_TAGS)
    unset(PACKAGE_EXCLUDES_TAGS)
    unset(PACKAGE_DEPENDENCIES)
    unset(PACKAGE_OVERRIDES)
    unset(PACKAGE_FEATURES)
    unset(PACKAGE_FEATURE_REQUIREMENTS)
    unset(PACKAGE_ABI_VARIANT)
    unset(PACKAGE_CONFIG_SUFFIX)
    
    # Include the manifest (sets PACKAGE_* variables in this scope)
    include("${manifest_file}")
    
    # Export to parent scope with MANIFEST_ prefix
    if(DEFINED PACKAGE_NAME)
        set(MANIFEST_NAME "${PACKAGE_NAME}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_VERSION)
        set(MANIFEST_VERSION "${PACKAGE_VERSION}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_DESCRIPTION)
        set(MANIFEST_DESCRIPTION "${PACKAGE_DESCRIPTION}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_PLATFORMS)
        set(MANIFEST_PLATFORMS "${PACKAGE_PLATFORMS}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_PLATFORM_TAGS)
        set(MANIFEST_PLATFORM_TAGS "${PACKAGE_PLATFORM_TAGS}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_PLATFORM_EXCLUDES)
        set(MANIFEST_PLATFORM_EXCLUDES "${PACKAGE_PLATFORM_EXCLUDES}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_REQUIRES_TAGS)
        set(MANIFEST_REQUIRES_TAGS "${PACKAGE_REQUIRES_TAGS}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_EXCLUDES_TAGS)
        set(MANIFEST_EXCLUDES_TAGS "${PACKAGE_EXCLUDES_TAGS}" PARENT_SCOPE)
    endif()
    # New simplified fields
    if(DEFINED PACKAGE_FEATURES)
        set(MANIFEST_FEATURES "${PACKAGE_FEATURES}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_FEATURE_REQUIREMENTS)
        # Backwards-compat: export legacy feature requirements under MANIFEST_FEATURES
        set(MANIFEST_FEATURES "${PACKAGE_FEATURE_REQUIREMENTS}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_ABI_VARIANT)
        set(MANIFEST_ABI_VARIANT "${PACKAGE_ABI_VARIANT}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_CONFIG_SUFFIX)
        set(MANIFEST_CONFIG_SUFFIX "${PACKAGE_CONFIG_SUFFIX}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_DEPENDENCIES)
        set(MANIFEST_DEPENDENCIES "${PACKAGE_DEPENDENCIES}" PARENT_SCOPE)
    endif()
    if(DEFINED PACKAGE_OVERRIDES)
        set(MANIFEST_OVERRIDES "${PACKAGE_OVERRIDES}" PARENT_SCOPE)
    endif()
endfunction()


#
# kis_validate_package_platform
#
# Validates that a package's platform constraints are satisfied by the current build configuration.
# Now supports both platform tags AND build configuration tags (tools, editor, demo, etc.)
# Checks PACKAGE_PLATFORMS, PACKAGE_PLATFORM_TAGS, PACKAGE_PLATFORM_EXCLUDES (legacy).
# Also checks PACKAGE_REQUIRES_TAGS and PACKAGE_EXCLUDES_TAGS (new unified system).
#
# Parameters:
#   PACKAGE_NAME - Name of the package being validated
#   PACKAGE_PATH - Path to the package directory
#   CURRENT_PLATFORM - Current KIS_PLATFORM value
#   CURRENT_TAGS - Current KIS_ACTIVE_TAGS list (platform + build tags)
#
# Returns: Sets IS_COMPATIBLE to TRUE or FALSE in PARENT_SCOPE
#          Sets ERROR_MESSAGE if incompatible (for user feedback)
#
function(kis_validate_package_platform PACKAGE_NAME PACKAGE_PATH CURRENT_PLATFORM CURRENT_TAGS OUTPUT_COMPATIBLE OUTPUT_ERROR)
    # Read the manifest
    kis_read_package_manifest("${PACKAGE_PATH}")
    
    set(is_compatible TRUE)
    set(error_msg "")
    
    # === LEGACY PLATFORM FIELDS (backward compatibility) ===
    
    # Check 1: PACKAGE_PLATFORM_EXCLUDES (explicit exclusions)
    if(DEFINED MANIFEST_PLATFORM_EXCLUDES)
        # Check if current platform is explicitly excluded
        list(FIND MANIFEST_PLATFORM_EXCLUDES "${CURRENT_PLATFORM}" platform_excluded_idx)
        if(NOT platform_excluded_idx EQUAL -1)
            set(is_compatible FALSE)
            kis_list_to_string(excluded_str "${MANIFEST_PLATFORM_EXCLUDES}" ", ")
            set(error_msg "Package '${PACKAGE_NAME}' explicitly excludes platform: ${CURRENT_PLATFORM}\n  Excluded platforms: ${excluded_str}")
        endif()
        
        # Check if any current tags are excluded
        if(is_compatible)
            foreach(tag ${CURRENT_TAGS})
                list(FIND MANIFEST_PLATFORM_EXCLUDES "${tag}" tag_excluded_idx)
                if(NOT tag_excluded_idx EQUAL -1)
                    set(is_compatible FALSE)
                    kis_list_to_string(excluded_str "${MANIFEST_PLATFORM_EXCLUDES}" ", ")
                    set(error_msg "Package '${PACKAGE_NAME}' explicitly excludes platform tag: ${tag}\n  Excluded platforms: ${excluded_str}")
                    break()
                endif()
            endforeach()
        endif()
    endif()
    
    # Check 2: PACKAGE_PLATFORMS (must match at least one)
    if(is_compatible AND DEFINED MANIFEST_PLATFORMS)
        list(FIND MANIFEST_PLATFORMS "${CURRENT_PLATFORM}" platform_found_idx)
        if(platform_found_idx EQUAL -1)
            set(is_compatible FALSE)
            kis_list_to_string(required_str "${MANIFEST_PLATFORMS}" ", ")
            set(error_msg "Package '${PACKAGE_NAME}' requires one of these platforms: ${required_str}\n  Current platform: ${CURRENT_PLATFORM}")
        endif()
    endif()
    
    # Check 3: PACKAGE_PLATFORM_TAGS (must have at least one matching tag)
    if(is_compatible AND DEFINED MANIFEST_PLATFORM_TAGS)
        set(has_matching_tag FALSE)
        foreach(required_tag ${MANIFEST_PLATFORM_TAGS})
            list(FIND CURRENT_TAGS "${required_tag}" tag_found_idx)
            if(NOT tag_found_idx EQUAL -1)
                set(has_matching_tag TRUE)
                break()
            endif()
        endforeach()
        
        if(NOT has_matching_tag)
            set(is_compatible FALSE)
            kis_list_to_string(required_tags_str "${MANIFEST_PLATFORM_TAGS}" ", ")
            kis_list_to_string(current_tags_str "${CURRENT_TAGS}" ", ")
            set(error_msg "Package '${PACKAGE_NAME}' requires at least one of these platform tags: ${required_tags_str}\n  Current tags: ${current_tags_str}")
        endif()
    endif()
    
    # === NEW UNIFIED TAG SYSTEM ===
    
    # Check 4: PACKAGE_EXCLUDES_TAGS (unified exclusions)
    if(is_compatible AND DEFINED MANIFEST_EXCLUDES_TAGS)
        foreach(excluded_tag ${MANIFEST_EXCLUDES_TAGS})
            list(FIND CURRENT_TAGS "${excluded_tag}" tag_excluded_idx)
            if(NOT tag_excluded_idx EQUAL -1)
                set(is_compatible FALSE)
                kis_list_to_string(excluded_str "${MANIFEST_EXCLUDES_TAGS}" ", ")
                kis_list_to_string(current_str "${CURRENT_TAGS}" ", ")
                set(error_msg "Package '${PACKAGE_NAME}' excludes tag: ${excluded_tag}\n  Excluded tags: ${excluded_str}\n  Current tags: ${current_str}")
                break()
            endif()
        endforeach()
    endif()
    
    # Check 5: PACKAGE_REQUIRES_TAGS (must have ALL required tags)
    if(is_compatible AND DEFINED MANIFEST_REQUIRES_TAGS)
        set(missing_tags "")
        foreach(required_tag ${MANIFEST_REQUIRES_TAGS})
            list(FIND CURRENT_TAGS "${required_tag}" tag_found_idx)
            if(tag_found_idx EQUAL -1)
                list(APPEND missing_tags "${required_tag}")
            endif()
        endforeach()
        
        if(missing_tags)
            set(is_compatible FALSE)
            kis_list_to_string(missing_str "${missing_tags}" ", ")
            kis_list_to_string(required_str "${MANIFEST_REQUIRES_TAGS}" ", ")
            kis_list_to_string(current_str "${CURRENT_TAGS}" ", ")
            set(error_msg "Package '${PACKAGE_NAME}' requires ALL of these tags: ${required_str}\n  Missing tags: ${missing_str}\n  Current tags: ${current_str}\n\n  [TIP] To enable missing tags:\n     - Use preset: cmake --preset dev-full\n     - Or set manually: -DKIS_BUILD_TAGS=\"${required_str}\"\n     - Or modify CMakePresets.json to add tags")
        endif()
    endif()
    
    # Return results
    set(${OUTPUT_COMPATIBLE} ${is_compatible} PARENT_SCOPE)
    set(${OUTPUT_ERROR} "${error_msg}" PARENT_SCOPE)
endfunction()


#
# kis_get_package_platform_preference
#
# Determines the preferred platform subdirectory for a package based on its manifest.
# Returns empty string if package has no platform preference (should go in root kis_packages/).
#
# Usage:
#   kis_get_package_platform_preference(preferred_platform "/path/to/package")
#   # Returns: "windows", "android", "linux", or "" for common packages
#
function(kis_get_package_platform_preference OUTPUT_VAR PACKAGE_PATH)
    kis_read_package_manifest("${PACKAGE_PATH}")
    
    set(result "")
    
    # If package specifies exactly one platform, use that as preference
    if(DEFINED MANIFEST_PLATFORMS)
        list(LENGTH MANIFEST_PLATFORMS num_platforms)
        if(num_platforms EQUAL 1)
            list(GET MANIFEST_PLATFORMS 0 single_platform)
            set(result "${single_platform}")
        endif()
    endif()
    
    set(${OUTPUT_VAR} "${result}" PARENT_SCOPE)
endfunction()
