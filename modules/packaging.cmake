# kis_build_system/modules/packaging.cmake

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

get_filename_component(_KIS_PACKAGING_MODULE_PATH "${CMAKE_CURRENT_LIST_FILE}" PATH)
set(_KIS_GENERIC_CONFIG_TEMPLATE_FILE "${_KIS_PACKAGING_MODULE_PATH}/../templates/GenericPackageConfig.cmake.in")

#
# _kis_get_package_platform_tag
#
function(_kis_get_package_platform_tag out_var)
    set(found_tag "")
    set(reversed_tags ${KIS_PLATFORM_TAGS})
    list(REVERSE reversed_tags)
    foreach(tag ${reversed_tags})
        if(CMAKE_CURRENT_SOURCE_DIR MATCHES "/kis_packages/${tag}/")
            set(found_tag ${tag})
            break()
        endif()
    endforeach()
    set(${out_var} ${found_tag} PARENT_SCOPE)
endfunction()

function(_kis_install_package_common_steps variant_suffix)
    _kis_get_package_platform_tag(package_platform_tag)
    set(PACKAGE_CMAKE_INSTALL_DIR "${KIS_INSTALL_CMAKEDIR_COMMON}/${MANIFEST_NAME}")

    set(public_include_dir_path "${CMAKE_CURRENT_SOURCE_DIR}/${KIS_PACKAGE_COMMON_INCLUDE_DIR}")
    if(EXISTS "${public_include_dir_path}")
        if(package_platform_tag)
            install(DIRECTORY "${public_include_dir_path}/" DESTINATION "platform_include/${package_platform_tag}/${KIS_INSTALL_INCLUDEDIR_COMMON}")
        else()
            install(DIRECTORY "${public_include_dir_path}/" DESTINATION "${KIS_INSTALL_INCLUDEDIR_COMMON}")
        endif()
    endif()

    if(variant_suffix)
        set(targets_file_name "${MANIFEST_NAME}-targets-${variant_suffix}.cmake")
        set(export_name "${MANIFEST_NAME}-targets-${variant_suffix}")
    else()
        set(targets_file_name "${MANIFEST_NAME}-targets.cmake")
        set(export_name "${MANIFEST_NAME}-targets")
    endif()
    
    install(EXPORT ${export_name}
        FILE        ${targets_file_name}
        NAMESPACE   kis::
        DESTINATION ${PACKAGE_CMAKE_INSTALL_DIR}
    )

    set(_public_modules_dir "${CMAKE_CURRENT_SOURCE_DIR}/cmake/public_modules")
    set(_package_has_modules FALSE)
    if(IS_DIRECTORY "${_public_modules_dir}")
        install(DIRECTORY "${_public_modules_dir}/" DESTINATION "${PACKAGE_CMAKE_INSTALL_DIR}" FILES_MATCHING PATTERN "*.cmake")
        set(_package_has_modules TRUE)
    endif()

    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/${MANIFEST_NAME}ConfigVersion.cmake"
        VERSION "${MANIFEST_VERSION}"
        COMPATIBILITY AnyNewerVersion
    )
    
    # Build the find_dependency list from the manifest's `dependencies` object.
    set(_package_find_deps "")

    # Add first-party dependencies from JSON
    if(DEFINED MANIFEST_KIS_DEPENDENCIES)
        string(JSON num_deps ERROR_VARIABLE err LENGTH "${MANIFEST_KIS_DEPENDENCIES}")
        if(NOT err AND num_deps GREATER 0)
            math(EXPR last_idx "${num_deps} - 1")
            foreach(i RANGE ${last_idx})
                string(JSON dep_obj GET "${MANIFEST_KIS_DEPENDENCIES}" ${i})
                string(JSON dep_name GET "${dep_obj}" "name")
                list(APPEND _package_find_deps ${dep_name})
            endforeach()
        endif()
    endif()

    # Add third-party dependencies from JSON
    if(DEFINED MANIFEST_TPL_DEPENDENCIES)
        string(JSON num_deps ERROR_VARIABLE err LENGTH "${MANIFEST_TPL_DEPENDENCIES}")
        if(NOT err AND num_deps GREATER 0)
            math(EXPR last_idx "${num_deps} - 1")
            foreach(i RANGE ${last_idx})
                string(JSON dep_obj GET "${MANIFEST_TPL_DEPENDENCIES}" ${i})
                string(JSON dep_name GET "${dep_obj}" "name")
                
                string(JSON condition ERROR_VARIABLE cond_err GET "${dep_obj}" "condition")
                if(cond_err)
                    unset(condition)
                endif()

                set(is_active TRUE)
                if(DEFINED condition AND NOT "${condition}" STREQUAL "")
                    if(NOT (DEFINED ${condition} AND ${condition}))
                        set(is_active FALSE)
                    endif()
                endif()
                
                if(is_active)
                    list(APPEND _package_find_deps ${dep_name})
                endif()
            endforeach()
        endif()
    endif()
    
    if(_package_find_deps)
        list(REMOVE_DUPLICATES _package_find_deps)
    endif()
    
    # This variable is now a clean list of names, which is passed to the template.
    set(PACKAGE_FIND_DEPENDENCIES "${_package_find_deps}")
    set(PACKAGE_NAME "${MANIFEST_NAME}")
    set(PACKAGE_VERSION "${MANIFEST_VERSION}")
    set(PACKAGE_ABI_VARIANT "${MANIFEST_ABI_VARIANT}")
    set(PACKAGE_CATEGORY "${MANIFEST_CATEGORY}")
    set(PACKAGE_SEARCH_TAGS "${MANIFEST_SEARCH_TAGS}")

    # --- VARIANT SUPPORT (IDEMPOTENT INSTALL) ---
    set(variant_registry_file_in_install "${CMAKE_INSTALL_PREFIX}/${PACKAGE_CMAKE_INSTALL_DIR}/.installed_variants")
    set(variant_registry_file_in_build "${CMAKE_CURRENT_BINARY_DIR}/${MANIFEST_NAME}.installed_variants")

    set(existing_variants "")
    if(EXISTS "${variant_registry_file_in_install}")
        file(READ "${variant_registry_file_in_install}" existing_variants_str)
        string(STRIP "${existing_variants_str}" existing_variants_str)
        string(REPLACE "\n" ";" existing_variants "${existing_variants_str}")
    endif()
    
    if(variant_suffix)
        list(APPEND existing_variants "${variant_suffix}")
    else()
        # The base variant for ABI_INVARIANT is release
        list(APPEND existing_variants "release")
    endif()
    
    list(REMOVE_DUPLICATES existing_variants)
    list(SORT existing_variants)
    
    string(REPLACE ";" "\n" variants_file_content "${existing_variants}")
    set(INSTALLED_VARIANTS "${existing_variants}")

    # Write the new variant list to a file in the build directory
    file(WRITE "${variant_registry_file_in_build}" "${variants_file_content}")

    # Install the generated file, making the process idempotent
    install(FILES "${variant_registry_file_in_build}"
        DESTINATION "${PACKAGE_CMAKE_INSTALL_DIR}"
        RENAME ".installed_variants"
    )

    set(config_template_to_use "${_KIS_GENERIC_CONFIG_TEMPLATE_FILE}")
    set(PACKAGE_HAS_CMAKE_MODULES ${_package_has_modules})
    configure_package_config_file(
        "${config_template_to_use}"
        "${CMAKE_CURRENT_BINARY_DIR}/${MANIFEST_NAME}Config.cmake"
        INSTALL_DESTINATION ${PACKAGE_CMAKE_INSTALL_DIR}
    )

    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${MANIFEST_NAME}Config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/${MANIFEST_NAME}ConfigVersion.cmake"
        DESTINATION ${PACKAGE_CMAKE_INSTALL_DIR}
    )
endfunction()

function(kis_install_package)
    kis_read_package_manifest_json()
    kis_message_verbose(STATUS "Installing package: ${MANIFEST_NAME} (v${MANIFEST_VERSION})")
    
    if(DEFINED MANIFEST_CUSTOM_VARIANTS)
        kis_register_package_custom_variants("${MANIFEST_NAME}" "${MANIFEST_CUSTOM_VARIANTS}")
    endif()
    
    if(NOT DEFINED MANIFEST_ABI_VARIANT)
        set(MANIFEST_ABI_VARIANT "PER_CONFIG")
    endif()
    
    set(lib_dest "${KIS_INSTALL_LIBDIR_PLATFORM}")
    set(bin_dest "${KIS_INSTALL_BINDIR_PLATFORM}")
    set(path_type "ABI_INVARIANT (shared)")
    set(variant_suffix "")
    
    if(MANIFEST_ABI_VARIANT STREQUAL "PER_CONFIG")
        kis_get_current_variant_name(current_variant)
        if(DEFINED MANIFEST_SUPPORTED_VARIANTS)
            set(supported_variants "${MANIFEST_SUPPORTED_VARIANTS}")
        else()
            set(supported_variants "release")
        endif()
        if(NOT "release" IN_LIST supported_variants)
            list(APPEND supported_variants "release")
        endif()
        if(NOT "debug" IN_LIST supported_variants)
            list(APPEND supported_variants "debug")
        endif()
        
        if(NOT current_variant IN_LIST supported_variants)
            message(STATUS "  -> Package does not support variant '${current_variant}'")
            message(STATUS "  -> Supported variants: ${supported_variants}")
            message(STATUS "  -> Skipping installation for this variant")
            return()
        endif()
        
        set(lib_dest "${KIS_INSTALL_LIBDIR_PF_ARCH}")
        set(bin_dest "${KIS_INSTALL_BINDIR_PF_ARCH}")
        set(variant_suffix "${current_variant}")
        set(path_type "PER_CONFIG (${current_variant})")
    elseif(MANIFEST_ABI_VARIANT STREQUAL "ABI_INVARIANT")
        kis_get_current_variant_name(current_variant)
        if(NOT current_variant STREQUAL "release" AND NOT current_variant STREQUAL "debug")
            message(STATUS "  -> ABI_INVARIANT package skipping installation for variant '${current_variant}'")
            message(STATUS "  -> Will use version from base variant (release/debug)")
            return()
        endif()
        set(path_type "ABI_INVARIANT (shared across all configs)")
    endif()
    
    message(STATUS "  -> ABI Variant: ${path_type}")
    message(STATUS "  -> Install path: ${lib_dest}")
    if(variant_suffix)
        message(STATUS "  -> Variant suffix: ${variant_suffix}")
    endif()
    
    if(variant_suffix)
        set(export_name "${MANIFEST_NAME}-targets-${variant_suffix}")
    else()
        set(export_name "${MANIFEST_NAME}-targets")
    endif()
    
    install(TARGETS ${MANIFEST_NAME}
        EXPORT ${export_name}
        LIBRARY DESTINATION ${lib_dest}
        ARCHIVE DESTINATION ${lib_dest}
        RUNTIME DESTINATION ${bin_dest}
        INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )
    _kis_install_package_common_steps("${variant_suffix}")
endfunction()

function(kis_install_interface_package)
    kis_read_package_manifest_json()
    message(STATUS "Installing INTERFACE package: ${MANIFEST_NAME} (v${MANIFEST_VERSION})")
    set(variant_suffix "")
    install(TARGETS ${MANIFEST_NAME} EXPORT ${MANIFEST_NAME}-targets)
    _kis_install_package_common_steps("${variant_suffix}")
endfunction()

function(kis_install_assets)
    kis_read_package_manifest_json()
    set(common_assets_src "${CMAKE_CURRENT_SOURCE_DIR}/public_assets")
    if(IS_DIRECTORY "${common_assets_src}")
        message(STATUS "Configuring common asset installation for package '${MANIFEST_NAME}'")
        install(DIRECTORY "${common_assets_src}/" DESTINATION "${KIS_INSTALL_ASSETSDIR_COMMON}/${MANIFEST_NAME}" USE_SOURCE_PERMISSIONS)
    endif()

    set(platform_assets_src_base "${CMAKE_CURRENT_SOURCE_DIR}/platform_assets")
    if(IS_DIRECTORY "${platform_assets_src_base}")
        foreach(tag ${KIS_PLATFORM_TAGS})
            set(platform_assets_source "${platform_assets_src_base}/${tag}")
            if(IS_DIRECTORY "${platform_assets_source}")
                message(STATUS "Configuring platform asset installation for package '${MANIFEST_NAME}' with tag '${tag}'")
                install(DIRECTORY "${platform_assets_source}/" DESTINATION "platform_assets/${tag}/${MANIFEST_NAME}" USE_SOURCE_PERMISSIONS)
            endif()
        endforeach()
    endif()
endfunction()