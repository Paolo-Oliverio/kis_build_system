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

    if(KIS_SKIP_MANIFEST_CHECKS)
        kis_message_verbose("skipped manifest checks of '${pkg_name}' by option full faith in schema validation.")
        return()
    endif()
    
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