# cmake/build_system/sdk_versions.cmake
# Defines the canonical versions for all third-party dependencies used in the SDK.
# Every sdk version may have its own set of default third-party versions only intended as single source of truth for shared dependencies.
# Do not pollute with every single third-party, only the ones that are shared across multiple packages or important to pin.
# Mostly for deduplication and favor reproducible builds.

message(STATUS "Loading SDK third-party versions...") 

set(KIS_THIRDPARTY_DOCTEST_VERSION "v2.4.12" CACHE STRING "Canonical version for the 'doctest' library" FORCE)
# ... etc for all other third-party dependencies ...