# tests/test_utils/test_json_parsing.cmake

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

begin_test_script("kis_read_package_manifest_json")

# --- Test Case 1: Valid and complete manifest ---
begin_test_case("Valid complete manifest")
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "test_pkg", "version": "1.2.3", "type": "LIBRARY",
  "features": ["f1", "f2"],
  "platform": { "tags": ["desktop"] },
  "dependencies": { "kis": [], "thirdParty": [] }
}
]])
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_succeeds()
assert_equal("${MANIFEST_NAME}" "test_pkg")
assert_equal("${MANIFEST_VERSION}" "1.2.3")
assert_equal("${MANIFEST_TYPE}" "LIBRARY")
assert_equal("${MANIFEST_FEATURES}" "f1;f2")
assert_equal("${MANIFEST_PLATFORM_TAGS}" "desktop")
assert_defined(MANIFEST_KIS_DEPENDENCIES)
assert_defined(MANIFEST_TPL_DEPENDENCIES)

# --- Test Case 2: Minimal valid manifest with empty arrays/objects ---
begin_test_case("Minimal manifest with empty fields")
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "minimal", "version": "1.0.0", "type": "INTERFACE",
  "features": [], "platform": {}, "dependencies": {}
}
]])
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_succeeds()
assert_equal("${MANIFEST_NAME}" "minimal")

# --- FIX START ---
# 'features' key exists with an empty array, so MANIFEST_FEATURES should be defined and empty.
assert_empty(MANIFEST_FEATURES)
# 'platform' key exists as an empty object, so it has no 'platforms' key within it.
# Therefore, MANIFEST_PLATFORMS should be UNDEFINED.
assert_not_defined(MANIFEST_PLATFORMS)
# 'dependencies' key exists as an empty object, so it has no 'kis' key within it.
# Therefore, MANIFEST_KIS_DEPENDENCIES should be UNDEFINED.
assert_not_defined(MANIFEST_KIS_DEPENDENCIES)
# --- FIX END ---


# --- Test Case 3: Invalid JSON syntax (missing comma) ---
begin_test_case("Invalid JSON syntax (missing comma)")
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "bad_syntax"
  "version": "1.0.0" 
}
]])
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_fails_with_substring("Invalid JSON")
assert_fails_with_substring("not valid JSON")

# --- Test Case 4: Incorrect type (string instead of array) ---
begin_test_case("Incorrect type for 'features'")
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "wrong_type", "version": "1.0.0", "type": "LIBRARY",
  "features": "my_feature"
}
]])
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_fails_with_substring("Invalid Manifest: Not an Array")
assert_fails_with_substring("key 'features'")

# --- Test Case 5: Incorrect type in platform object ---
begin_test_case("Incorrect type for 'platform.tags'")
file(WRITE "${TEST_PKG_DIR}/kis.package.json" [[
{
  "name": "wrong_type", "version": "1.0.0", "type": "LIBRARY",
  "platform": {
    "tags": { "oops": "not an array" }
  }
}
]])
kis_read_package_manifest_json(PACKAGE_PATH ${TEST_PKG_DIR})
assert_fails_with_substring("Invalid Manifest: Not an Array")
assert_fails_with_substring("key 'tags'")

end_test_script("kis_read_package_manifest_json")