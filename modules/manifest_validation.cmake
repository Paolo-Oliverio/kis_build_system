# kis_build_system/modules/manifest_validation.cmake
#
# Functions for validating package manifests

#
# kis_validate_package_manifest
#
# Validates that a package manifest (kis.package.json) contains required fields
# and that the configuration is consistent.
#
function(kis_validate_package_manifest package_path)
    set(manifest_file "${package_path}/kis.package.json")
    
    if(NOT EXISTS "${manifest_file}")
        kis_message_fatal_actionable(
            "Missing Package Manifest"
            "Package at '${package_path}' has no kis.package.json file"
            "Create a kis.package.json file with required fields (name, version, type)."
            PACKAGE "(unknown)"
            FILE "${manifest_file}"
        )
    endif()

    file(READ "${manifest_file}" manifest_content)
    
    # Validate required fields
    string(JSON pkg_name ERROR_VARIABLE err GET "${manifest_content}" "name")
    if(err OR NOT pkg_name)
        kis_message_fatal_actionable(
            "Invalid Package Manifest"
            "Missing or invalid required field: 'name' (must be a string)"
            "Add to ${manifest_file}:\n     \"name\": \"your_package\""
            FILE "${manifest_file}"
        )
    endif()

    string(JSON pkg_version ERROR_VARIABLE err GET "${manifest_content}" "version")
    if(err OR NOT pkg_version)
        kis_message_fatal_actionable(
            "Invalid Package Manifest"
            "Missing or invalid required field: 'version' (must be a string)"
            "Add to ${manifest_file}:\n     \"version\": \"1.0.0\""
            PACKAGE "${pkg_name}" FILE "${manifest_file}"
        )
    endif()
    
    string(JSON pkg_type ERROR_VARIABLE err GET "${manifest_content}" "type")
    if(err OR NOT pkg_type)
        kis_message_fatal_actionable(
            "Invalid Package Manifest"
            "Missing or invalid required field: 'type'"
            "Add to ${manifest_file}:\n     \"type\": \"LIBRARY\"  (or INTERFACE, EXECUTABLE)"
            PACKAGE "${pkg_name}" FILE "${manifest_file}"
        )
    endif()

    # Validate `type` value
    set(valid_types "LIBRARY" "INTERFACE" "EXECUTABLE")
    if(NOT pkg_type IN_LIST valid_types)
        kis_message_fatal_actionable(
            "Invalid 'type' in Manifest"
            "Invalid value: '${pkg_type}'\n  Valid values: LIBRARY, INTERFACE, EXECUTABLE"
            "Fix in ${manifest_file}:\n     \"type\": \"LIBRARY\""
            PACKAGE "${pkg_name}" FILE "${manifest_file}"
        )
    endif()

    # Validate ABI configuration
    string(JSON abi_variant ERROR_VARIABLE err GET "${manifest_content}" "abi" "variant")
    if(NOT err AND abi_variant)
        set(valid_abi_variants "PER_CONFIG" "ABI_INVARIANT")
        if(NOT abi_variant IN_LIST valid_abi_variants)
             kis_message_fatal_actionable(
                "Invalid 'abi.variant' in Manifest"
                "Invalid value: '${abi_variant}'\n  Valid values: PER_CONFIG, ABI_INVARIANT"
                "Fix in ${manifest_file}:\n     \"abi\": { \"variant\": \"PER_CONFIG\" }"
                PACKAGE "${pkg_name}" FILE "${manifest_file}"
            )
        endif()

        # Validate consistency: INTERFACE type should be ABI_INVARIANT
        if(pkg_type STREQUAL "INTERFACE" AND abi_variant STREQUAL "PER_CONFIG")
            kis_message_warning_actionable(
                "Inconsistent Package Configuration"
                "INTERFACE libraries should use ABI_INVARIANT, not PER_CONFIG"
                "Change to:\n     \"type\": \"INTERFACE\",\n     \"abi\": { \"variant\": \"ABI_INVARIANT\" }"
                PACKAGE "${pkg_name}" FILE "${manifest_file}"
            )
        endif()
    endif()

    # Cross-check with CMakeLists.txt if available
    set(cmakelists_file "${package_path}/CMakeLists.txt")
    if(EXISTS "${cmakelists_file}")
        file(READ "${cmakelists_file}" cmakelists_content)
        
        set(cmake_declares_interface FALSE)
        set(cmake_declares_executable FALSE)
        
        # More flexible regex patterns that handle ${pkg_name} or literal name
        if(cmakelists_content MATCHES "add_library\\((\\$\\{PACKAGE_NAME\\}|${pkg_name})[ \\t]+INTERFACE")
            set(cmake_declares_interface TRUE)
        endif()
        
        if(cmakelists_content MATCHES "add_executable\\((\\$\\{PACKAGE_NAME\\}|${pkg_name})")
            set(cmake_declares_executable TRUE)
        endif()
        
        # 1. INTERFACE packages MUST use INTERFACE keyword
        if(pkg_type STREQUAL "INTERFACE" AND NOT cmake_declares_interface)
            if(cmakelists_content MATCHES "add_library\\((\\$\\{PACKAGE_NAME\\}|${pkg_name})\\)")
                kis_message_warning_actionable(
                    "Manifest/CMake Mismatch"
                    "Manifest declares INTERFACE but CMakeLists.txt missing INTERFACE keyword"
                    "Fix in ${cmakelists_file}:\n     add_library(\\${PACKAGE_NAME} INTERFACE)  # Add INTERFACE keyword"
                    PACKAGE "${pkg_name}" FILE "${manifest_file}"
                )
            endif()
        
        # 2. EXECUTABLE packages MUST use add_executable
        elseif(pkg_type STREQUAL "EXECUTABLE" AND NOT cmake_declares_executable)
            if(cmakelists_content MATCHES "add_library\\((\\$\\{PACKAGE_NAME\\}|${pkg_name})")
                kis_message_warning_actionable(
                    "Manifest/CMake Mismatch"
                    "Manifest declares EXECUTABLE but CMakeLists.txt uses add_library"
                    "Fix in ${cmakelists_file}:\n     add_executable(\\${PACKAGE_NAME} ...)  # Use add_executable instead"
                    PACKAGE "${pkg_name}" FILE "${manifest_file}"
                )
            endif()
        endif()
    endif()
endfunction()

#
# kis_validate_all_manifests
#
# Validates all discovered package manifests
#
function(kis_validate_all_manifests)
    set(package_paths ${ARGN})
    
    message(STATUS "Validating package manifests...")
    
    set(validation_errors 0)
    foreach(package_path ${package_paths})
        get_filename_component(package_name ${package_path} NAME)
        
        # Validation happens inside kis_validate_package_manifest
        # and will call FATAL_ERROR if critical issues found
        kis_validate_package_manifest("${package_path}")
    endforeach()
    
    message(STATUS "Manifest validation complete")
endfunction()