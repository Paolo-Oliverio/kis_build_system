# cmake/build_system/sdk_options.cmake
# Defines all user-configurable options for the SDK build.

message(STATUS "Loading SDK build options...")

option(KIS_BUILD_TESTS "Build all test projects." ON)
option(KIS_BUILD_SAMPLES "Build all sample projects." ON)
option(KIS_BUILD_BENCHMARKS "Build all benchmark projects." OFF)
option(KIS_SDK_RESOLVE_PACKAGES "Automatically resolve and clone missing first-party packages." ON)
set(KIS_TRUSTED_URL_PREFIXES "https://github.com/your-org/" CACHE STRING "List of trusted URL prefixes for package cloning.")
list(APPEND CMAKE_MESSAGE_INDENT "  ")
message(STATUS "Trusted Prefixes: ${KIS_TRUSTED_URL_PREFIXES}") # list of repos to get first party and curated packages.