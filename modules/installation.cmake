# kis_build_system/modules/installation.cmake
#
# Provides functions to generate and configure installation artifacts for the SDK.

#
# kis_install_third_party_dependencies
#
# Scans all declared third-party dependencies, resolves their targets (including aliases),
# and configures them to be installed correctly within the SDK's layered structure.
#
# IMPORTANT: Most third-party libraries (like GLFW) already provide their own CMake
# config files and install rules via FetchContent. We DON'T re-export them to avoid
# "target exported multiple times" errors. Instead, we rely on the library's own
# installation and ensure packages can find them via find_package().
#
function(kis_install_third_party_dependencies)
    get_property(dep_names GLOBAL PROPERTY KIS_DECLARED_DEPENDENCY_NAMES)
    if(NOT dep_names)
        return() # No third-party dependencies to install.
    endif()

    list(REMOVE_DUPLICATES dep_names)
    
    # List of third-party libraries that provide their own CMake config and should
    # NOT be re-exported by the SDK. Add libraries here as needed.
    set(SELF_INSTALLING_DEPS
        glfw      # GLFW provides glfw3Config.cmake and glfw3Targets.cmake
        doctest   # doctest provides its own config
        # Add more as you encounter them
    )
    set(TPL_CONFIG_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/kis_build_system/templates/GenericThirdPartyConfig.cmake.in")

    if(NOT EXISTS "${TPL_CONFIG_TEMPLATE}")
        kis_collect_warning("Third-party config template not found at '${TPL_CONFIG_TEMPLATE}'. Skipping installation for third-party packages.")
        return()
    endif()

    # Track which third-party targets we're installing to avoid duplicates
    set(installed_targets "")

    foreach(dep_name ${dep_names})
        # Skip dependencies that provide their own CMake config to avoid export conflicts
        if(dep_name IN_LIST SELF_INSTALLING_DEPS)
            message(STATUS "Skipping third-party '${dep_name}' - it provides its own CMake config")
            continue()
        endif()
        set(found_target "")
        if(TARGET "${dep_name}::${dep_name}")
            set(found_target "${dep_name}::${dep_name}")
        elseif(TARGET ${dep_name})
            set(found_target ${dep_name})
        else()
            message(WARNING "Could not find a target for third-party dependency '${dep_name}'. Cannot install its package configuration.")
            continue()
        endif()

        # Resolve ALIAS targets before calling install().
        set(install_target ${found_target})
        get_target_property(aliased_for ${found_target} ALIASED_TARGET)
        if(aliased_for)
            message(STATUS "Resolving alias target '${found_target}' to real target '${aliased_for}' for installation.")
            set(install_target ${aliased_for})
        endif()

        # Check if this target was already installed (avoid duplicates)
        if("${install_target}" IN_LIST installed_targets)
            message(STATUS "Third-party target '${install_target}' already installed, skipping.")
            continue()
        endif()
        list(APPEND installed_targets ${install_target})

        # Mark this target as a third-party dependency so packages can exclude it from their exports
        set_property(GLOBAL APPEND PROPERTY KIS_THIRD_PARTY_INSTALLED_TARGETS ${install_target})

        message(STATUS "Generating install configuration for dependency: ${dep_name}")
        set(TPL_EXPORT_NAME "${dep_name}")
        set(TPL_NAMESPACE "${dep_name}")
        set(TPL_TARGET_NAME "${dep_name}")
        set(TPL_CMAKE_INSTALL_DIR "${KIS_INSTALL_CMAKEDIR_COMMON}/${dep_name}")

        # Install in a separate export set (not part of any package export)
        install(TARGETS ${install_target}
            EXPORT ${TPL_EXPORT_NAME}-targets
            LIBRARY DESTINATION ${KIS_INSTALL_LIBDIR_PF_ARCH}
            ARCHIVE DESTINATION ${KIS_INSTALL_LIBDIR_PF_ARCH}
            RUNTIME DESTINATION ${KIS_INSTALL_BINDIR_PF_ARCH}
            INCLUDES DESTINATION ${KIS_INSTALL_INCLUDEDIR_COMMON}
        )
        install(EXPORT ${TPL_EXPORT_NAME}-targets
            FILE        ${TPL_EXPORT_NAME}-targets.cmake
            NAMESPACE   ${TPL_NAMESPACE}::
            DESTINATION ${TPL_CMAKE_INSTALL_DIR}
        )

        configure_file(${TPL_CONFIG_TEMPLATE} "${CMAKE_CURRENT_BINARY_DIR}/${dep_name}Config.cmake" @ONLY)
        install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${dep_name}Config.cmake" DESTINATION ${TPL_CMAKE_INSTALL_DIR})
    endforeach()
endfunction()


#
# generate_sdk_config_file
#
# Generates the top-level KIS_SDKConfig.cmake file for the superbuild's installation.
#
function(generate_sdk_config_file)
    include(CMakePackageConfigHelpers)

    set(template_file "${CMAKE_CURRENT_SOURCE_DIR}/cmake/KIS_SDKConfig.cmake.in")
    if(NOT EXISTS "${template_file}")
        message(FATAL_ERROR "Could not find the SDK config template at '${template_file}'.")
    endif()

    configure_package_config_file(
        "${template_file}"
        "${CMAKE_CURRENT_BINARY_DIR}/KIS_SDKConfig.cmake"
        INSTALL_DESTINATION "${KIS_INSTALL_CMAKEDIR_COMMON}/KIS_SDK"
        PATH_VARS CMAKE_INSTALL_PREFIX KIS_INSTALL_CMAKEDIR_COMMON
    )

    # Also configure the variant selection file
    set(variants_template "${CMAKE_CURRENT_SOURCE_DIR}/cmake/KIS_SDKVariants.cmake.in")
    if(EXISTS "${variants_template}")
        configure_package_config_file(
            "${variants_template}"
            "${CMAKE_CURRENT_BINARY_DIR}/KIS_SDKVariants.cmake"
            INSTALL_DESTINATION "${KIS_INSTALL_CMAKEDIR_COMMON}/KIS_SDK"
        )
        
        install(FILES
            "${CMAKE_CURRENT_BINARY_DIR}/KIS_SDKConfig.cmake"
            "${CMAKE_CURRENT_BINARY_DIR}/KIS_SDKVariants.cmake"
            DESTINATION "${KIS_INSTALL_CMAKEDIR_COMMON}/KIS_SDK"
        )
    else()
        install(FILES
            "${CMAKE_CURRENT_BINARY_DIR}/KIS_SDKConfig.cmake"
            DESTINATION "${KIS_INSTALL_CMAKEDIR_COMMON}/KIS_SDK"
        )
    endif()

    message(STATUS "\nConfiguration complete.")
    message(STATUS "Run the 'install' step to build and populate the installation directory.")
    message(STATUS "Consumer projects should add this path to CMAKE_PREFIX_PATH:")
    message(STATUS "  ${CMAKE_INSTALL_PREFIX}")
endfunction()