# kis_build_system/modules/manifest_validation.cmake
#
# Functions for validating package manifests

#
# kis_validate_package_manifest
#
# Validates that a package manifest (kis.package.cmake) contains required fields
# and that the configuration is consistent.
#
function(kis_validate_package_manifest package_path)
    set(manifest_file "${package_path}/kis.package.cmake")
    
    if(NOT EXISTS "${manifest_file}")
        kis_message_fatal_actionable(
            "Missing Package Manifest"
            "Package at '${package_path}' has no kis.package.cmake file"
            "Create a kis.package.cmake file with at minimum:\\n     set(PACKAGE_NAME \\\"your_package\\\")\\n     set(PACKAGE_VERSION \\\"1.0.0\\\")"
        )
    endif()
    
    # Read manifest in clean scope
    unset(PACKAGE_NAME)
    unset(PACKAGE_VERSION)
    unset(PACKAGE_LIBRARY_TYPE)
    unset(PACKAGE_ABI_VARIANT)
    include("${manifest_file}")
    
    # Validate required fields
    if(NOT DEFINED PACKAGE_NAME)
        kis_message_fatal_actionable(
            "Invalid Package Manifest"
            "Missing required field: PACKAGE_NAME\\n  File: ${manifest_file}"
            "Add to ${manifest_file}:\\n     set(PACKAGE_NAME \\\"your_package\\\")"
        )
    endif()
    
    if(NOT DEFINED PACKAGE_VERSION)
        kis_message_fatal_actionable(
            "Invalid Package Manifest"
            "Missing required field: PACKAGE_VERSION\\n  File: ${manifest_file}"
            "Add to ${manifest_file}:\\n     set(PACKAGE_VERSION \\\"1.0.0\\\")"
        )
    endif()
    
    # Validate PACKAGE_LIBRARY_TYPE if provided
    if(DEFINED PACKAGE_LIBRARY_TYPE)
        set(valid_types "INTERFACE" "STATIC" "SHARED")
        if(NOT PACKAGE_LIBRARY_TYPE IN_LIST valid_types)
            kis_message_fatal_actionable(
                "Invalid PACKAGE_LIBRARY_TYPE"
                "Package: ${PACKAGE_NAME}\\n  Invalid value: '${PACKAGE_LIBRARY_TYPE}'\\n  Valid values: INTERFACE, STATIC, SHARED"
                "Fix in ${manifest_file}:\\n     set(PACKAGE_LIBRARY_TYPE \\\"STATIC\\\")  # or INTERFACE or SHARED"
            )
        endif()
        
        # Validate consistency: INTERFACE + PER_CONFIG is contradictory
        if(PACKAGE_LIBRARY_TYPE STREQUAL "INTERFACE")
            if(DEFINED PACKAGE_ABI_VARIANT AND PACKAGE_ABI_VARIANT STREQUAL "PER_CONFIG")
                kis_message_warning_actionable(
                    "Inconsistent Package Configuration"
                    "Package: ${PACKAGE_NAME}\\n  INTERFACE libraries should use ABI_INVARIANT, not PER_CONFIG\\n  File: ${manifest_file}"
                    "Change to:\\n     set(PACKAGE_LIBRARY_TYPE \\\"INTERFACE\\\")\\n     set(PACKAGE_ABI_VARIANT \\\"ABI_INVARIANT\\\")  # or omit"
                )
            endif()
        endif()
    endif()
    
    # Validate PACKAGE_ABI_VARIANT if provided
    if(DEFINED PACKAGE_ABI_VARIANT)
        set(valid_variants "PER_CONFIG" "ABI_INVARIANT" "DEFAULT")  # DEFAULT for backward compat
        if(NOT PACKAGE_ABI_VARIANT IN_LIST valid_variants)
            kis_message_fatal_actionable(
                "Invalid PACKAGE_ABI_VARIANT"
                "Package: ${PACKAGE_NAME}\\n  Invalid value: '${PACKAGE_ABI_VARIANT}'\\n  Valid values: PER_CONFIG, ABI_INVARIANT"
                "Fix in ${manifest_file}:\\n     set(PACKAGE_ABI_VARIANT \\\"PER_CONFIG\\\")  # or ABI_INVARIANT"
            )
        endif()
        
        # Warn about deprecated DEFAULT
        if(PACKAGE_ABI_VARIANT STREQUAL "DEFAULT")
            message(STATUS "[INFO] Package '${PACKAGE_NAME}' uses deprecated 'DEFAULT', consider renaming to 'ABI_INVARIANT'")
        endif()
    endif()
    
    # Validate PACKAGE_SUPPORTED_VARIANTS if provided
    if(DEFINED PACKAGE_SUPPORTED_VARIANTS)
        # Only makes sense for PER_CONFIG packages
        if(DEFINED PACKAGE_ABI_VARIANT)
            if(PACKAGE_ABI_VARIANT STREQUAL "ABI_INVARIANT" OR PACKAGE_ABI_VARIANT STREQUAL "DEFAULT")
                kis_message_warning_actionable(
                    "Unnecessary Configuration"
                    "Package: ${PACKAGE_NAME}\\n  PACKAGE_SUPPORTED_VARIANTS is set but PACKAGE_ABI_VARIANT is '${PACKAGE_ABI_VARIANT}'\\n  Supported variants only apply to PER_CONFIG packages"
                    "Either:\\n     1. Remove PACKAGE_SUPPORTED_VARIANTS (not needed for ABI_INVARIANT)\\n     2. Or change to set(PACKAGE_ABI_VARIANT \\\"PER_CONFIG\\\")"
                )
            endif()
        endif()
    endif()
    
    # Cross-check with CMakeLists.txt if available
    set(cmakelists_file "${package_path}/CMakeLists.txt")
    if(EXISTS "${cmakelists_file}")
        file(READ "${cmakelists_file}" cmakelists_content)
        
        # Check if add_library/add_executable declaration matches PACKAGE_TYPE
        if(DEFINED PACKAGE_TYPE)
            set(cmake_declares_interface FALSE)
            set(cmake_declares_executable FALSE)
            
            # More flexible regex patterns that handle ${PACKAGE_NAME} or literal name
            # Need to escape $ and { } for regex matching
            # Pattern matches: add_library(${PACKAGE_NAME} INTERFACE) or add_library(literal_name INTERFACE)
            if(cmakelists_content MATCHES "add_library\\((\\$\\{PACKAGE_NAME\\}|${PACKAGE_NAME})[ \\t]+INTERFACE")
                set(cmake_declares_interface TRUE)
            endif()
            
            # Pattern for add_executable - check if it exists with package name
            if(cmakelists_content MATCHES "add_executable\\((\\$\\{PACKAGE_NAME\\}|${PACKAGE_NAME})")
                set(cmake_declares_executable TRUE)
            endif()
            
            # Only validate critical mismatches that affect build correctness
            # We focus on two cases where the mismatch causes real problems:
            
            # 1. INTERFACE packages MUST use INTERFACE keyword
            if(PACKAGE_TYPE STREQUAL "INTERFACE" AND NOT cmake_declares_interface)
                # Check if add_library exists without INTERFACE keyword
                if(cmakelists_content MATCHES "add_library\\((\\$\\{PACKAGE_NAME\\}|${PACKAGE_NAME})\\)")
                    kis_message_warning_actionable(
                        "Manifest/CMake Mismatch"
                        "Package: ${PACKAGE_NAME}\\n  Manifest declares INTERFACE but CMakeLists.txt missing INTERFACE keyword"
                        "Fix in ${cmakelists_file}:\\n     add_library(\\${PACKAGE_NAME} INTERFACE)  # Add INTERFACE keyword"
                    )
                endif()
            
            # 2. EXECUTABLE packages MUST use add_executable
            elseif(PACKAGE_TYPE STREQUAL "EXECUTABLE" AND NOT cmake_declares_executable)
                # Check if add_library is used instead of add_executable
                if(cmakelists_content MATCHES "add_library\\((\\$\\{PACKAGE_NAME\\}|${PACKAGE_NAME})")
                    kis_message_warning_actionable(
                        "Manifest/CMake Mismatch"
                        "Package: ${PACKAGE_NAME}\\n  Manifest declares EXECUTABLE but CMakeLists.txt uses add_library"
                        "Fix in ${cmakelists_file}:\\n     add_executable(\\${PACKAGE_NAME} ...)  # Use add_executable instead"
                    )
                endif()
            endif()
            
            # Note: We intentionally don't validate STATIC vs SHARED because:
            # - These can be set via BUILD_SHARED_LIBS at configure time
            # - The manifest reflects the default/intended type, not always the actual type
            # - Static analysis of CMakeLists.txt can't reliably detect the final type
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
