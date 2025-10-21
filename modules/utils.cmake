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
        set(KIS_TEST_LAST_ERROR "FATAL: ${TITLE}\n  ${MESSAGE}\n  Hint: ${HINT}")
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

# --- Helper macro to parse an array of strings with robust error handling ---
macro(_json_get_array PARENT_VAR JSON_STRING KEY)
    string(JSON arr_str ERROR_VARIABLE get_err GET "${JSON_STRING}" "${KEY}")
    
    if(NOT get_err)
        string(JSON arr_type TYPE "${arr_str}")
        if(NOT arr_type STREQUAL "ARRAY")
            if(NOT arr_str STREQUAL "")
                kis_get_package_name_from_path("${PACKAGE_PATH}" pkg_name)
                kis_message_fatal_actionable("Invalid Manifest: Not an Array" "The value for key '${KEY}' must be a JSON array, but is a '${arr_type}'." "Value found was: '${arr_str}'\n  Example of a correct array: \"${KEY}\": [\"value1\", \"value2\"]" PACKAGE ${pkg_name} FILE ${manifest_file})
            endif()
        else()
            string(JSON len LENGTH "${arr_str}")
            if(len GREATER 0)
                math(EXPR last_idx "${len} - 1")
                set(list_val "")
                foreach(i RANGE ${last_idx})
                    string(JSON item ERROR_VARIABLE item_err GET "${arr_str}" ${i})
                    if(item_err)
                        kis_get_package_name_from_path("${PACKAGE_PATH}" pkg_name)
                        kis_message_fatal_actionable("Invalid Manifest: Array Item Parse Error" "Could not parse item at index ${i} for key '${KEY}'. Reason: ${item_err}" "Array content being parsed: ${arr_str}" PACKAGE ${pkg_name} FILE ${manifest_file})
                    else()
                        list(APPEND list_val "${item}")
                    endif()
                endforeach()
                set(${PARENT_VAR} "${list_val}")
            endif()
        endif()
    endif()
endmacro()

#
# kis_read_package_manifest_json (MACRO)
#
# Reads a package's kis.package.json file and extracts all metadata fields
# into MANIFEST_* variables in the CALLER'S scope.
#
macro(kis_read_package_manifest_json PACKAGE_PATH)
    set(manifest_file "${PACKAGE_PATH}/kis.package.json")
    
    if(NOT EXISTS "${manifest_file}")
        message(FATAL_ERROR "Package manifest not found: ${manifest_file}")
    endif()

    file(READ "${manifest_file}" manifest_content)
    
    if(manifest_content MATCHES "^\\xef\\xbb\\bf")
        string(SUBSTRING "${manifest_content}" 3 -1 manifest_content)
    endif()

    set(manifest_vars NAME VERSION TYPE DESCRIPTION CATEGORY SEARCH_TAGS OVERRIDES PLATFORMS PLATFORM_TAGS PLATFORM_EXCLUDES REQUIRES_TAGS EXCLUDES_TAGS ABI_VARIANT SUPPORTED_VARIANTS CUSTOM_VARIANTS KIS_DEPENDENCIES TPL_DEPENDENCIES FEATURES)
    foreach(var ${manifest_vars})
        unset(MANIFEST_${var})
    endforeach()

    # First, check if the content is a valid JSON object at all.
    string(JSON content_type ERROR_VARIABLE type_err TYPE "${manifest_content}")
    if(type_err OR NOT content_type STREQUAL "OBJECT")
        kis_get_package_name_from_path("${PACKAGE_PATH}" pkg_name)
        kis_message_fatal_actionable("Invalid JSON" "Manifest content is not a valid JSON object. Reason: ${type_err}" "Ensure the file starts with '{' and ends with '}' and contains valid JSON." PACKAGE ${pkg_name} FILE ${manifest_file})
    else()
        # Use the robust "try-get and check error" pattern for each field.
        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "name")
        if(NOT err)
            set(MANIFEST_NAME "${val}")
        endif()
        
        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "version")
        if(NOT err)
            set(MANIFEST_VERSION "${val}")
        endif()

        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "type")
        if(NOT err)
            set(MANIFEST_TYPE "${val}")
        endif()

        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "description")
        if(NOT err)
            set(MANIFEST_DESCRIPTION "${val}")
        endif()

        string(JSON val ERROR_VARIABLE err GET "${manifest_content}" "category")
        if(NOT err)
            set(MANIFEST_CATEGORY "${val}")
        endif()

        _json_get_array(MANIFEST_SEARCH_TAGS "${manifest_content}" "searchTags")
        _json_get_array(MANIFEST_OVERRIDES "${manifest_content}" "overrides")
        _json_get_array(MANIFEST_FEATURES "${manifest_content}" "features")

        string(JSON platform_obj ERROR_VARIABLE err GET "${manifest_content}" "platform")
        if(NOT err)
            _json_get_array(MANIFEST_PLATFORMS "${platform_obj}" "platforms")
            _json_get_array(MANIFEST_PLATFORM_TAGS "${platform_obj}" "tags")
            _json_get_array(MANIFEST_PLATFORM_EXCLUDES "${platform_obj}" "excludes")
            _json_get_array(MANIFEST_REQUIRES_TAGS "${platform_obj}" "requiresTags")
            _json_get_array(MANIFEST_EXCLUDES_TAGS "${platform_obj}" "excludesTags")
        endif()

        string(JSON abi_obj ERROR_VARIABLE err GET "${manifest_content}" "abi")
        if(NOT err)
            string(JSON val ERROR_VARIABLE err_v GET "${abi_obj}" "variant")
            if(NOT err_v)
                set(MANIFEST_ABI_VARIANT "${val}")
            endif()
            _json_get_array(MANIFEST_SUPPORTED_VARIANTS "${abi_obj}" "supportedVariants")
            string(JSON val ERROR_VARIABLE err_c GET "${abi_obj}" "customVariants")
            if(NOT err_c)
                set(MANIFEST_CUSTOM_VARIANTS "${val}")
            endif()
        endif()

        string(JSON deps_obj ERROR_VARIABLE err GET "${manifest_content}" "dependencies")
        if(NOT err)
            string(JSON val ERROR_VARIABLE err_k GET "${deps_obj}" "kis")
            if(NOT err_k)
                set(MANIFEST_KIS_DEPENDENCIES "${val}")
            endif()
            string(JSON val ERROR_VARIABLE err_t GET "${deps_obj}" "thirdParty")
            if(NOT err_t)
                set(MANIFEST_TPL_DEPENDENCIES "${val}")
            endif()
        endif()
    endif()
endmacro()


#
# kis_validate_package_platform
#
function(kis_validate_package_platform PACKAGE_NAME PACKAGE_PATH CURRENT_PLATFORM CURRENT_TAGS OUTPUT_COMPATIBLE OUTPUT_ERROR)
    kis_read_package_manifest_json("${PACKAGE_PATH}")
    
    set(is_compatible TRUE)
    set(error_msg "")
    
    if(DEFINED MANIFEST_PLATFORM_EXCLUDES)
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
    
    if(is_compatible AND DEFINED MANIFEST_PLATFORMS)
        list(FIND MANIFEST_PLATFORMS "${CURRENT_PLATFORM}" platform_found_idx)
        if(platform_found_idx EQUAL -1)
            set(is_compatible FALSE)
            kis_list_to_string(required_str "${MANIFEST_PLATFORMS}" ", ")
            set(error_msg "Package requires one of these platforms: ${required_str}\n  Current platform: ${CURRENT_PLATFORM}")
        endif()
    endif()
    
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
            set(error_msg "Package requires at least one of these platform tags: ${required_tags_str}\n  Current tags: ${current_tags_str}")
        endif()
    endif()
    
    if(is_compatible AND DEFINED MANIFEST_EXCLUDES_TAGS)
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
            set(error_msg "Package requires ALL of these tags: ${required_str}\n  Missing tags: ${missing_str}\n  Current tags: ${current_str}\n\n  [TIP] To enable missing tags:\n     - Use preset: cmake --preset dev-full\n     - Or set manually: -DKIS_BUILD_TAGS=\"${required_str}\"\n     - Or modify CMakePresets.json to add tags")
        endif()
    endif()
    
    set(${OUTPUT_COMPATIBLE} ${is_compatible} PARENT_SCOPE)
    set(${OUTPUT_ERROR} "${error_msg}" PARENT_SCOPE)
endfunction()


#
# kis_get_package_platform_preference
#
# Determines the preferred platform subdirectory for a package based on its manifest.
#
function(kis_get_package_platform_preference OUTPUT_VAR PACKAGE_PATH)
    kis_read_package_manifest_json("${PACKAGE_PATH}")
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