# KIS Build System Modules

This directory contains the modular CMake components that comprise the KIS SDK build system. Each module is focused on a specific aspect of the build process, promoting maintainability and reusability.

## Module Overview

### Core Infrastructure
- **`utils.cmake`** - Common utility functions used across modules (regex escaping, URL validation, error formatting, list parsing)
- **`kis_build_system.cmake`** - Master module that includes all others; entry point for the build system
- **`env_setup.cmake`** - Environment initialization and FetchContent cache configuration
- **`diagnostics.cmake`** - Build environment validation and troubleshooting utilities

### Platform & Configuration
- **`platform_setup.cmake`** - Detects host platform (windows, linux, macos) and architecture
- **`platforms.cmake`** - Platform specialization API (`kis_add_platform_specializations`)
- **`paths.cmake`** - Sets up SDK installation paths and directory structure
- **`sdk_options.cmake`** - User-configurable build options (tests, samples, trusted URLs, etc.)
- **`sdk_presets.cmake`** - Compiler flags, warnings, and C++ standard settings
- **`sdk_versions.cmake`** - Pinned versions for third-party dependencies
- **`sdk_variants.cmake`** ⭐ **NEW** - Configuration variant system for ABI compatibility and granular per-package selection
- **`presets_logic.cmake`** - Applies SDK build settings to targets
- **`compiler_cache.cmake`** ⭐ **NEW** - Auto-detects and enables ccache/sccache for faster rebuilds
- **`dependency_graph.cmake`** ⭐ **NEW** - Exports dependency relationships to DOT format for visualization
- **`build_profiling.cmake`** ⭐ **NEW** - Tracks and reports build times for performance analysis
- **`file_utils.cmake`** ⭐ **NEW** - Unified file globbing utilities for consistent file discovery
- **`cache_validation.cmake`** ⭐ **NEW** - Cache staleness detection and environment validation
- **`incremental_validation.cmake`** ⭐ **NEW** - Smart package validation that skips unchanged packages
- **`incremental_dependencies.cmake`** ⭐ **NEW** - Smart dependency fetching that skips unchanged third-party deps
- **`parallel_fetch.cmake`** ⭐ **NEW** - Parallel dependency fetching using Python threading for 3-4x speedup

### Dependency Management
- **`dependencies.cmake`** - Third-party dependency handling (FetchContent), dual-phase linking system
- **`dependency_resolution.cmake`** - First-party package auto-cloning and recursive resolution
- **`discovery.cmake`** - Package discovery, platform overrides, and configuration ordering

### Target & Component Creation
- **`targets.cmake`** - Library creation with platform-specific source resolution (`kis_add_library`)
- **`components.cmake`** - Test, sample, and benchmark helpers (`kis_add_test`, etc.)

### Installation & Packaging
- **`packaging.cmake`** - Package-level installation (`kis_install_package`, `kis_install_interface_package`)
- **`installation.cmake`** - Third-party dependency installation and SDK-level config generation
- **`manifest_validation.cmake`** ⭐ **NEW** - Validates package manifests for consistency
- **`warning_summary.cmake`** ⭐ **NEW** - Collects and displays configuration warnings

## Design Principles

### 1. **Separation of Concerns**
Each module has a single, well-defined responsibility:
- `dependencies.cmake` handles third-party libs
- `dependency_resolution.cmake` handles first-party packages
- `platforms.cmake` handles platform-specific includes/sources

### 2. **Dual-Mode Support**
Every module must work in both:
- **Superbuild Mode**: Building the entire SDK with all packages
- **Standalone Mode**: Building a single package independently

Modules check `BUILDING_WITH_SUPERBUILD` and adapt behavior accordingly.

### 3. **Global State via Properties**
CMake variables are function-scoped. For cross-module communication, use global properties:
```cmake
set_property(GLOBAL PROPERTY KIS_DECLARED_DEPENDENCY_NAMES ${names})
get_property(names GLOBAL PROPERTY KIS_DECLARED_DEPENDENCY_NAMES)
```

**Key Properties:**
- `KIS_DECLARED_DEPENDENCY_NAMES` - List of third-party dependencies
- `KIS_ARGS_<name>` - FetchContent arguments for each dependency
- `KIS_PENDING_LINKS_<target>` - Deferred linking commands (dual-phase system)
- `KIS_OVERRIDE_MAP_KEYS/VALUES` - Platform override mappings
- `KIS_DEP_VERSION_<name>` - Declared version for conflict detection

### 4. **Consistent Naming**
- **Public API**: `kis_*` prefix (e.g., `kis_add_library`, `kis_link_dependencies`)
- **Internal helpers**: `_kis_*` prefix (e.g., `_kis_get_override_map`, `_kis_install_package_common_steps`)
- **Module variables**: `KIS_*` prefix in UPPER_CASE

### 5. **Error Handling**
Use the helpers from `utils.cmake` for consistent, actionable error messages:
```cmake
kis_message_fatal_actionable(
    "Error Title"
    "Detailed problem description"
    "Step-by-step fix instructions"
)
```

## Recent Improvements (October 2025)

### ✅ Warning Summary System
**Solves**: Warnings scattered throughout configure output were easy to miss.

**Implementation**:
- `warning_summary.cmake` - Collects warnings during configuration
- `kis_collect_warning()` - Simple API for adding warnings
- `kis_print_warning_summary()` - Displays all warnings at end with formatting
- Integrated with `kis_message_warning_actionable()` for automatic collection

**Benefits**:
- ✅ **Visibility**: All warnings displayed together at end of configure
- ✅ **Actionable**: Each warning includes context and suggestions
- ✅ **Tracked**: Warning count helps monitor build health

**Usage**:
```cmake
# Collect a warning
kis_collect_warning("Package 'foo' uses deprecated DEFAULT variant")

# Warnings automatically displayed at end:
-- [WARNING] Configuration Warnings (3)
--   1. Package 'foo' uses deprecated DEFAULT variant
--   2. Cannot create imported target for 'bar': manifest not found
--   3. Unknown processor detected
```

---

### ✅ Compiler Cache Auto-Detection
**Solves**: Manual ccache setup required, often forgotten, leading to slower rebuilds.

**Implementation**:
- `compiler_cache.cmake` - Auto-detects ccache or sccache
- Automatically sets `CMAKE_C/CXX_COMPILER_LAUNCHER` if found
- Provides installation hints if not found

**Benefits**:
- ✅ **Zero config**: Works automatically if ccache/sccache installed
- ✅ **Faster rebuilds**: 5-10x speedup on incremental builds
- ✅ **Cross-platform**: Works on Windows, macOS, Linux

**Usage**:
```bash
# Install ccache once
choco install ccache  # Windows
brew install ccache   # macOS
apt install ccache    # Linux

# Then builds automatically use cache
cmake --preset release
```

---

### ✅ Build Time Profiling
**Solves**: No visibility into which packages are slow during configuration.

**Implementation**:
- `build_profiling.cmake` - Timing collection and reporting
- Tracks per-package configuration time
- Displays bar chart visualization in terminal
- Exports detailed report to text file

**Benefits**:
- ✅ **Identify bottlenecks**: See which packages take longest to configure
- ✅ **Track improvements**: Measure impact of optimizations over time
- ✅ **Visual feedback**: Bar chart shows relative times at a glance
- ✅ **Exportable**: Text file for sharing and historical comparison

**Usage**:
```bash
cmake --preset release -DKIS_PROFILE_BUILD=ON

# Output shows:
#   kis_rendering    12.5s  ####################
#   kis_physics       8.2s  #############
#   kis_core          3.1s  #####
```

---

### ✅ Simplified ABI & Config System

The project now uses a simplified model that separates platform, explicit
configuration suffixes, and feature flags. The authoritative description is
available here `TODO` — please consult that
document for package manifest fields, consumer guidance, and migration notes.

---

### ✅ Manifest-Based Platform System
**Solves**: Platform-specific packages can now declare constraints explicitly instead of relying on directory location.

**New Manifest Fields** (`kis.package.cmake`):
```cmake
# Require specific platforms (OR logic)
set(PACKAGE_PLATFORMS "windows" "linux")

# Require platform tags (OR logic)  
set(PACKAGE_PLATFORM_TAGS "desktop" "unix")

# Exclude platforms/tags (explicit conflicts)
set(PACKAGE_PLATFORM_EXCLUDES "mobile" "wasm")
```

**Benefits**:
- ✅ **Location-independent**: Package location no longer dictates platform support
- ✅ **Multi-platform packages**: A single package can support multiple platforms
- ✅ **Smart cloning**: Auto-cloned dependencies are placed in correct platform subdirectory
- ✅ **Early validation**: Build fails fast with clear error if platform is incompatible
- ✅ **Explicit constraints**: No more silent failures from wrong platform usage

**New Utils Functions**:
- `kis_read_package_manifest()` - Parse manifest fields into variables
- `kis_validate_package_platform()` - Check platform compatibility with actionable errors
- `kis_get_package_platform_preference()` - Determine optimal subdirectory for package

**Module Changes**:
- `discovery.cmake` - Validates all discovered packages against current platform
- `dependency_resolution.cmake` - Clones packages to platform-specific subdirs when needed
- Package templates - Include comprehensive platform constraint examples

### ✅ Centralized Utilities (`utils.cmake`)
Eliminates code duplication across modules:
- `kis_regex_escape()` - Safe regex escaping (used in URL prefix matching)
- `kis_is_url_trusted()` - Centralized URL validation against trusted prefixes
- `kis_message_fatal_actionable()` / `kis_message_warning_actionable()` - Consistent error formatting
- `kis_list_to_string()` - Human-readable list formatting for debug output
- `kis_parse_triplet_list()` - Robust parsing of `name;url;tag` dependency lists
- `kis_build_override_map_parse()` - Centralized override map parsing

### ✅ Improved Error Messages
All fatal errors now include:
- Detailed problem description
- ✅ Actionable fix instructions with examples
- Current state information for debugging

### ✅ Version Conflict Detection
`kis_handle_dependency()` now warns when different packages request different versions of the same dependency.

### ✅ Diagnostic Mode
Set `KIS_DIAGNOSTIC_MODE=ON` for verbose debugging:
```bash
cmake -DKIS_DIAGNOSTIC_MODE=ON --preset sdk-base
```

### ✅ Environment Validation
`kis_validate_environment()` checks:
- Git availability (if needed for package resolution)
- CMake version compatibility
- Compiler detection
- Platform detection
- Ninja availability (if using Ninja generator)

## Module Dependencies

```
kis_build_system.cmake (master)
  ├─ utils.cmake (no deps - must be first!)
  ├─ components.cmake
  ├─ dependencies.cmake
  │    └─ utils.cmake
  ├─ dependency_resolution.cmake
  │    └─ utils.cmake
  ├─ discovery.cmake
  ├─ env_setup.cmake
  ├─ installation.cmake
  ├─ packaging.cmake
  ├─ paths.cmake
  ├─ platforms.cmake
  ├─ targets.cmake
  └─ presets_logic.cmake
```

**Important**: `utils.cmake` is included first and has no dependencies on other modules.

## Platform System Architecture

### Overview
The KIS SDK uses a **manifest-based platform system** that separates platform constraints from directory structure. This enables explicit platform declarations, multi-platform packages, and smart dependency resolution.

### Platform Hierarchy

```
kis_packages/
  ├─ kis_core/              # Common (all platforms)
  ├─ kis_profiling/         # Common (all platforms)
  ├─ windows/
  │   └─ kis_win32_api/     # Windows-specific
  ├─ linux/
  │   └─ kis_x11_utils/     # Linux-specific
  └─ android/
      └─ kis_android_jni/   # Android-specific
```

**Platform Tags** (from `platform_setup.cmake`):
- `windows` → `["desktop", "windows"]`
- `linux` → `["posix", "unix", "desktop", "linux"]`
- `android` → `["unix", "mobile", "android"]`

### Manifest-Based Constraints

Packages declare platform requirements in `kis.package.cmake`:

```cmake
# Example 1: Windows-only package
set(PACKAGE_PLATFORMS "windows")

# Example 2: Desktop-only (Windows OR Linux OR macOS)
set(PACKAGE_PLATFORM_TAGS "desktop")

# Example 3: Multi-platform with exclusions
set(PACKAGE_PLATFORMS "windows" "linux")
set(PACKAGE_PLATFORM_EXCLUDES "mobile")

# Example 4: No constraints (cross-platform)
# Leave all fields unset
```

### Discovery & Validation Flow

1. **Discovery** (`discovery.cmake`):
   - Scans `kis_packages/` and all platform subdirectories
   - Reads each package's manifest
   - **Validates platform compatibility** using `kis_validate_package_platform()`
   - Fails fast with actionable error if incompatible

2. **Dependency Resolution** (`dependency_resolution.cmake`):
   - Clones missing dependencies to temporary location
   - Reads manifest to determine platform preference
   - **Moves to correct subdirectory** (e.g., `kis_packages/windows/` for Windows-only)
   - Common packages go to root `kis_packages/`

3. **Platform Specializations** (`platforms.cmake`):
   - Adds platform-specific headers/sources from `main/platform/{tag}/`
   - Works independently of package location

### Example: Platform-Specific Package

```cmake
# kis_packages/windows/kis_window_mgr/kis.package.cmake

set(PACKAGE_NAME "kis_window_mgr")
set(PACKAGE_VERSION "1.0.0")
set(PACKAGE_DESCRIPTION "Windows window management API")

# Platform constraints
set(PACKAGE_PLATFORMS "windows")           # Only Windows
set(PACKAGE_PLATFORM_TAGS "desktop")       # Requires desktop
set(PACKAGE_PLATFORM_EXCLUDES "mobile")    # Not for mobile

set(PACKAGE_DEPENDENCIES
    "kis_core;https://github.com/your-org/kis_core.git;main"
)
```

**Build on Windows**: ✅ Package discovered and configured  
**Build on Linux**: ❌ Clear error with instructions

### Example: Multi-Platform Package

```cmake
# kis_packages/kis_input/kis.package.cmake

set(PACKAGE_NAME "kis_input")
set(PACKAGE_PLATFORMS "windows" "linux" "android")  # Works on 3 platforms

# No PACKAGE_PLATFORM_TAGS or EXCLUDES needed
```

This package:
- Can live in root `kis_packages/` (not platform-specific subdirectory)
- Uses `main/platform/{windows,linux,android}/` for platform-specific implementations
- Discovered and configured on any of the 3 platforms

### Migration Guide

**Old System** (directory-based):
```
kis_packages/windows/my_package/  # Implicitly Windows-only
```

**New System** (manifest-based):
```cmake
# kis_packages/windows/my_package/kis.package.cmake
set(PACKAGE_PLATFORMS "windows")  # Explicitly Windows-only
```

**For existing packages**:
1. Add platform fields to `kis.package.cmake` (see templates)
2. For cross-platform packages, leave fields commented out
3. For platform-specific packages, declare constraints explicitly

## Common Patterns

### Adding a New Function

1. **Choose the right module** based on responsibility:
   - Package-level operations → `packaging.cmake`
   - Target-level operations → `targets.cmake`
   - Platform-specific logic → `platforms.cmake`
   - Dependency handling → `dependencies.cmake` or `dependency_resolution.cmake`
   - Utilities/helpers → `utils.cmake`

2. **Follow naming conventions**:
   ```cmake
   # Public API (for package authors)
   function(kis_my_new_function)
   
   # Internal helper (for build system only)
   function(_kis_my_helper_function)
   ```

3. **Use cmake_parse_arguments** for clarity:
   ```cmake
   function(kis_my_function)
       set(options OPTIONAL_FLAG)
       set(oneValueArgs TARGET NAME)
       set(multiValueArgs SOURCES DEPENDENCIES)
       cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
       
       # Access via ARG_TARGET, ARG_SOURCES, etc.
   endfunction()
   ```

4. **Add dual-mode support** if relevant:
   ```cmake
   if(BUILDING_WITH_SUPERBUILD)
       # Superbuild logic
   else()
       # Standalone logic
   endif()
   ```

5. **Use utilities** where appropriate:
   ```cmake
   # Instead of raw message(FATAL_ERROR ...)
   kis_message_fatal_actionable("Title" "Problem" "Solution")
   
   # Instead of manual regex escaping
   kis_regex_escape(escaped_pattern "${input}")
   
   # Instead of manual URL checking
   kis_is_url_trusted(is_safe "${url}" "${KIS_TRUSTED_URL_PREFIXES}")
   ```

### Testing Module Changes

Always test both modes after changes:
```bash
# Test superbuild
cmake --preset sdk-base
cmake --build --preset debug

# Test standalone (pick a package)
cd kis_packages/kis_test_package_b
cmake -B build -S .
cmake --build build
```

## Future Enhancements

### Planned Improvements
- [ ] **Dependency lock file** - Generate/use lock files for reproducible builds
- [ ] **Parallel package configuration** - Speed up superbuild configure time
- [ ] **CMake script tests** - Automated testing of build system functions
- [ ] **Binary caching** - Cache compiled dependencies across builds
- [ ] **Cross-compilation support** - Toolchain files for Android, iOS, WebAssembly
- [ ] **Dependency graph visualization** - Generate Graphviz diagrams of package relationships
- [ ] **SBOM generation** - Software Bill of Materials for compliance

### Identified Technical Debt
- Some modules have `message()` calls that could use the new `utils.cmake` helpers
- `targets.cmake` and `platforms.cmake` have similar file-globbing logic that could be unified
- Cache variable handling could be more robust (detect stale values)

## Troubleshooting

### Common Issues

**"Function not found" errors**
- Ensure `kis_build_system.cmake` is included
- Check if you're using the correct function name (`kis_*` prefix)
- Verify the module defining the function is included in `kis_build_system.cmake`

**Cache not updating**
- Delete `build/` directory: `rm -rf build`
- Or clear specific variables: `cmake -UVAR_NAME ..`
- Or use `FORCE` in `set(...CACHE... FORCE)`

**Platform-specific issues**
- Check `KIS_PLATFORM_TAGS` is set correctly
- Verify platform directories exist: `main/platform/windows/`, etc.
- Enable diagnostic mode: `-DKIS_DIAGNOSTIC_MODE=ON`

## Contributing

When modifying modules:
1. **Maintain backward compatibility** - Don't break existing package CMakeLists.txt
2. **Document breaking changes** - Add migration notes to `CHANGELOG.md`
3. **Test both modes** - Superbuild and standalone
4. **Update this README** - Keep documentation in sync with code
5. **Use utilities** - Don't duplicate code that exists in `utils.cmake`

## Module Checklist

When adding a new module:
- [ ] Add to `kis_build_system.cmake` include list
- [ ] Follow `kis_*` / `_kis_*` naming convention
- [ ] Document all public functions
- [ ] Support both superbuild and standalone modes
- [ ] Use `utils.cmake` helpers instead of duplicating code
- [ ] Add entry to this README's "Module Overview" section
- [ ] Test in both build modes

---

**Last Updated**: October 16, 2025  
**Version**: 0.1.0+refactor
