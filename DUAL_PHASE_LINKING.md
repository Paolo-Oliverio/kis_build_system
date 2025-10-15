# Dual-Phase Dependency System

## Overview

The KIS SDK build system uses a **dual-phase approach** to handle dependencies, ensuring that all targets are created before any linking occurs. This prevents "target not found" errors in complex dependency graphs.

## The Two Phases

### Phase 1: Target Creation & Configuration
During this phase, all packages are discovered and their targets are created:

1. **Package Discovery** (`discover_and_map_packages`)
   - Scans `kis_packages/` directory
   - Finds all packages with `CMakeLists.txt`
   - Detects platform-specific overrides

2. **Package Configuration** (`configure_discovered_packages`)
   - Calls `add_subdirectory()` for each package
   - Creates all library targets
   - Applies build settings, includes, etc.
   - **Defers all linking commands** via `kis_link_dependencies()`

3. **Third-Party Dependencies** (`kis_populate_declared_dependencies`)
   - Fetches external dependencies (doctest, fmt, etc.)
   - Makes them available globally

### Phase 2: Dependency Linking
After all targets exist, the actual linking happens:

4. **Link All Dependencies** (`link_all_package_dependencies`)
   - Executes deferred link commands
   - Applies dependency overrides
   - Calls `target_link_libraries()` for each target

## Build Modes

### Superbuild Mode (SDK Development)
When building the entire SDK:

- **First-Party Dependencies**: Automatically discovered from `kis_packages/`
- **Missing Dependencies**: Can be auto-cloned via `kis_resolve_and_sync_packages()`
- **Linking**: Always deferred to Phase 2
- **Flag**: `BUILDING_WITH_SUPERBUILD=TRUE`

### Standalone Mode (Single Package)
When building a package independently:

- **First-Party Dependencies**: Fetched via `FetchContent` from git URLs
- **Linking**: Executed immediately (backward compatible)
- **Flag**: `BUILDING_WITH_SUPERBUILD` not defined

## API for Package Authors

### Declaring First-Party Dependencies

In `kis.package.cmake`:

```cmake
set(PACKAGE_DEPENDENCIES
    "kis_test_package_a;https://github.com/Paolo-Oliverio/kis_test_package_a.git;main"
    "kis_core;https://github.com/your-org/kis_core.git;v1.2.0"
)
```

Format: `"name;git_url;git_tag"` (semicolons create CMake list items)

### Handling Dependencies in CMakeLists.txt

```cmake
# 1. Include metadata
include(kis.package.cmake)
project(${PACKAGE_NAME} VERSION ${PACKAGE_VERSION})

# 2. Handle first-party dependencies
kis_handle_first_party_dependencies()

# 3. Create your target
kis_add_library(${PACKAGE_NAME} main/src/foo.cpp)

# 4. Link dependencies (automatically deferred in superbuild)
kis_link_dependencies(TARGET ${PACKAGE_NAME} 
    PUBLIC kis::other_package
    PRIVATE kis::another_package
)
```

### Key Functions

#### `kis_handle_first_party_dependencies()`
- **Superbuild**: Does nothing (discovery handles it)
- **Standalone**: Fetches dependencies via FetchContent
- **Call this early** in your CMakeLists.txt, after `project()`

#### `kis_link_dependencies(TARGET <name> PUBLIC/PRIVATE/INTERFACE <deps>)`
- **Superbuild**: Defers linking to Phase 2
- **Standalone**: Links immediately
- **Always use this** instead of raw `target_link_libraries()`

#### `kis_defer_link_dependencies(TARGET <name> ...)`
- Explicitly defers linking (advanced usage)
- Useful for complex scenarios

#### `kis_execute_deferred_links(TARGET_NAME)`
- Internal function called by superbuild in Phase 2
- Package authors don't need to call this

## Dependency Resolution Process

### In Superbuild Mode

```
1. kis_resolve_and_sync_packages()
   ↓ Scans existing packages in kis_packages/
   ↓ Reads PACKAGE_DEPENDENCIES from each
   ↓ Clones missing packages from git URLs
   ↓ Repeats until all transitive deps resolved

2. discover_and_map_packages()
   ↓ Scans all packages (common + platform-specific)
   ↓ Builds list of packages to configure

3. configure_discovered_packages()
   ↓ add_subdirectory() for each package
   ↓ Targets created
   ↓ Links deferred

4. kis_populate_declared_dependencies()
   ↓ Fetches third-party libs (doctest, etc.)

5. link_all_package_dependencies()
   ↓ kis_execute_deferred_links() for each target
   ↓ All linking happens here
```

### In Standalone Mode

```
1. kis_handle_first_party_dependencies()
   ↓ FetchContent_Declare() for each dep
   ↓ FetchContent_MakeAvailable()
   ↓ Dependencies built immediately

2. Target creation
   ↓ kis_add_library() etc.

3. kis_link_dependencies()
   ↓ Links immediately (no deferral)
```

## Why Dual-Phase?

### Problem Without Dual-Phase
```cmake
# Package A
add_library(A ...)
target_link_libraries(A PUBLIC B)  # ERROR: B doesn't exist yet!

# Package B (configured later)
add_library(B ...)
```

### Solution With Dual-Phase
```cmake
# PHASE 1: Create all targets
add_library(A ...)
kis_link_dependencies(TARGET A PUBLIC B)  # Deferred!

add_library(B ...)
kis_link_dependencies(TARGET B PUBLIC C)  # Deferred!

# PHASE 2: Execute all links
kis_execute_deferred_links(A)  # Now B exists ✓
kis_execute_deferred_links(B)  # Now C exists ✓
```

## Security: Trusted URL Prefixes

To prevent malicious dependency injection, only URLs matching trusted prefixes are allowed:

```cmake
# In sdk_options.cmake
set(KIS_TRUSTED_URL_PREFIXES
    "https://github.com/Paolo-Oliverio/"
    "https://github.com/your-org/"
)
```

Attempting to clone from untrusted URLs will fail with an error.

## Troubleshooting

### "Target not found" errors
- **Cause**: Direct `target_link_libraries()` called before target exists
- **Fix**: Use `kis_link_dependencies()` instead

### Package not discovered in superbuild
- **Cause**: Missing `kis.package.cmake` or `CMakeLists.txt`
- **Fix**: Ensure both files exist in package directory

### Dependency not auto-cloned
- **Cause**: Missing or malformed `PACKAGE_DEPENDENCIES`
- **Fix**: Verify format: `"name;url;tag"` with proper semicolons

### Standalone build can't find dependency
- **Cause**: `kis_handle_first_party_dependencies()` not called
- **Fix**: Add it after `project()` in your CMakeLists.txt

## Migration Guide

### Old Style (Deprecated)
```cmake
# Old: Manual FetchContent per package
if(NOT BUILDING_WITH_SUPERBUILD)
    FetchContent_Declare(dep ...)
    FetchContent_MakeAvailable(dep)
endif()

target_link_libraries(mylib PUBLIC dep)  # May fail in superbuild!
```

### New Style (Recommended)
```cmake
# kis.package.cmake
set(PACKAGE_DEPENDENCIES
    "dep;https://github.com/org/dep.git;v1.0"
)

# CMakeLists.txt
kis_handle_first_party_dependencies()
kis_link_dependencies(TARGET mylib PUBLIC kis::dep)  # Always works!
```

## Internal Data Structures

### Global Properties
- `KIS_DECLARED_DEPENDENCY_NAMES`: List of third-party dependencies
- `KIS_ARGS_<name>`: FetchContent arguments for each dep
- `KIS_PENDING_LINKS_<target>`: Deferred link commands per target
- `KIS_OVERRIDE_MAP_KEYS/VALUES`: Platform override mappings

These are implementation details - package authors don't interact with them directly.
