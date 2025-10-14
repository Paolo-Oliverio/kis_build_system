# cmake/build_system/paths.cmake

function(setup_sdk_paths)
    # The SDK_VERSION can be set from a file, git tag, or parent project
    if(NOT DEFINED SDK_VERSION)
        set(SDK_VERSION "0.1.0")
    endif()

    message(STATUS "Setting up KIS SDK paths with version: ${SDK_VERSION}")

    # The canonical variable that controls the root for all installation commands
    # is CMAKE_INSTALL_PREFIX. We must set this variable to our desired versioned path.
    #
    # By default, we place it inside the build directory to keep the source tree clean.
    # The `CACHE` keyword ensures this setting persists across re-configurations
    # and is visible in tools like cmake-gui. A user can still override this
    # on the command line with -DCMAKE_INSTALL_PREFIX=/some/other/path.
    if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
        # If the user has not provided a CMAKE_INSTALL_PREFIX on the command line,
        # we set our versioned default.
        set(DEFAULT_SDK_INSTALL_ROOT "${CMAKE_SOURCE_DIR}/_install/kis_sdk-${SDK_VERSION}")
        set(CMAKE_INSTALL_PREFIX "${DEFAULT_SDK_INSTALL_ROOT}"
            CACHE PATH "Root directory for the KIS SDK installation." FORCE
        )
    endif()
    # If the user provides a CMAKE_INSTALL_PREFIX, we respect their choice.
    # This allows them to install the SDK to a system location like /usr/local if they wish.

    # CMAKE_INSTALL_PREFIX
    # is now the single source of truth for the installation path.
    message(STATUS "KIS SDK Superbuild")
    message(STATUS "  - Source Directory: ${CMAKE_CURRENT_SOURCE_DIR}")
    message(STATUS "  - Build Directory:  ${CMAKE_BINARY_DIR}")
    message(STATUS "  - Install Root:     ${CMAKE_INSTALL_PREFIX}")
endfunction()