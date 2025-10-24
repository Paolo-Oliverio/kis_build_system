# tests/test_utils/test_cache.cmake

# --- Test Script Setup ---
if(NOT COMMAND begin_test_script)
    get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    include("${self_dir}/../test_utilities.cmake")
endif()
# --- End Test Script Setup ---

# Include the module to test
include(utils)

# Setup a temporary directory for test manifests
setup_test_env(TEST_PKG_DIR)

begin_test_script("Caching System")

# --- Test Case 1: Manifest Fingerprinting ---
begin_test_case("Compute file fingerprint")

file(WRITE "${TEST_PKG_DIR}/test_file.txt" "Hello, World!")
kis_compute_file_fingerprint("${TEST_PKG_DIR}/test_file.txt" fp1)
assert_defined(fp1)

# Same content should produce same fingerprint
file(WRITE "${TEST_PKG_DIR}/test_file2.txt" "Hello, World!")
kis_compute_file_fingerprint("${TEST_PKG_DIR}/test_file2.txt" fp2)
assert_equal("${fp1}" "${fp2}")

# Different content should produce different fingerprint
file(WRITE "${TEST_PKG_DIR}/test_file3.txt" "Different content")
kis_compute_file_fingerprint("${TEST_PKG_DIR}/test_file3.txt" fp3)
if("${fp1}" STREQUAL "${fp3}")
    message(FATAL_ERROR "Different content produced same fingerprint")
endif()

# --- Test Case 2: Content Fingerprinting ---
begin_test_case("Compute content fingerprint")

kis_compute_content_fingerprint("test string" hash1)
kis_compute_content_fingerprint("test string" hash2)
assert_equal("${hash1}" "${hash2}")

kis_compute_content_fingerprint("different string" hash3)
if("${hash1}" STREQUAL "${hash3}")
    message(FATAL_ERROR "Different strings produced same hash")
endif()

# --- Test Case 3: Manifest Cache Hit ---
begin_test_case("Manifest caching with cache hit")

# Create a test manifest
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "cache_test_pkg",
  "version": "1.0.0",
  "type": "LIBRARY",
  "features": ["feature1"],
  "platform": {},
  "dependencies": {}
}
]])

# First read - should be a cache miss
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_equal("${MANIFEST_NAME}" "cache_test_pkg")
assert_equal("${MANIFEST_VERSION}" "1.0.0")
assert_equal("${MANIFEST_FEATURES}" "feature1")

# Second read - should be a cache hit
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_equal("${MANIFEST_NAME}" "cache_test_pkg")
assert_equal("${MANIFEST_VERSION}" "1.0.0")
assert_equal("${MANIFEST_FEATURES}" "feature1")

# --- Test Case 4: Manifest Cache Invalidation on Change ---
begin_test_case("Manifest cache invalidation on file change")

# Modify the manifest
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "cache_test_pkg_modified",
  "version": "2.0.0",
  "type": "LIBRARY",
  "features": ["feature2"],
  "platform": {},
  "dependencies": {}
}
]])

# Read should detect change and re-parse
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_equal("${MANIFEST_NAME}" "cache_test_pkg_modified")
assert_equal("${MANIFEST_VERSION}" "2.0.0")
assert_equal("${MANIFEST_FEATURES}" "feature2")

# --- Test Case 5: Platform Compatibility Cache ---
begin_test_case("Platform compatibility caching")

# Create a manifest with platform requirements
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "platform_test_pkg",
  "version": "1.0.0",
  "type": "LIBRARY",
  "platform": {
    "tags": ["desktop"]
  },
  "dependencies": {}
}
]])

# First validation - cache miss
kis_validate_package_platform("platform_test_pkg" "${TEST_PKG_DIR}" 
                               "windows-x64" "desktop;windows" 
                               is_compat1 error_msg1)
assert_true(is_compat1)

# Second validation with same parameters - cache hit
kis_validate_package_platform("platform_test_pkg" "${TEST_PKG_DIR}" 
                               "windows-x64" "desktop;windows" 
                               is_compat2 error_msg2)
assert_true(is_compat2)

# Third validation with different tags - cache miss (different key)
kis_validate_package_platform("platform_test_pkg" "${TEST_PKG_DIR}" 
                               "linux-x64" "mobile" 
                               is_compat3 error_msg3)
assert_false(is_compat3)

# --- Test Case 6: Manual Cache Invalidation ---
begin_test_case("Manual cache invalidation")

file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "invalidation_test",
  "version": "1.0.0",
  "type": "LIBRARY",
  "dependencies": {}
}
]])

# Read and cache
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_equal("${MANIFEST_NAME}" "invalidation_test")

# Manually invalidate
kis_cache_invalidate_manifest("${TEST_PKG_DIR}/kis.package.json")

# Modify without changing fingerprint would normally use cache,
# but we invalidated it, so it should re-read
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "invalidation_test_new",
  "version": "2.0.0",
  "type": "LIBRARY",
  "dependencies": {}
}
]])

kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_equal("${MANIFEST_NAME}" "invalidation_test_new")

# --- Test Case 6: Manifest Watching Registration ---
begin_test_case("Manifest watching registration")

# Verify that CMAKE_CONFIGURE_DEPENDS contains our manifest
get_property(configure_deps DIRECTORY PROPERTY CMAKE_CONFIGURE_DEPENDS)
set(manifest_found FALSE)
foreach(dep ${configure_deps})
    if(dep MATCHES "kis\\.package\\.json$")
        set(manifest_found TRUE)
        break()
    endif()
endforeach()
assert_true(manifest_found)

end_test_script("Caching System")
