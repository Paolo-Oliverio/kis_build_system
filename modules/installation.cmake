# kis_build_system/modules/installation.cmake
#
# Provides functions to generate and configure installation artifacts for the SDK.

#
# kis_install_third_party_dependencies
#
# In this refactored system, this function is now a no-op.
# Third-party dependencies that support installation (e.g., doctest, glfw)
# will have their `install()` rules automatically integrated into the main
# build's `install` target when `FetchContent_MakeAvailable` is called.
# This is the modern, standard CMake behavior and avoids conflicts and
# double-install issues.
#
# Our custom packaging logic is now only for our own first-party packages.
#
function(kis_install_third_party_dependencies)
    message(STATUS "Third-party dependency installation is handled automatically by FetchContent.")
    message(STATUS "Well-behaved dependencies with their own install() rules will be installed.")
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