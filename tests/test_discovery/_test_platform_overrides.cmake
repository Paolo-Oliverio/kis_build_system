# tests/test_discovery/test_platform_overrides.cmake

# --- Test Script Setup ---
if(NOT COMMAND begin_test_script)
    get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    include("${self_dir}/../test_utilities.cmake")
endif()
# --- End Test Script Setup ---

begin_test_script("discover_and_map_packages (platform override)")

# --- Test Setup ---
setup_test_env(temp_dir)
file(COPY "${TEST_FIXTURES_DIR}/discovery_test_basic/" DESTINATION "${temp_dir}")
set(CMAKE_CURRENT_SOURCE_DIR "${temp_dir}/discovery_test_basic") # Mock the project root

# --- Define Inputs for the function ---
set(KIS_PLATFORM "windows")
set(KIS_PLATFORM_TAGS "desktop;windows") # Must match platform_setup.cmake logic
set(KIS_ACTIVE_TAGS ${KIS_PLATFORM_TAGS}) # This is also needed now for validation
set(KIS_ENABLE_INCREMENTAL_VALIDATION OFF) # Disable incremental for predictable testing

# --- Call the function under test ---
begin_test_case("Correctly identify platform override")
discover_and_map_packages()
assert_succeeds() # Ensure no fatal errors during discovery/validation

# Retrieve results from state
kis_state_get_all_package_paths(out_paths)
kis_state_get_override_map(out_override_keys out_override_values)

# --- Assertions ---
list(LENGTH out_paths path_count)
assert_equal(${path_count} 2) # Should find both packages

assert_equal("${out_override_keys}" "common_pkg_A")
assert_equal("${out_override_values}" "win_pkg_B")

end_test_script("discover_and_map_packages (platform override)")