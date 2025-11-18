# kis_build_system/modules/utils.cmake
#
# Common utility functions used across the KIS build system.
# These helpers reduce duplication and centralize commonly-used patterns.

#
# kis_get_package_name_from_path
#
# Extracts the package name from a full package path or manifest path.
#
function(kis_get_package_name_from_path path out_name_var)
    # If path is a file, get its directory first
    if(NOT IS_DIRECTORY "${path}")
        get_filename_component(path "${path}" DIRECTORY)
    endif()
    
    get_filename_component(pkg_name "${path}" NAME)
    set(${out_name_var} ${pkg_name} PARENT_SCOPE)
endfunction()

#
# kis_regex_escape
#
# Escapes all regex metacharacters in a string for safe use in
# CMake's MATCHES or string(REGEX ...) operations.
#
function(kis_regex_escape OUTPUT_VAR INPUT_STRING)
    set(result "${INPUT_STRING}")
    string(REPLACE "\\" "\\\\" result "${result}")
    foreach(char "." "*" "+" "?" "^" "$" "|" "(" ")" "[" "]" "{" "}")
        string(REPLACE "${char}" "\\${char}" result "${result}")
    endforeach()
    set(${OUTPUT_VAR} "${result}" PARENT_SCOPE)
endfunction()

#
# kis_is_url_trusted
#
# Checks if a URL starts with any of the trusted prefixes.
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
# kis_message_fatal_actionable (MACRO)
#
# Formats and prints a fatal error message with a clear structure.
# In test mode, it sets a variable instead of halting.
#
macro(kis_message_fatal_actionable TITLE MESSAGE HINT)
    cmake_parse_arguments(ARG "" "PACKAGE;FILE" "" ${ARGN})

    set(context "")
    if(ARG_PACKAGE)
        string(APPEND context "[Package: ${ARG_PACKAGE}] ")
    endif()
    if(ARG_FILE)
        string(APPEND context "[File: ${ARG_FILE}]")
    endif()

    if(context)
        set(TITLE "${context} ${TITLE}")
    endif()
    
    if(KIS_TESTING_MODE)
        # FIX: Use a GLOBAL PROPERTY to make the error visible across all function scopes.
        set_property(GLOBAL PROPERTY KIS_TEST_LAST_ERROR "FATAL: ${TITLE}\n  ${MESSAGE}\n  Hint: ${HINT}")
    else()
        message(FATAL_ERROR
            "\n[ERROR] ${TITLE}\n"
            "  ${MESSAGE}\n"
            "  \n"
            "  [SOLUTION] How to fix:\n"
            "     ${HINT}\n"
        )
    endif()
endmacro()


#
# kis_message_warning_actionable (MACRO)
#
# Similar to kis_message_fatal_actionable but for warnings.
#
macro(kis_message_warning_actionable TITLE MESSAGE HINT)
    cmake_parse_arguments(ARG "" "PACKAGE;FILE" "" ${ARGN})

    set(context "")
    if(ARG_PACKAGE)
        string(APPEND context "[Package: ${ARG_PACKAGE}] ")
    endif()
    if(ARG_FILE)
        string(APPEND context "[File: ${ARG_FILE}]")
    endif()
    
    if(context)
        set(TITLE "${context} ${TITLE}")
    endif()

    kis_collect_warning("${TITLE}" "${MESSAGE}" "${HINT}")
    message(WARNING
        "\n[WARNING] ${TITLE}\n"
        "  ${MESSAGE}\n"
        "  \n"
        "  [TIP] Suggestion:\n"
        "     ${HINT}\n"
    )
endmacro()

#
# kis_message_verbose
#
# Prints a STATUS message only if KIS_VERBOSE_BUILD is enabled.
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
#
function(kis_message_info)
    message(STATUS ${ARGN})
endfunction()


#
# kis_list_to_string
#
# Converts a CMake list to a human-readable string with a separator.
#
function(kis_list_to_string OUTPUT_VAR INPUT_LIST SEPARATOR)
    string(REPLACE ";" "${SEPARATOR}" result "${INPUT_LIST}")
    set(${OUTPUT_VAR} "${result}" PARENT_SCOPE)
endfunction()


#
# kis_build_override_map_parse
#
# Parses the KIS_DEPENDENCY_OVERRIDES variable into separate key/value lists.
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

# --- Helper FUNCTION to parse an array of strings with robust error handling ---
function(_json_get_array out_var JSON_STRING KEY _PACKAGE_PATH _MANIFEST_FILE)
    string(JSON arr_str ERROR_VARIABLE get_err GET "${JSON_STRING}" "${KEY}")
    
    # FIX: If the key is not found, do nothing. The variable will remain unset.
    if(get_err)
        return()
    endif()
    
    set(list_val "") # Default to an empty list if the key exists
    string(JSON arr_type ERROR_VARIABLE type_err TYPE "${arr_str}")
    if(type_err OR NOT arr_type STREQUAL "ARRAY")
        if(NOT arr_str STREQUAL "")
            kis_get_package_name_from_path("${_PACKAGE_PATH}" pkg_name)
            if(type_err)
                set(type_desc "not valid JSON")
            else()
                set(type_desc "a '${arr_type}'")
            endif()
            kis_message_fatal_actionable("Invalid Manifest: Not an Array" "The value for key '${KEY}' must be a JSON array, but is ${type_desc}." "Value found was: '${arr_str}'\n  Example of a correct array: \"${KEY}\": [\"value1\", \"value2\"]" PACKAGE ${pkg_name} FILE ${_MANIFEST_FILE})
        endif()
    else()
        string(JSON len LENGTH "${arr_str}")
        if(len GREATER 0)
            math(EXPR last_idx "${len} - 1")
            foreach(i RANGE ${last_idx})
                string(JSON item ERROR_VARIABLE item_err GET "${arr_str}" ${i})
                if(item_err)
                    kis_get_package_name_from_path("${_PACKAGE_PATH}" pkg_name)
                    kis_message_fatal_actionable("Invalid Manifest: Array Item Parse Error" "Could not parse item at index ${i} for key '${KEY}'. Reason: ${item_err}" "Array content being parsed: ${arr_str}" PACKAGE ${pkg_name} FILE ${_MANIFEST_FILE})
                else()
                    list(APPEND list_val "${item}")
                endif()
            endforeach()
        endif()
    endif()

    # Set the final value (which will be an empty string if the array was empty)
    set(${out_var} "${list_val}" PARENT_SCOPE)
endfunction()

# Helper macro to set MANIFEST_* variables in both current and parent scope
# This is needed so kis_cache_store_manifest can see the variables
macro(_set_manifest_var var_name value)
    set(MANIFEST_${var_name} "${value}")
    set(MANIFEST_${var_name} "${value}" PARENT_SCOPE)
endmacro()

#
# kis_read_package_manifest_json (FUNCTION)
#
# Reads a package's kis.package.json file and extracts all metadata fields
# into MANIFEST_* variables in the CALLER'S scope.
#
function(kis_read_package_manifest_json)
    set(options)
    set(oneValueArgs PACKAGE_PATH)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(package_root "")
    if(ARG_PACKAGE_PATH)
        set(package_root "${ARG_PACKAGE_PATH}")
    # --- THE CHANGE: Prioritize the explicit context variable ---
    elseif(DEFINED CACHE{_KIS_CTX_CURRENT_PACKAGE_ROOT})
        set(package_root "${_KIS_CTX_CURRENT_PACKAGE_ROOT}") # This is now set reliably by the caller
    else()
        set(package_root "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()

    set(manifest_file "${package_root}/kis.package.json")
    
    if(NOT EXISTS "${manifest_file}")
        message(FATAL_ERROR "Package manifest not found: ${manifest_file}")
    endif()

    # Register manifest with CMake's dependency tracking for auto-reconfigure on change
    kis_cache_watch_manifest("${manifest_file}")

    # Try to retrieve from cache first
    kis_cache_get_manifest("${manifest_file}" cache_valid)
    if(cache_valid)
        # Cache hit - MANIFEST_* variables are already set in current scope by cache function
        # Propagate each one individually to PARENT_SCOPE
        if(DEFINED MANIFEST_NAME)
            set(MANIFEST_NAME "${MANIFEST_NAME}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_VERSION)
            set(MANIFEST_VERSION "${MANIFEST_VERSION}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_TYPE)
            set(MANIFEST_TYPE "${MANIFEST_TYPE}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_DESCRIPTION)
            set(MANIFEST_DESCRIPTION "${MANIFEST_DESCRIPTION}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_CATEGORY)
            set(MANIFEST_CATEGORY "${MANIFEST_CATEGORY}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_SEARCH_TAGS)
            set(MANIFEST_SEARCH_TAGS "${MANIFEST_SEARCH_TAGS}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_OVERRIDES)
            set(MANIFEST_OVERRIDES "${MANIFEST_OVERRIDES}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_PLATFORMS)
            set(MANIFEST_PLATFORMS "${MANIFEST_PLATFORMS}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_PLATFORM_TAGS)
            set(MANIFEST_PLATFORM_TAGS "${MANIFEST_PLATFORM_TAGS}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_PLATFORM_EXCLUDES)
            set(MANIFEST_PLATFORM_EXCLUDES "${MANIFEST_PLATFORM_EXCLUDES}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_REQUIRES_TAGS)
            set(MANIFEST_REQUIRES_TAGS "${MANIFEST_REQUIRES_TAGS}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_EXCLUDES_TAGS)
            set(MANIFEST_EXCLUDES_TAGS "${MANIFEST_EXCLUDES_TAGS}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_ABI_VARIANT)
            set(MANIFEST_ABI_VARIANT "${MANIFEST_ABI_VARIANT}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_SUPPORTED_VARIANTS)
            set(MANIFEST_SUPPORTED_VARIANTS "${MANIFEST_SUPPORTED_VARIANTS}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_CUSTOM_VARIANTS)
            set(MANIFEST_CUSTOM_VARIANTS "${MANIFEST_CUSTOM_VARIANTS}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_KIS_DEPENDENCIES)
            set(MANIFEST_KIS_DEPENDENCIES "${MANIFEST_KIS_DEPENDENCIES}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_TPL_DEPENDENCIES)
            set(MANIFEST_TPL_DEPENDENCIES "${MANIFEST_TPL_DEPENDENCIES}" PARENT_SCOPE)
        endif()
        if(DEFINED MANIFEST_FEATURES)
            set(MANIFEST_FEATURES "${MANIFEST_FEATURES}" PARENT_SCOPE)
        endif()
        return()
    endif()

    # Cache miss - parse the manifest
    file(READ "${manifest_file}" manifest_content)
    
    if(manifest_content MATCHES "^\\xef\\xbb\\bf")
        string(SUBSTRING "${manifest_content}" 3 -1 manifest_content)
    endif()

    set(manifest_vars NAME VERSION TYPE DESCRIPTION CATEGORY SEARCH_TAGS OVERRIDES PLATFORMS PLATFORM_TAGS PLATFORM_EXCLUDES REQUIRES_TAGS EXCLUDES_TAGS ABI_VARIANT SUPPORTED_VARIANTS CUSTOM_VARIANTS KIS_DEPENDENCIES TPL_DEPENDENCIES FEATURES)
    foreach(var ${manifest_vars})
        unset(MANIFEST_${var} PARENT_SCOPE)
    endforeach()

    #message(STATUS "[DEBUG][JSON] Reading manifest from: ${manifest_file}")

    string(JSON content_type ERROR_VARIABLE type_err TYPE "${manifest_content}")
    if(type_err)
        #message(STATUS "[DEBUG][JSON] ERROR during initial TYPE check: ${type_err}")
        kis_get_package_name_from_path("${package_root}" pkg_name)
        kis_message_fatal_actionable(
            "Invalid JSON in '${manifest_file}'" 
            "Manifest content is not valid JSON. Reason: ${type_err}\n  File: ${manifest_file}" 
            "Ensure the file is well-formed JSON. Check for:\n     - Missing braces or brackets\n     - Trailing commas\n     - Invalid escape sequences\n     - BOM or encoding issues"
            PACKAGE ${pkg_name} 
            FILE ${manifest_file}
        )
        message(STATUS "[DEBUG][JSON] Exiting after fatal error macro.")
        return() 
    endif()

    #message(STATUS "[DEBUG][JSON] Manifest content is valid JSON of type '${content_type}'")

    if(NOT content_type STREQUAL "OBJECT")
        kis_get_package_name_from_path("${package_root}" pkg_name)
        kis_message_fatal_actionable(
            "Invalid JSON in '${manifest_file}'" 
            "Manifest content is not a valid JSON object. Top-level type is '${content_type}'.\n  File: ${manifest_file}" 
            "Ensure the file starts with '{' and ends with '}'." 
            PACKAGE ${pkg_name} 
            FILE ${manifest_file}
        )
    else()
        # JSON is valid, proceed with parsing
        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "name")
        if(NOT err)
            _set_manifest_var(NAME "${val}")
        endif()
        
        # ... (rest of the parsing logic is unchanged) ...
        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "version")
        if(NOT err)
            _set_manifest_var(VERSION "${val}")
        endif()

        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "type")
        if(NOT err)
            _set_manifest_var(TYPE "${val}")
        endif()

        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "description")
        if(NOT err)
            _set_manifest_var(DESCRIPTION "${val}")
        endif()

        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "category")
        if(NOT err)
            _set_manifest_var(CATEGORY "${val}")
        endif()

    _json_get_array(temp_search_tags "${manifest_content}" "searchTags" "${package_root}" "${manifest_file}")
        if(DEFINED temp_search_tags)
            _set_manifest_var(SEARCH_TAGS "${temp_search_tags}")
        endif()
        _json_get_array(temp_overrides "${manifest_content}" "overrides" "${package_root}" "${manifest_file}")
        if(DEFINED temp_overrides)
            _set_manifest_var(OVERRIDES "${temp_overrides}")
        endif()
        _json_get_array(temp_features "${manifest_content}" "features" "${package_root}" "${manifest_file}")
        if(DEFINED temp_features)
            _set_manifest_var(FEATURES "${temp_features}")
        endif()

        string(JSON platform_obj ERROR_VARIABLE err GET "${manifest_content}" "platform")
        if(NOT err)
            # --- THIS IS THE FIX ---
            # Check if platform_obj is actually a JSON object before parsing it.
            # An empty string is not a valid object.
            string(JSON platform_obj_type TYPE "${platform_obj}")
            if(platform_obj_type STREQUAL "OBJECT")
                _json_get_array(temp_platforms "${platform_obj}" "platforms" "${package_root}" "${manifest_file}")
                if(DEFINED temp_platforms)
                    _set_manifest_var(PLATFORMS "${temp_platforms}")
                endif()
                _json_get_array(temp_platform_tags "${platform_obj}" "tags" "${package_root}" "${manifest_file}")
                if(DEFINED temp_platform_tags)
                    _set_manifest_var(PLATFORM_TAGS "${temp_platform_tags}")
                endif()
                _json_get_array(temp_platform_excludes "${platform_obj}" "excludes" "${package_root}" "${manifest_file}")
                if(DEFINED temp_platform_excludes)
                    _set_manifest_var(PLATFORM_EXCLUDES "${temp_platform_excludes}")
                endif()
                _json_get_array(temp_requires_tags "${platform_obj}" "requiresTags" "${package_root}" "${manifest_file}")
                if(DEFINED temp_requires_tags)
                    _set_manifest_var(REQUIRES_TAGS "${temp_requires_tags}")
                endif()
                _json_get_array(temp_excludes_tags "${platform_obj}" "excludesTags" "${package_root}" "${manifest_file}")
                if(DEFINED temp_excludes_tags)
                    _set_manifest_var(EXCLUDES_TAGS "${temp_excludes_tags}")
                endif()
            endif()
            # --- END OF FIX ---
        endif()

        # Apply the same fix for the 'abi' and 'dependencies' objects
        string(JSON abi_obj ERROR_VARIABLE err GET "${manifest_content}" "abi")
        if(NOT err)
            string(JSON abi_obj_type TYPE "${abi_obj}")
            if(abi_obj_type STREQUAL "OBJECT")
                string(JSON val ERROR_VARIABLE err_v GET "${abi_obj}" "variant")
                if(NOT err_v)
                    _set_manifest_var(ABI_VARIANT "${val}")
                endif()
                _json_get_array(temp_supported_variants "${abi_obj}" "supportedVariants" "${package_root}" "${manifest_file}")
                if(DEFINED temp_supported_variants)
                    _set_manifest_var(SUPPORTED_VARIANTS "${temp_supported_variants}")
                endif()
                string(JSON val ERROR_VARIABLE err_c GET "${abi_obj}" "customVariants")
                if(NOT err_c)
                    _set_manifest_var(CUSTOM_VARIANTS "${val}")
                endif()
            endif()
        endif()

        string(JSON deps_obj ERROR_VARIABLE err GET "${manifest_content}" "dependencies")
        if(NOT err)
            string(JSON deps_obj_type TYPE "${deps_obj}")
            if(deps_obj_type STREQUAL "OBJECT")
                string(JSON val ERROR_VARIABLE err_k GET "${deps_obj}" "kis")
                if(NOT err_k)
                    _set_manifest_var(KIS_DEPENDENCIES "${val}")
                    kis_message_verbose("[MANIFEST] Read KIS_DEPENDENCIES: ${val}")
                endif()
                string(JSON val ERROR_VARIABLE err_t GET "${deps_obj}" "thirdParty")
                if(NOT err_t)
                    _set_manifest_var(TPL_DEPENDENCIES "${val}")
                    kis_message_verbose("[MANIFEST] Read TPL_DEPENDENCIES: ${val}")
                else()
                    kis_message_verbose("[MANIFEST] No thirdParty dependencies (error: ${err_t})")
                endif()
            endif()
        endif()
    endif()
    
    # Collect all MANIFEST_* variables from PARENT_SCOPE into current scope for caching
    # This is necessary because all set() calls above use PARENT_SCOPE
    get_directory_property(parent_vars VARIABLES)
    
    # Store parsed manifest in cache for future use
    kis_cache_store_manifest("${manifest_file}")
endfunction()



#
# kis_validate_package_platform
#
function(kis_validate_package_platform PACKAGE_NAME PACKAGE_PATH CURRENT_PLATFORM CURRENT_TAGS OUTPUT_COMPATIBLE OUTPUT_ERROR)
    # Check cache first
    kis_cache_get_platform_compatibility("${PACKAGE_PATH}" "${CURRENT_PLATFORM}" "${CURRENT_TAGS}" 
                                         cache_valid cached_compatible cached_error)
    if(cache_valid)
        set(${OUTPUT_COMPATIBLE} "${cached_compatible}" PARENT_SCOPE)
        set(${OUTPUT_ERROR} "${cached_error}" PARENT_SCOPE)
        return()
    endif()
    
    # Cache miss - perform validation
    kis_read_package_manifest_json(PACKAGE_PATH "${PACKAGE_PATH}")
    
    set(is_compatible TRUE)
    set(error_msg "")
    
    # FIX 1: Use direct variable check instead of DEFINED
    if(is_compatible AND MANIFEST_PLATFORM_EXCLUDES)
        list(FIND MANIFEST_PLATFORM_EXCLUDES "${CURRENT_PLATFORM}" platform_excluded_idx)
        if(NOT platform_excluded_idx EQUAL -1)
            set(is_compatible FALSE)
            kis_list_to_string(excluded_str "${MANIFEST_PLATFORM_EXCLUDES}" ", ")
            set(error_msg "Package explicitly excludes platform: ${CURRENT_PLATFORM}\n  Excluded platforms: ${excluded_str}")
        endif()
        
        if(is_compatible)
            foreach(tag ${CURRENT_TAGS})
                list(FIND MANIFEST_PLATFORM_EXCLUDES "${tag}" tag_excluded_idx)
                if(NOT tag_excluded_idx EQUAL -1)
                    set(is_compatible FALSE)
                    kis_list_to_string(excluded_str "${MANIFEST_PLATFORM_EXCLUDES}" ", ")
                    set(error_msg "Package explicitly excludes platform tag: ${tag}\n  Excluded platforms: ${excluded_str}")
                    break()
                endif()
            endforeach()
        endif()
    endif()
    
    # This one was already fixed, but is correct.
    if(is_compatible AND MANIFEST_PLATFORMS)
        list(FIND MANIFEST_PLATFORMS "${CURRENT_PLATFORM}" platform_found_idx)
        if(platform_found_idx EQUAL -1)
            set(is_compatible FALSE)
            kis_list_to_string(required_str "${MANIFEST_PLATFORMS}" ", ")
            set(error_msg "Package requires one of these platforms: ${required_str}\n  Current platform: ${CURRENT_PLATFORM}")
        endif()
    endif()
    
    # FIX 2: THIS IS THE KEY FIX for the current error.
    if(is_compatible AND MANIFEST_PLATFORM_TAGS)
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
            set(error_msg "Package requires at least one of these platform tags: ${required_tags_str}\n  Current tags: ${current_tags_str}")
        endif()
    endif()
    
    # FIX 3: Proactively fix the same bug for excludesTags
    if(is_compatible AND MANIFEST_EXCLUDES_TAGS)
        foreach(excluded_tag ${MANIFEST_EXCLUDES_TAGS})
            list(FIND CURRENT_TAGS "${excluded_tag}" tag_excluded_idx)
            if(NOT tag_excluded_idx EQUAL -1)
                set(is_compatible FALSE)
                kis_list_to_string(excluded_str "${MANIFEST_EXCLUDES_TAGS}" ", ")
                kis_list_to_string(current_str "${CURRENT_TAGS}" ", ")
                set(error_msg "Package excludes tag: ${excluded_tag}\n  Excluded tags: ${excluded_str}\n  Current tags: ${current_str}")
                break()
            endif()
        endforeach()
    endif()
    
    # FIX 4: Proactively fix the same bug for requiresTags
    if(is_compatible AND MANIFEST_REQUIRES_TAGS)
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
            set(error_msg "Package requires ALL of these tags: ${required_str}\n  Missing tags: ${missing_str}\n  Current tags: ${current_str}\n\n  [TIP] To enable missing tags:\n     - Use preset: cmake --preset dev-full\n     - Or set manually: -DKIS_BUILD_TAGS=\"${required_str}\"\n     - Or modify CMakePresets.json to add tags")
        endif()
    endif()
    
    # Store result in cache
    kis_cache_store_platform_compatibility("${PACKAGE_PATH}" "${CURRENT_PLATFORM}" "${CURRENT_TAGS}"
                                           "${is_compatible}" "${error_msg}")
    
    set(${OUTPUT_COMPATIBLE} ${is_compatible} PARENT_SCOPE)
    set(${OUTPUT_ERROR} "${error_msg}" PARENT_SCOPE)
endfunction()


#
# kis_get_package_platform_preference
#
# Determines the preferred platform subdirectory for a package based on its manifest.
#
function(kis_get_package_platform_preference OUTPUT_VAR PACKAGE_PATH)
    kis_read_package_manifest_json(PACKAGE_PATH "${PACKAGE_PATH}")
    set(result "")
    if(DEFINED MANIFEST_PLATFORMS)
        list(LENGTH MANIFEST_PLATFORMS num_platforms)
        if(num_platforms EQUAL 1)
            list(GET MANIFEST_PLATFORMS 0 single_platform)
            set(result "${single_platform}")
        endif()
    endif()
    set(${OUTPUT_VAR} "${result}" PARENT_SCOPE)
endfunction()