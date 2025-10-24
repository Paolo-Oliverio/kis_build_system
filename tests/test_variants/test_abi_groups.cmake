# tests/test_variants/test_abi_groups.cmake

# --- Test Script Setup ---
if(NOT COMMAND begin_test_script)
    get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    include("${self_dir}/../test_utilities.cmake")
endif()
# --- End Test Script Setup ---

# Include the module to test
include(diagnostics) # Dependency for sdk_variants
include(sdk_variants)

begin_test_script("SDK Variant ABI Logic")

# --- Test Case 1: Get ABI Group ---
begin_test_case("Get ABI group for known variants")
kis_get_variant_abi_group("release" abi_group)
assert_equal("${abi_group}" "RELEASE")

kis_get_variant_abi_group("profiling" abi_group)
assert_equal("${abi_group}" "RELEASE")

kis_get_variant_abi_group("debug" abi_group)
assert_equal("${abi_group}" "DEBUG")

kis_get_variant_abi_group("asan" abi_group)
assert_equal("${abi_group}" "DEBUG")

kis_get_variant_abi_group("" abi_group) # Empty should default to release
assert_equal("${abi_group}" "RELEASE")

kis_get_variant_abi_group("unknown_variant" abi_group)
assert_equal("${abi_group}" "UNKNOWN")

# --- Test Case 2: ABI Compatibility ---
begin_test_case("Check ABI compatibility")
kis_variants_are_compatible("release" "profiling" is_compat)
assert_true(${is_compat})

kis_variants_are_compatible("debug" "asan" is_compat)
assert_true(${is_compat})

# --- THIS IS THE FIX ---
# Use the correct assertion helper for checking a false condition.
kis_variants_are_compatible("release" "debug" is_compat)
assert_false(${is_compat})

kis_variants_are_compatible("profiling" "asan" is_compat)
assert_false(${is_compat})
# --- END OF FIX ---

# --- Test Case 3: Custom Variant Registration ---
begin_test_case("Register and test a custom variant")
# Re-include to reset its internal state to defaults before testing registration
include(sdk_variants)

set(custom_json [[
  [{ "name": "relwithdebinfo", "abiGroup": "RELEASE", "description": "..." }]
]])
kis_register_package_custom_variants("my_pkg" "${custom_json}")

kis_get_variant_abi_group("relwithdebinfo" abi_group)
assert_equal("${abi_group}" "RELEASE")

kis_variants_are_compatible("release" "relwithdebinfo" is_compat)
assert_true(${is_compat})

kis_variants_are_compatible("debug" "relwithdebinfo" is_compat)
assert_false(${is_compat})

end_test_script("SDK Variant ABI Logic")