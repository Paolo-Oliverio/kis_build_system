# KIS SDK Build System

[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE.txt)

This repository contains the centralized CMake build and packaging logic for the **kis_sdk**. It is designed as a modular, versioned, and installable CMake package, providing a single source of truth for building all components within the kis_ ecosystem.

This package provides CMake functions, not libraries. Its purpose is to be consumed by other kis_ packages to ensure they are built, tested, and installed in a consistent and robust manner.

## Key Features

-   **Context-Aware Building**: Enables kis_ packages to be built seamlessly either as part of the main [kis_sdk](https://github.com/Paolo-Oliverio/kis_sdk) or as standalone projects.
-   **Dependency Management**: Provides helpers for declaring and resolving both first-party (kis_) and third-party dependencies.
-   **Automated Packaging**: Standardizes the installation and CMake package configuration (`<Package>Config.cmake`) generation for all kis_ libraries.
-   **Consistent Tooling**: Enforces consistent settings and options across the entire SDK.
-   **Component Registration**: Offers simple functions (`kis_add_test`, `kis_add_sample`) for adding optional components like tests and samples.

## How It Works

This is not a typical library that you link against. Instead, it's a "build-time" dependency. KIS packages use this system in one of two ways:

1.  **Superbuild Mode**: When built as part of the main KIS SDK, the superbuild includes this package directly. Its functions become globally available to all other packages, which can then use them without any extra setup.

2.  **Standalone Mode**: When a KIS package (e.g., `kis_core_utils`) is cloned and built on its own, its `CMakeLists.txt` is responsible for acquiring these build tools. It does this by:
    a. First, trying to find a pre-installed version using `find_package(kis_build_system)`.
    b. If not found, falling back to `FetchContent` to clone this repository automatically.

This "find-or-fetch" mechanism ensures that a package is always self-contained and buildable with a minimal set of prerequisites (CMake and a compiler).

## Usage

Direct usage of this repository is uncommon. It is designed to be used implicitly by other KIS packages.
Templates for various kind of packages will be available to kickstart kis_ package development.

As now to use this build system a `CMakeLists.txt` should include a block similar to this:

```cmake
# CMakeLists.txt for a new KIS package

cmake_minimum_required(VERSION 3.20)

# --- 1. Find-or-Fetch the KIS Build System (Standalone Mode Only) ---
if(NOT BUILDING_WITH_SUPERBUILD)
    find_package(kis_build_system 0.1.0 QUIET)

    if(NOT kis_build_system_FOUND)
        message(STATUS "kis_build_system not found. Fetching from source...")
        include(FetchContent)
        FetchContent_Declare(
            kis_build_system
            GIT_REPOSITORY https://github.com/Paolo-Oliverio/kis_build_system.git
            GIT_TAG        v0.1.0
        )
        FetchContent_MakeAvailable(kis_build_system)
    endif()
endif()

# --- 2. Now, use the provided functions ---
include(kis.package.cmake)
project(${PACKAGE_NAME})

# ... define your library target ...

# Install the package using the centralized logic
kis_install_package()

# Add a test using the centralized helper
if(KIS_BUILD_TESTS)
    kis_add_test(MyTest SOURCES tests/my_test.cpp)
endif()
```

## Contributing

Contributions to the build system should be made with care, as they affect all packages in the SDK. Please open an issue to discuss proposed changes before submitting a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
