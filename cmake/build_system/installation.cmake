# cmake/build_system/installation.cmake
#
# Provides the function to generate the top-level KIS_SDKConfig.cmake file
# for the superbuild's installation.

function(generate_sdk_config_file)
    include(CMakePackageConfigHelpers)

    # Note: This function assumes it is being called from the top-level
    # superbuild, so CMAKE_CURRENT_SOURCE_DIR will correctly point to the
    # root of the kis_sdk repository.
    set(template_file "${CMAKE_CURRENT_SOURCE_DIR}/cmake/KIS_SDKConfig.cmake.in")

    if(NOT EXISTS "${template_file}")
        message(FATAL_ERROR "Could not find the SDK config template at '${template_file}'. This file is expected in the root SDK repository.")
    endif()

    configure_package_config_file(
        "${template_file}"
        "${CMAKE_CURRENT_BINARY_DIR}/KIS_SDKConfig.cmake"
        INSTALL_DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/cmake/KIS_SDK
        PATH_VARS CMAKE_INSTALL_PREFIX
    )

    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/KIS_SDKConfig.cmake"
        DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/cmake/KIS_SDK
    )

    message(STATUS "\nConfiguration complete.")
    message(STATUS "Run the 'install' step to build and populate the installation directory.")
    message(STATUS "Consumer projects should add this path to CMAKE_PREFIX_PATH:")
    message(STATUS "  ${CMAKE_INSTALL_PREFIX}")
endfunction()