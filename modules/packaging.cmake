# kis_build_system/modules/packaging.cmake

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

get_filename_component(_KIS_PACKAGING_MODULE_PATH "${CMAKE_CURRENT_LIST_FILE}" PATH)
set(_KIS_GENERIC_CONFIG_TEMPLATE_FILE "${_KIS_PACKAGING_MODULE_PATH}/../templates/GenericPackageConfig.cmake.in")

#
# _kis_get_package_platform_tag
#
# Helper to determine if the current package is in a platform-tagged directory.
# It returns the most specific tag found in the package's path.
#
function(_kis_get_package_platform_tag out_var)
    set(found_tag "")
    # We check tags from most specific to least specific to find the best match.
    set(reversed_tags ${KIS_PLATFORM_TAGS})
    list(REVERSE reversed_tags)

    foreach(tag ${reversed_tags})
        # Check if the package's path matches ".../kis_packages/<tag>/..."
        if(CMAKE_CURRENT_SOURCE_DIR MATCHES "/kis_packages/${tag}/")
            set(found_tag ${tag})
            break() # Found the most specific tag, so we can stop.
        endif()
    endforeach()
    set(${out_var} ${found_tag} PARENT_SCOPE)
endfunction()

function(_kis_install_package_common_steps variant_suffix)
    _kis_get_package_platform_tag(package_platform_tag)

    # All CMake configuration files now go to a common, platform-agnostic directory.
    set(PACKAGE_CMAKE_INSTALL_DIR "${KIS_INSTALL_CMAKEDIR_COMMON}/${PACKAGE_NAME}")

    # --- THIS IS THE KEY LOGIC CHANGE ---
    set(public_include_dir_path "${CMAKE_CURRENT_SOURCE_DIR}/main/include")
    if(EXISTS "${public_include_dir_path}")
        if(package_platform_tag)
            # This is a platform-specific package, so its headers go to the override directory.
            message(STATUS "--> Installing package '${PACKAGE_NAME}' headers to platform directory: '${package_platform_tag}'")
            install(DIRECTORY "${public_include_dir_path}/" DESTINATION "platform_include/${package_platform_tag}/${KIS_INSTALL_INCLUDEDIR_COMMON}")
        else()
            # This is a common package, its headers go to the common directory.
            install(DIRECTORY "${public_include_dir_path}/" DESTINATION "${KIS_INSTALL_INCLUDEDIR_COMMON}")
        endif()
    endif()

    # Install the export definition file (contains platform-specific library paths)
    # For PER_CONFIG packages, append variant suffix to the targets file name
    if(variant_suffix)
        set(targets_file_name "${PACKAGE_NAME}-targets-${variant_suffix}.cmake")
        set(export_name "${PACKAGE_NAME}-targets-${variant_suffix}")
    else()
        set(targets_file_name "${PACKAGE_NAME}-targets.cmake")
        set(export_name "${PACKAGE_NAME}-targets")
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
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}ConfigVersion.cmake"
        VERSION "${PACKAGE_VERSION}"
        COMPATIBILITY AnyNewerVersion
    )

    # Build a list of dependency package names for use with
    # the generic package config template which calls
    # find_dependency(<dep>) for each entry in
    # PACKAGE_FIND_DEPENDENCIES. PACKAGE_DEPENDENCIES is expected to
    # contain entries in the form: "name;url;tag" (which CMake splits
    # into list elements). We parse it and extract only the package
    # names so consumers of the package will get a find_dependency()
    # call for each first-party dependency.
    set(_package_find_deps "")
    if(DEFINED PACKAGE_DEPENDENCIES AND PACKAGE_DEPENDENCIES)
        list(LENGTH PACKAGE_DEPENDENCIES _deps_len)
        set(_i 0)
        while(_i LESS _deps_len)
            list(GET PACKAGE_DEPENDENCIES ${_i} _depname)
            math(EXPR _i "${_i} + 1")

            # If the next element looks like a URL, skip the URL and
            # the following tag element (if present).
            if(_i LESS _deps_len)
                list(GET PACKAGE_DEPENDENCIES ${_i} _maybe_url)
                if(_maybe_url MATCHES "^https?://")
                    math(EXPR _i "${_i} + 1")
                    if(_i LESS _deps_len)
                        math(EXPR _i "${_i} + 1")
                    endif()
                endif()
            endif()

            list(APPEND _package_find_deps ${_depname})
        endwhile()
        list(REMOVE_DUPLICATES _package_find_deps)
    endif()

    # Also collect third-party dependencies that this package uses
    # These will be added to find_dependency() calls in the package config
    get_property(_third_party_deps GLOBAL PROPERTY KIS_PACKAGE_${PACKAGE_NAME}_THIRD_PARTY_DEPS)
    if(_third_party_deps)
        list(APPEND _package_find_deps ${_third_party_deps})
        list(REMOVE_DUPLICATES _package_find_deps)
    endif()

    # Expose PACKAGE_FIND_DEPENDENCIES for the template. The template
    # expects this to be a CMake list.
    set(PACKAGE_FIND_DEPENDENCIES "${_package_find_deps}")

    # Optional metadata: ensure variables exist so configure_package_config_file
    # can substitute them even if individual package manifests don't set them.
    if(DEFINED PACKAGE_CATEGORY)
        set(_package_category "${PACKAGE_CATEGORY}")
    else()
        set(_package_category "")
    endif()

    if(DEFINED PACKAGE_SEARCH_TAGS)
        # PACKAGE_SEARCH_TAGS is expected to be a list; serialize to a
        # semicolon-separated string for easy parsing by tools that read
        # the generated Config.cmake.
        string(REPLACE ";" ";" _serialized_search_tags "${PACKAGE_SEARCH_TAGS}")
        set(_package_search_tags "${_serialized_search_tags}")
    else()
        set(_package_search_tags "")
    endif()

    # Make them available under the exact names expected by the template.
    set(PACKAGE_CATEGORY "${_package_category}")
    set(PACKAGE_SEARCH_TAGS "${_package_search_tags}")
    
    # --- VARIANT SUPPORT ---
    # Track installed variants for this package across multiple installs
    set(variant_registry_file "${CMAKE_INSTALL_PREFIX}/${PACKAGE_CMAKE_INSTALL_DIR}/.installed_variants")
    
    # Read existing variants if the file exists
    set(existing_variants "")
    if(EXISTS "${variant_registry_file}")
        file(READ "${variant_registry_file}" existing_variants)
        string(STRIP "${existing_variants}" existing_variants)
        string(REPLACE "\n" ";" existing_variants "${existing_variants}")
    endif()
    
    # Add current variant to the list
    if(variant_suffix)
        list(APPEND existing_variants "${variant_suffix}")
    else()
        list(APPEND existing_variants "release")  # DEFAULT packages count as "release"
    endif()
    
    # Remove duplicates and sort
    list(REMOVE_DUPLICATES existing_variants)
    list(SORT existing_variants)
    
    # Set INSTALLED_VARIANTS for the template
    string(REPLACE ";" ";" INSTALLED_VARIANTS "${existing_variants}")
    
    # Write updated variant registry (this happens during install, not configure)
    install(CODE "
        file(WRITE \"${variant_registry_file}\" \"${existing_variants}\")
    ")

    set(config_template_to_use "${_KIS_GENERIC_CONFIG_TEMPLATE_FILE}")
    set(PACKAGE_HAS_CMAKE_MODULES ${_package_has_modules})
    configure_package_config_file(
        "${config_template_to_use}"
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}Config.cmake"
        INSTALL_DESTINATION ${PACKAGE_CMAKE_INSTALL_DIR}
    )

    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}Config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}ConfigVersion.cmake"
        DESTINATION ${PACKAGE_CMAKE_INSTALL_DIR}
    )
endfunction()

function(kis_install_package)
    include("${CMAKE_CURRENT_SOURCE_DIR}/kis.package.cmake")
    message(STATUS "Installing package: ${PACKAGE_NAME} (v${PACKAGE_VERSION})")
    
    # Register any custom variants this package defines
    if(DEFINED PACKAGE_CUSTOM_VARIANTS)
        kis_register_package_custom_variants("${PACKAGE_NAME}" "${PACKAGE_CUSTOM_VARIANTS}")
    endif()
    
    # Default to PER_CONFIG if not specified
    if(NOT DEFINED PACKAGE_ABI_VARIANT)
        set(PACKAGE_ABI_VARIANT "PER_CONFIG")
    endif()
    
    # Determine installation path based on PACKAGE_ABI_VARIANT
    # ABI_INVARIANT (formerly DEFAULT): Use platform-default path (shared across configs)
    #                                    Only for header-only or truly ABI-invariant libraries
    # PER_CONFIG (default): Use config-specific path (with suffix if set)
    
    set(lib_dest "${KIS_INSTALL_LIBDIR_PLATFORM}")
    set(bin_dest "${KIS_INSTALL_BINDIR_PLATFORM}")
    set(path_type "ABI_INVARIANT (shared)")
    set(variant_suffix "")  # Empty for ABI_INVARIANT packages
    
    if(PACKAGE_ABI_VARIANT STREQUAL "PER_CONFIG")
        # Determine current variant name
        kis_get_current_variant_name(current_variant)
        
        # Get supported variants for this package
        if(DEFINED PACKAGE_SUPPORTED_VARIANTS)
            set(supported_variants "${PACKAGE_SUPPORTED_VARIANTS}")
        else()
            # Default: PER_CONFIG packages support at least "release"
            set(supported_variants "release")
        endif()
        
        # IMPORTANT: debug and release are ALWAYS implicitly supported
        # Add them if not already in the list
        if(NOT "release" IN_LIST supported_variants)
            list(APPEND supported_variants "release")
        endif()
        if(NOT "debug" IN_LIST supported_variants)
            list(APPEND supported_variants "debug")
        endif()
        
        # Check if this package supports the current variant
        if(NOT current_variant IN_LIST supported_variants)
            message(STATUS "  -> Package does not support variant '${current_variant}'")
            message(STATUS "  -> Supported variants: ${supported_variants}")
            message(STATUS "  -> Skipping installation for this variant")
            return()  # Don't install this variant
        endif()
        
        # Use config-specific paths (includes suffix if set)
        set(lib_dest "${KIS_INSTALL_LIBDIR_PF_ARCH}")
        set(bin_dest "${KIS_INSTALL_BINDIR_PF_ARCH}")
        set(variant_suffix "${current_variant}")
        set(path_type "PER_CONFIG (${current_variant})")
    elseif(PACKAGE_ABI_VARIANT STREQUAL "ABI_INVARIANT" OR PACKAGE_ABI_VARIANT STREQUAL "DEFAULT")
        # Legacy support for DEFAULT, now renamed to ABI_INVARIANT for clarity
        # These packages are shared across all configs (header-only or truly ABI-invariant)
        # They should only be installed during plain release/debug builds
        kis_get_current_variant_name(current_variant)
        if(NOT current_variant STREQUAL "release" AND NOT current_variant STREQUAL "debug")
            message(STATUS "  -> ABI_INVARIANT package skipping installation for variant '${current_variant}'")
            message(STATUS "  -> Will use version from base variant (release/debug)")
            return()  # Don't install this variant
        endif()
        set(path_type "ABI_INVARIANT (shared across all configs)")
    endif()
    
    message(STATUS "  -> ABI Variant: ${path_type}")
    message(STATUS "  -> Install path: ${lib_dest}")
    if(variant_suffix)
        message(STATUS "  -> Variant suffix: ${variant_suffix}")
    endif()
    
    # Create export name with variant suffix for PER_CONFIG packages
    if(variant_suffix)
        set(export_name "${PACKAGE_NAME}-targets-${variant_suffix}")
    else()
        set(export_name "${PACKAGE_NAME}-targets")
    endif()
    
    install(TARGETS ${PACKAGE_NAME}
        EXPORT ${export_name}
        LIBRARY DESTINATION ${lib_dest}
        ARCHIVE DESTINATION ${lib_dest}
        RUNTIME DESTINATION ${bin_dest}
        INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )
    _kis_install_package_common_steps("${variant_suffix}")
endfunction()

function(kis_install_interface_package)
    include("${CMAKE_CURRENT_SOURCE_DIR}/kis.package.cmake")
    message(STATUS "Installing INTERFACE package: ${PACKAGE_NAME} (v${PACKAGE_VERSION})")
    
    # Interface packages are always DEFAULT (header-only, ABI-invariant)
    set(variant_suffix "")
    
    install(TARGETS ${PACKAGE_NAME} EXPORT ${PACKAGE_NAME}-targets)
    _kis_install_package_common_steps("${variant_suffix}")
endfunction()

function(kis_install_assets)
    # --- 1. Install Common Assets ---
    # Look for a 'public_assets' directory and install its contents.
    set(common_assets_src "${CMAKE_CURRENT_SOURCE_DIR}/public_assets")
    if(IS_DIRECTORY "${common_assets_src}")
        message(STATUS "Configuring common asset installation for package '${PACKAGE_NAME}'")
        install(DIRECTORY "${common_assets_src}/"
                DESTINATION "${KIS_INSTALL_ASSETSDIR_COMMON}/${PACKAGE_NAME}"
                USE_SOURCE_PERMISSIONS)
    endif()

    # --- 2. Install Platform-Specific Assets ---
    # Look for a 'platform_assets' directory.
    set(platform_assets_src_base "${CMAKE_CURRENT_SOURCE_DIR}/platform_assets")
    if(IS_DIRECTORY "${platform_assets_src_base}")
        # Loop through each platform tag (e.g., windows, desktop).
        foreach(tag ${KIS_PLATFORM_TAGS})
            set(platform_assets_source "${platform_assets_src_base}/${tag}")
            # If a directory for the tag exists, install its contents.
            if(IS_DIRECTORY "${platform_assets_source}")
                message(STATUS "Configuring platform asset installation for package '${PACKAGE_NAME}' with tag '${tag}'")
                install(DIRECTORY "${platform_assets_source}/"
                        DESTINATION "platform_assets/${tag}/${PACKAGE_NAME}"
                        USE_SOURCE_PERMISSIONS)
            endif()
        endforeach()
    endif()
endfunction()