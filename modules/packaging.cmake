# cmake/build_system/packaging.cmake
# Provides helper functions for installing and exporting KIS SDK packages.

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

#
# kis_install_package
#
# Encapsulates all the logic for installing a package's targets and generating
# the necessary CMake config files to make it findable via find_package().
# It assumes a file named 'kis.package.cmake' exists in the current source dir.
#
function(kis_install_package)
    # Load the package metadata
    include("${CMAKE_CURRENT_SOURCE_DIR}/kis.package.cmake")

    if(NOT PACKAGE_NAME)
        message(FATAL_ERROR "PACKAGE_NAME is not set in kis.package.cmake")
    endif()
    if(NOT PACKAGE_VERSION)
        message(FATAL_ERROR "PACKAGE_VERSION is not set in kis.package.cmake")
    endif()

    message(STATUS "Installing package: ${PACKAGE_NAME} (version: ${PACKAGE_VERSION})")

    if(NOT DEFINED PACKAGE_VERSION_MAJOR)
        string(REGEX MATCH "^[0-9]+" PACKAGE_VERSION_MAJOR "${PACKAGE_VERSION}")
        if(NOT PACKAGE_VERSION_MAJOR)
            message(FATAL_ERROR "${PACKAGE_NAME} : PACKAGE_VERSION_MAJOR could not be extracted from PACKAGE_VERSION")
        endif()
    endif()

    if(NOT DEFINED PACKAGE_DESCRIPTION)
        set(PACKAGE_DESCRIPTION "no description provided")
    endif()

    set_target_properties(${PACKAGE_NAME} PROPERTIES
        VERSION ${PACKAGE_VERSION}
        SOVERSION ${PACKAGE_VERSION_MAJOR}
        DESCRIPTION "${PACKAGE_DESCRIPTION}"
    )

    install(TARGETS ${PACKAGE_NAME}
        EXPORT ${PACKAGE_NAME}-targets
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )

 if(NOT DEFINED PACKAGE_PUBLIC_INCLUDE_DIR)
        set(PACKAGE_PUBLIC_INCLUDE_DIR "main/include")
    endif()

    set(public_include_dir_path "${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE_PUBLIC_INCLUDE_DIR}")

    if(EXISTS "${public_include_dir_path}")
        # Install the contents of the specified directory.
        # The trailing slash is important to copy contents, not the folder itself.
        install(DIRECTORY "${public_include_dir_path}/"
            DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
        )
    endif()

    install(EXPORT ${PACKAGE_NAME}-targets
        FILE        ${PACKAGE_NAME}-targets.cmake
        NAMESPACE   kis::
        DESTINATION lib/cmake/${PACKAGE_NAME}
    )

    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}ConfigVersion.cmake"
        VERSION "${PACKAGE_VERSION}"
        COMPATIBILITY AnyNewerVersion
    )

    set(custom_config_template "${CMAKE_CURRENT_SOURCE_DIR}/cmake/config/${PACKAGE_NAME}Config.cmake.in")
    if(EXISTS "${custom_config_template}")
        message(STATUS "Package '${PACKAGE_NAME}' provides a custom config template.")
        set(config_template_to_use "${custom_config_template}")
    else()
        message(STATUS "Package '${PACKAGE_NAME}' using generic SDK config template.")
        set(config_template_to_use "${KIS_GENERIC_CONFIG_TEMPLATE}")
    endif()

    configure_package_config_file(
        "${config_template_to_use}"
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}Config.cmake"
        INSTALL_DESTINATION lib/cmake/${PACKAGE_NAME}
    )

    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}Config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}ConfigVersion.cmake"
        DESTINATION lib/cmake/${PACKAGE_NAME}
    )
endfunction()

#
# kis_install_interface_package
#
# Encapsulates the installation logic for a header-only INTERFACE package.
# It does NOT install binaries, but handles headers and CMake export files.
#
function(kis_install_interface_package)
    # Load the package metadata (identical to a regular package)
    include("${CMAKE_CURRENT_SOURCE_DIR}/kis.package.cmake")

    if(NOT PACKAGE_NAME)
        message(FATAL_ERROR "PACKAGE_NAME is not set in kis.package.cmake")
    endif()
    if(NOT PACKAGE_VERSION)
        message(FATAL_ERROR "PACKAGE_VERSION is not set in kis.package.cmake")
    endif()

    message(STATUS "Installing INTERFACE package: ${PACKAGE_NAME} (version: ${PACKAGE_VERSION})")

    # An INTERFACE library has no binary artifacts (VERSION, SOVERSION, etc.),
    # so we skip the set_target_properties() and the main install(TARGETS...) call.

    # 1. Install public headers (identical to a regular package)
    if(NOT DEFINED PACKAGE_PUBLIC_INCLUDE_DIR)
        set(PACKAGE_PUBLIC_INCLUDE_DIR "main/include")
    endif()
    set(public_include_dir_path "${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE_PUBLIC_INCLUDE_DIR}")
    if(EXISTS "${public_include_dir_path}")
        install(DIRECTORY "${public_include_dir_path}/"
            DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
        )
    endif()

    # 2. Add the INTERFACE target to an export set.
    # This is a minimal version of install(TARGETS...) that only registers
    # the target for export without trying to install any files for it.
    install(TARGETS ${PACKAGE_NAME} EXPORT ${PACKAGE_NAME}-targets)

    # 3. Install the export definition file (identical to a regular package)
    install(EXPORT ${PACKAGE_NAME}-targets
        FILE        ${PACKAGE_NAME}-targets.cmake
        NAMESPACE   kis::
        DESTINATION lib/cmake/${PACKAGE_NAME}
    )

    # 4. Generate and install version/config files (identical to a regular package)
    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}ConfigVersion.cmake"
        VERSION "${PACKAGE_VERSION}"
        COMPATIBILITY AnyNewerVersion
    )

    set(custom_config_template "${CMAKE_CURRENT_SOURCE_DIR}/cmake/config/${PACKAGE_NAME}Config.cmake.in")
    if(EXISTS "${custom_config_template}")
        set(config_template_to_use "${custom_config_template}")
    else()
        set(config_template_to_use "${KIS_GENERIC_CONFIG_TEMPLATE}")
    endif()

    configure_package_config_file(
        "${config_template_to_use}"
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}Config.cmake"
        INSTALL_DESTINATION lib/cmake/${PACKAGE_NAME}
    )

    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}Config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}ConfigVersion.cmake"
        DESTINATION lib/cmake/${PACKAGE_NAME}
    )
endfunction()