# KIS SDK Build System

[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE.txt)

This repository contains the centralized CMake build and packaging logic for the **KIS SDK**. It is designed as a modular, versioned, and installable CMake package, providing a single source of truth for building all components within the KIS ecosystem.

This package provides a powerful suite of CMake functions, not linkable libraries. Its purpose is to be consumed by other KIS packages to ensure they are built, tested, and installed in a consistent, modern, and robust manner.

## Key Features

*   **Dual-Mode Architecture**: Seamlessly builds KIS packages either as part of the main `kis_sdk` superbuild or as completely standalone projects.
*   **Automated Packaging & Installation**: Provides `kis_install_package()` and `kis_install_interface_package()` to standardize the entire installation process, including generating relocatable CMake package configuration files (`<Package>Config.cmake`) and version files.
*   **Standardized Dependency Helpers**: Offers a consistent API (`kis_handle_dependency`, `kis_link_dependencies`) to declare third-party dependencies that works transparently in both standalone and superbuild modes.
*   **Consistent Component Tooling**: Simplifies project structure with functions like `kis_add_test`, `kis_add_sample`, and `kis_add_benchmark`, which automatically handle IDE folder organization and build configurations.
*   **Advanced Asset Management**: Includes a sophisticated asset installation system (`kis_install_assets`) that supports both traditional file copying and a developer-friendly symlinking mode for rapid iteration.
*   **Self-Contained & Bootstrappable**: Implements a "find-or-fetch" pattern, allowing any standalone package to automatically download these build tools if they aren't already installed, ensuring projects are always buildable with minimal prerequisites.

## How It Works

This is not a typical library you link against; it is a build-time dependency that empowers your `CMakeLists.txt`. KIS packages leverage this system in one of two modes:

1.  **Superbuild Mode**: When built within the main KIS SDK, the superbuild includes this package directly. Its functions and settings become globally available to all sub-packages, ensuring total consistency across the entire SDK.

2.  **Standalone Mode**: When a single KIS package (e.g., `kis_core_utils`) is cloned and built on its own, its `CMakeLists.txt` is responsible for acquiring these build tools. This is achieved through a robust, self-contained mechanism:

    1.  First, it tries to find a pre-installed version on the system via `find_package(kis_build_system)`.
    2.  If not found, it falls back to using `FetchContent` to clone and include this repository automatically at configure time.

This powerful pattern guarantees that every KIS package is independently buildable, testable, and distributable.

## Usage

While you can write a package from scratch, the recommended way to create a new KIS package is by using the official `cookiecutter` templates provided in the KIS SDK, as they handle all the boilerplate for you.

For reference, a typical standalone package's `CMakeLists.txt` includes a block like this to bootstrap the build system:

```cmake
# CMakeLists.txt for a new KIS package

cmake_minimum_required(VERSION 3.20)

# --- 1. Bootstrap the Build System (Only for Standalone Builds) ---
# This block is the key to making a package self-contained. It ensures
# the KIS build functions are available, either from an installed version
# or by fetching them from source.
if(NOT BUILDING_WITH_SUPERBUILD)
    # Prefer a system-installed version first.
    find_package(kis_build_system 0.1.0 QUIET)

    if(NOT kis_build_system_FOUND)
        message(STATUS "kis_build_system not found. Fetching from source...")
        include(FetchContent)
        FetchContent_Declare(
            kis_build_system
            GIT_REPOSITORY https://github.com/Paolo-Oliverio/kis_build_system.git
            GIT_TAG        v0.1.0 # Or a specific commit/branch
        )
        # This makes the kis_* functions available to this script.
        FetchContent_MakeAvailable(kis_build_system)
    endif()
endif()

# --- 2. Define the Package ---
# Load the package manifest (version, name, etc.)
include(kis.package.cmake)
project(${PACKAGE_NAME} VERSION ${PACKAGE_VERSION})

# Define the library target (INTERFACE for header-only)
add_library(${PACKAGE_NAME} ...)
add_library(kis::${PACKAGE_NAME} ALIAS ${PACKAGE_NAME})

# ... target_include_directories, etc. ...

# --- 3. Apply Build Presets and Link Dependencies ---
# These functions are provided by the build system and adapt their
# behavior based on whether this is a standalone or superbuild context.
if(BUILDING_WITH_SUPERBUILD)
    kis_apply_sdk_build_settings_to_target(${PACKAGE_NAME})
else()
    apply_kis_build_presets(${PACKAGE_NAME})
    # In standalone, linking happens immediately.
    # In a superbuild, this function call is deferred.
    ${PACKAGE_NAME}_link_dependencies()
endif()

# --- 4. Install the Package ---
# This single command handles all installation and packaging logic.
kis_install_package()

# --- 5. Add Optional Components ---
if(KIS_BUILD_TESTS)
    kis_add_test(MyTest SOURCES tests/my_test.cpp)
endif()
```

## Contributing

Contributions to the build system should be made with care, as they affect all packages in the SDK. Please open an issue to discuss proposed changes before submitting a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.txt) file for details.