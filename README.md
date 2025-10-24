### **README for the `kis_build_system` (Framework Repository)**

# KIS SDK Build System

[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE.txt)

This repository contains the centralized CMake build and packaging logic for the **KIS SDK**. It is a modular, versioned, and installable CMake package that provides a declarative, powerful, and consistent framework for building all components within the KIS ecosystem.

This is a **build system framework**, not a linkable library. It is consumed by KIS packages to automate and standardize their entire development lifecycle, from configuration and dependency management to testing and installation.

## Core Philosophy: Declarative & Automated

The KIS SDK build system is architected around a simple principle: **describe your package in a manifest, and the build system will handle the rest.**

A single `kis.package.json` file at the root of your package is the single source of truth. It defines the package's metadata, dependencies, build variants, and platform compatibility. The build system reads this manifest and intelligently generates all the necessary CMake logic, eliminating boilerplate and ensuring consistency across the entire SDK.

## Key Features

*   **Manifest-Driven Configuration**: A simple `kis.package.json` file declares everything the build system needs to know.
*   **Dual-Mode Architecture**: Seamlessly builds packages as part of the `kis_sdk` **superbuild** or as completely **standalone** projects for isolated development and testing.

### Advanced Configuration & Specialization

*   **Platform Overrides**: The system automatically detects and applies platform-specific source files, headers, and assets from conventional directories (`main/platform/windows/`, `platform_assets/desktop/`). This enables transparent, compile-time specialization without `#ifdef` clutter.
*   **Package Overrides**: A powerful mechanism allows a platform-specific package (e.g., `kis_packages/windows/kis_renderer`) to completely replace a generic implementation (`kis_packages/kis_renderer`), enabling deeply specialized backends.
*   **Feature-Based Package Filtering**: Associate packages with features (`"features": ["tools", "editor"]`). The build system will only configure and build packages if their required feature flags are enabled, keeping builds lean and focused.
*   **ABI-Aware Build Variants**: Define custom, ABI-compatible build types like `profiling` or `asan`. The system manages artifact paths and reuses pre-built dependencies from compatible base variants (`release` or `debug`), dramatically speeding up multi-config workflows.

### Precise & Automated Dependency Management

*   **Component Scoping**: Declare dependencies that are only for `tests`, `samples`, or `benchmarks` using the `"scope"` property, preventing them from linking against your main library target.
*   **Implicit Conditioning**: Scoped dependencies are automatically enabled or disabled based on build flags (`KIS_BUILD_TESTS`, etc.), removing redundant `condition` boilerplate from the manifest.
*   **Target Mapping**: Explicitly map dependency names (e.g., `glfw3`) to their actual CMake targets (`glfw`) using the `"targets"` property, resolving common integration issues.
*   **Automated Fetching**: All dependencies (first- and third-party) are automatically fetched via `FetchContent` from Git or URL archives.

### Exceptional Developer Experience (DevEx) Tooling

*   **Automatic Compiler Caching**: Speeds up rebuilds by automatically detecting and enabling `ccache` or `sccache`.
*   **Incremental Builds**: Smartly re-validates and re-fetches only the packages and dependencies that have actually changed.
*   **Parallel Dependency Fetching**: Slashes initial configuration time by fetching dependencies concurrently.
*   **Build Profiling & Graphing**: Provides tools to identify configuration bottlenecks and visualize the project's dependency architecture.
*   **Standardized Structure & Installation**: A consistent API (`kis_define_package`, `kis_add_test`, `kis_install_package`) enforces a common structure and handles the entire installation process, including generating relocatable CMake package configuration files.

## Usage in a KIS Package

Creating a KIS package is incredibly simple. All the complexity is handled by the build system.

**1. Create `kis.package.json`:**

This manifest defines your package, its dependencies, and its behavior.

```json
{
  "name": "kis_renderer_gl",
  "version": "0.1.0",
  "type": "LIBRARY",
  "description": "OpenGL rendering backend.",
  "features": ["renderer"],
  "overrides": ["kis_renderer_base"],
  "platform": { "tags": ["desktop"] },
  "dependencies": {
    "thirdParty": [
      {
        "name": "glad",
        "git": "...", "tag": "...",
        "scope": ["main"]
      },
      {
        "name": "doctest",
        "git": "...", "tag": "...",
        "scope": ["tests"]
      }
    ]
  }
}
```

**2. Create `CMakeLists.txt`:**

The package's CMake script is minimal and declarative.

```cmake
# kis_renderer_gl/CMakeLists.txt
cmake_minimum_required(VERSION 3.20)
project(kis_renderer_gl)

# This block enables standalone development. It's ignored in a superbuild.
if(CMAKE_PROJECT_IS_TOP_LEVEL)
    include(cmake/build_system_bootstrap.cmake)
endif()

# --- 1. Define the Main Library ---
# This single command reads the manifest, creates the target, and links
# all dependencies with 'main' or 'all' scope.
kis_define_package(
    SOURCES
        main/src/renderer.cpp
)

# --- 2. Define Optional Components ---
# The build system automatically links dependencies with 'tests' scope.
# No need to manually specify 'doctest' here!
if(KIS_BUILD_TESTS)
    kis_add_test(kis_renderer_gl_tests
        SOURCES
            tests/renderer.test.cpp
    )
endif()
```

This simple setup is all that's needed. The build system handles the rest, ensuring it works seamlessly whether you're building this one package by itself or as part of the entire SDK.

## Contributing

Contributions to the build system should be made with care, as they affect all packages in the SDK. Please open an issue to discuss proposed changes before submitting a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE.txt](LICENSE.txt) file for details.