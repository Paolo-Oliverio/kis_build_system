# kis_build_system/modules/policies.cmake
#
# Centralized CMake policy management for the KIS build system.
#
# This module sets all required CMake policies to ensure consistent, predictable
# behavior across different CMake versions and prevent subtle bugs caused by
# policy changes between CMake releases.
#
# USAGE:
#   include(policies)
#
# This should be included BEFORE any other KIS build system modules to establish
# the policy environment early in the configuration process.

# =============================================================================
# POLICY VERSIONING STRATEGY
# =============================================================================
#
# We set policies explicitly rather than using cmake_minimum_required() in
# modules to avoid affecting the parent project's policy settings. This allows
# the build system to work as a library with well-defined behavior while
# respecting the host project's CMake configuration.

message(STATUS "Setting KIS build system CMake policies...")

# =============================================================================
# CRITICAL POLICIES - Required for Correct Operation
# =============================================================================

if(POLICY CMP0011)
    # CMP0011: Included scripts do automatic cmake_policy PUSH and POP.
    #
    # WHY: When a script is included via include(), this policy ensures that any
    # policy changes made within that script are automatically reverted when the
    # script completes. This prevents modules from accidentally affecting the
    # policy state of other modules or the parent project.
    #
    # BENEFIT: Modular isolation - each module can set its own policies without
    # side effects.
    #
    # INTRODUCED: CMake 2.8.12
    cmake_policy(SET CMP0011 NEW)
endif()

if(POLICY CMP0012)
    # CMP0012: if() recognizes numbers and boolean constants.
    #
    # WHY: Ensures that TRUE, FALSE, YES, NO, ON, OFF, Y, N are recognized as
    # boolean constants in if() conditions, and that numeric strings are treated
    # as numbers for comparison operations.
    #
    # BENEFIT: Critical for the test framework's assert_true()/assert_false()
    # functions and for reliable variable checking throughout the build system.
    #
    # WITHOUT THIS: Expressions like if(TRUE) might fail or behave unexpectedly.
    #
    # INTRODUCED: CMake 2.8.0
    cmake_policy(SET CMP0012 NEW)
endif()

if(POLICY CMP0054)
    # CMP0054: Only interpret if() arguments as variables or keywords when unquoted.
    #
    # WHY: Prevents automatic variable dereferencing of quoted strings in if()
    # statements. With OLD behavior, if(FOO MATCHES "${BAR}") would dereference
    # both FOO and BAR. With NEW behavior, only unquoted arguments are dereferenced.
    #
    # BENEFIT: Eliminates a major source of hard-to-debug issues where variable
    # names accidentally match existing variable names. Makes if() statements
    # more predictable and safer.
    #
    # EXAMPLE:
    #   set(VAR "MSVC")
    #   if("${VAR}" STREQUAL "MSVC")  # NEW: Compares string "MSVC" to "MSVC"
    #                                 # OLD: Would try to dereference MSVC!
    #
    # INTRODUCED: CMake 3.1
    cmake_policy(SET CMP0054 NEW)
endif()

if(POLICY CMP0057)
    # CMP0057: Support new IN_LIST operator in if() conditions.
    #
    # WHY: Enables the IN_LIST operator for checking list membership:
    #   if(item IN_LIST my_list)
    #
    # BENEFIT: Essential for the variant system's ABI group checking and platform
    # tag validation. Much cleaner than using list(FIND) manually.
    #
    # USAGE IN KIS: Used extensively in sdk_variants.cmake for checking if a
    # variant belongs to an ABI group.
    #
    # WITHOUT THIS: Would need verbose list(FIND) + index checking everywhere.
    #
    # INTRODUCED: CMake 3.3
    cmake_policy(SET CMP0057 NEW)
endif()

if(POLICY CMP0077)
    # CMP0077: option() honors normal variables.
    #
    # WHY: When set to NEW, if a normal variable is already defined when option()
    # is called, the option() command will not override it. This allows parent
    # projects to set KIS build system options before including the build system.
    #
    # BENEFIT: Users can configure KIS options like KIS_VERBOSE_BUILD in their
    # top-level CMakeLists.txt before including KIS, and those settings will be
    # respected.
    #
    # EXAMPLE:
    #   set(KIS_VERBOSE_BUILD ON)      # User's preference
    #   include(kis_build_system)
    #   option(KIS_VERBOSE_BUILD ...)  # Will NOT override user's setting
    #
    # INTRODUCED: CMake 3.13
    cmake_policy(SET CMP0077 NEW)
endif()

# =============================================================================
# STRING HANDLING POLICIES
# =============================================================================

if(POLICY CMP0010)
    # CMP0010: Bad variable reference syntax is an error.
    #
    # WHY: Catches malformed variable references like ${VAR or $VAR} early with
    # clear error messages instead of silently treating them as literal strings.
    #
    # BENEFIT: Helps catch typos and syntax errors in variable expansion,
    # especially important in JSON parsing and complex string manipulation.
    #
    # INTRODUCED: CMake 2.8.0
    cmake_policy(SET CMP0010 NEW)
endif()

if(POLICY CMP0053)
    # CMP0053: Simplify variable reference and escape sequence evaluation.
    #
    # WHY: Improves performance and predictability of variable expansion in
    # strings. Changes evaluation order to be more intuitive.
    #
    # BENEFIT: Faster variable substitution in large projects with many packages.
    # More reliable behavior when mixing $ENV{} and ${} expansions.
    #
    # INTRODUCED: CMake 3.1
    cmake_policy(SET CMP0053 NEW)
endif()

# =============================================================================
# TARGET AND LINKING POLICIES
# =============================================================================

if(POLICY CMP0022)
    # CMP0022: INTERFACE_LINK_LIBRARIES defines the link interface.
    #
    # WHY: Ensures that INTERFACE_LINK_LIBRARIES property is used to determine
    # what gets propagated to dependent targets, rather than the old LINK_INTERFACE_*
    # properties.
    #
    # BENEFIT: Critical for the dual-phase linking system and incremental
    # dependency resolution. Ensures correct transitive dependency propagation.
    #
    # INTRODUCED: CMake 2.8.12
    cmake_policy(SET CMP0022 NEW)
endif()

if(POLICY CMP0028)
    # CMP0028: Disallow :: in target names except in ALIAS targets.
    #
    # WHY: Reserves the :: syntax for namespace-qualified imported targets,
    # preventing users from creating regular targets with confusing names.
    #
    # BENEFIT: Enforces clean separation between imported third-party targets
    # (TPL::library) and first-party KIS targets. Makes dependency resolution
    # more reliable.
    #
    # INTRODUCED: CMake 3.0
    cmake_policy(SET CMP0028 NEW)
endif()

if(POLICY CMP0038)
    # CMP0038: Targets may not link directly to themselves.
    #
    # WHY: Catches circular dependency errors where a target accidentally lists
    # itself in its link libraries.
    #
    # BENEFIT: Prevents subtle build errors and infinite loops in dependency
    # resolution. Important for catching manifest errors early.
    #
    # INTRODUCED: CMake 3.0
    cmake_policy(SET CMP0038 NEW)
endif()

if(POLICY CMP0046)
    # CMP0046: Error on non-existent dependency in add_dependencies().
    #
    # WHY: Makes it a fatal error to add a dependency on a target that doesn't
    # exist, rather than silently ignoring it.
    #
    # BENEFIT: Catches typos and missing targets early in the configuration
    # phase rather than causing mysterious build failures later.
    #
    # INTRODUCED: CMake 3.0
    cmake_policy(SET CMP0046 NEW)
endif()

if(POLICY CMP0060)
    # CMP0060: Link libraries by full path even in implicit directories.
    #
    # WHY: Ensures that full paths to libraries are always used in link commands,
    # even when the library is in a system directory.
    #
    # BENEFIT: More reliable linking, especially when multiple versions of the
    # same library exist on the system. Reduces "wrong library version" issues.
    #
    # INTRODUCED: CMake 3.3
    cmake_policy(SET CMP0060 NEW)
endif()

if(POLICY CMP0065)
    # CMP0065: Do not add flags to export symbols from executables without
    # ENABLE_EXPORTS property.
    #
    # WHY: By default, don't make executable symbols available for dynamic linking
    # unless explicitly requested.
    #
    # BENEFIT: Cleaner, more predictable linking behavior. Symbols are only
    # exported when intentionally designed for plugin systems.
    #
    # INTRODUCED: CMake 3.4
    cmake_policy(SET CMP0065 NEW)
endif()

# =============================================================================
# INSTALLATION AND PACKAGING POLICIES
# =============================================================================

if(POLICY CMP0087)
    # CMP0087: install(CODE) and install(SCRIPT) support generator expressions.
    #
    # WHY: Allows use of $<CONFIG> and other generator expressions in install
    # commands, enabling configuration-aware installation.
    #
    # BENEFIT: Essential for multi-configuration generators (Visual Studio, Xcode)
    # to install the correct variant's files. Used in installation.cmake module.
    #
    # INTRODUCED: CMake 3.14
    cmake_policy(SET CMP0087 NEW)
endif()

# =============================================================================
# FIND AND DEPENDENCY POLICIES
# =============================================================================

if(POLICY CMP0074)
    # CMP0074: find_package() uses <PackageName>_ROOT variables.
    #
    # WHY: Enables find_package() to use <PackageName>_ROOT as a search hint,
    # both as a CMake variable and environment variable.
    #
    # BENEFIT: Simplifies third-party dependency management. Users can set
    # GLFW_ROOT or similar to point to custom installations.
    #
    # EXAMPLE:
    #   set(GLFW_ROOT "/opt/custom/glfw")
    #   find_package(GLFW)  # Will search in /opt/custom/glfw first
    #
    # INTRODUCED: CMake 3.12
    cmake_policy(SET CMP0074 NEW)
endif()

# =============================================================================
# PLATFORM-SPECIFIC POLICIES
# =============================================================================

if(POLICY CMP0025)
    # CMP0025: Compiler id for Apple Clang is now AppleClang.
    #
    # WHY: Distinguishes between Apple's Clang and upstream LLVM Clang, which
    # have different capabilities and quirks.
    #
    # BENEFIT: Enables platform-specific workarounds for Apple's Clang in
    # platform_setup.cmake. Improves cross-platform reliability.
    #
    # INTRODUCED: CMake 3.0
    cmake_policy(SET CMP0025 NEW)
endif()

if(POLICY CMP0056)
    # CMP0056: Honor link flags in try_compile() source-file signature.
    #
    # WHY: Ensures that CMAKE_EXE_LINKER_FLAGS is respected when doing
    # try_compile() checks during configuration.
    #
    # BENEFIT: More accurate feature detection, especially for sanitizer builds
    # where link flags are critical.
    #
    # INTRODUCED: CMake 3.2
    cmake_policy(SET CMP0056 NEW)
endif()

if(POLICY CMP0066)
    # CMP0066: Honor per-config flags in try_compile() source-file signature.
    #
    # WHY: Like CMP0056 but for configuration-specific flags (CMAKE_EXE_LINKER_FLAGS_DEBUG, etc.)
    #
    # BENEFIT: Ensures try_compile() tests match the actual build environment
    # for the current configuration.
    #
    # INTRODUCED: CMake 3.7
    cmake_policy(SET CMP0066 NEW)
endif()

# =============================================================================
# PROPERTY POLICIES
# =============================================================================

if(POLICY CMP0069)
    # CMP0069: INTERPROCEDURAL_OPTIMIZATION is enforced when enabled.
    #
    # WHY: When IPO/LTO is requested via INTERPROCEDURAL_OPTIMIZATION, actually
    # fail the build if it's not supported, rather than silently ignoring it.
    #
    # BENEFIT: Ensures that release builds that request LTO actually get it,
    # preventing silent performance regressions.
    #
    # INTRODUCED: CMake 3.9
    cmake_policy(SET CMP0069 NEW)
endif()

if(POLICY CMP0076)
    # CMP0076: target_sources() converts relative paths to absolute.
    #
    # WHY: When using target_sources() with relative paths, convert them to
    # absolute paths based on CMAKE_CURRENT_SOURCE_DIR.
    #
    # BENEFIT: Prevents subtle bugs when source files are added from different
    # directories. Makes package configuration more robust.
    #
    # INTRODUCED: CMake 3.13
    cmake_policy(SET CMP0076 NEW)
endif()

# =============================================================================
# GENERATOR EXPRESSION POLICIES
# =============================================================================

if(POLICY CMP0045)
    # CMP0045: Error on non-existent target in get_target_property().
    #
    # WHY: Makes it an error to query properties of non-existent targets rather
    # than returning an empty string.
    #
    # BENEFIT: Catches typos in target names early, especially in generator
    # expressions where errors are harder to debug.
    #
    # INTRODUCED: CMake 3.0
    cmake_policy(SET CMP0045 NEW)
endif()

if(POLICY CMP0051)
    # CMP0051: List TARGET_OBJECTS in SOURCES property.
    #
    # WHY: Include $<TARGET_OBJECTS:objlib> in the SOURCES property when queried.
    #
    # BENEFIT: More complete introspection of target sources, useful for
    # dependency analysis and build system diagnostics.
    #
    # INTRODUCED: CMake 3.1
    cmake_policy(SET CMP0051 NEW)
endif()

# =============================================================================
# NEWER POLICIES (CMake 3.15+)
# =============================================================================

if(POLICY CMP0091)
    # CMP0091: MSVC runtime library flags are selected by CMAKE_MSVC_RUNTIME_LIBRARY.
    #
    # WHY: Use the abstracted CMAKE_MSVC_RUNTIME_LIBRARY variable instead of
    # manually manipulating /MD, /MT flags in CMAKE_CXX_FLAGS.
    #
    # BENEFIT: Cleaner MSVC configuration. Easier to switch between static and
    # dynamic runtime. Better multi-config support.
    #
    # INTRODUCED: CMake 3.15
    cmake_policy(SET CMP0091 NEW)
endif()

if(POLICY CMP0092)
    # CMP0092: MSVC warning flags are not in CMAKE_<LANG>_FLAGS by default.
    #
    # WHY: Prevents CMake from adding /W3 to CMAKE_CXX_FLAGS automatically,
    # allowing the project to fully control warning levels.
    #
    # BENEFIT: Essential for enforcing KIS warning standards across all packages.
    # Prevents conflicts between default /W3 and our /W4 or /Wall settings.
    #
    # INTRODUCED: CMake 3.15
    cmake_policy(SET CMP0092 NEW)
endif()

# =============================================================================
# SUMMARY
# =============================================================================

message(STATUS "KIS CMake policies configured for CMake ${CMAKE_VERSION}")
message(STATUS "  - Variable handling: CMP0010, CMP0012, CMP0053, CMP0054")
message(STATUS "  - Target linking: CMP0022, CMP0028, CMP0038, CMP0046, CMP0060, CMP0065")
message(STATUS "  - List operations: CMP0057")
message(STATUS "  - Options: CMP0077")
message(STATUS "  - Module scope: CMP0011")
message(STATUS "  - Platform detection: CMP0025")
message(STATUS "  - Installation: CMP0087")
message(STATUS "  - Generator expressions: CMP0045, CMP0051")
if(MSVC)
    message(STATUS "  - MSVC-specific: CMP0091, CMP0092")
endif()

# =============================================================================
# POLICY COMPATIBILITY NOTES
# =============================================================================
#
# MINIMUM CMAKE VERSION:
# These policies require CMake 3.15 or newer for full functionality. For older
# CMake versions, some policies will be silently skipped (if(POLICY) checks).
#
# FORWARD COMPATIBILITY:
# New policies introduced in future CMake versions will use OLD behavior until
# explicitly added to this file. This ensures stable, predictable behavior.
#
# TESTING:
# All policy settings are tested in script mode by the test suite to ensure
# they work correctly in both normal and test contexts.
