# kis_build_system/kis.package.cmake

set(PACKAGE_NAME "kis_build_system")
set(PACKAGE_VERSION "0.1.0")
set(PACKAGE_VERSION_MAJOR "0")
set(PACKAGE_DESCRIPTION "Main package for sdk and standalone kis_ packages build system.")

# This package provides no remotes and has no dependencies.
set(PACKAGE_DEPENDENCIES "")
set(PACKAGE_REMOTES "")

# Optional metadata for tooling and discovery. Packages may set these in their
# own `kis.package.cmake` to provide richer information to UIs and tools.
# set(PACKAGE_CATEGORY "Core")
# set(PACKAGE_SEARCH_TAGS "build;tools")