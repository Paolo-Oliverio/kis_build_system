# tests/test_configuration/test_package_configuration.cmake

# --- Test Script Setup ---
if(NOT COMMAND begin_test_script)
    get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    include("${self_dir}/../test_utilities.cmake")
endif()
# --- End Test Script Setup ---

# All required modules are now loaded by test_utilities.cmake
begin_test_script("Package Configuration Integration")

# --- MOCKING: Create spy functions for non-scriptable commands ---
function(add_subdirectory source_dir binary_dir)
    message(STATUS "[TEST SPY] add_subdirectory called for ${source_dir}")
    get_filename_component(pkg_name "${source_dir}" NAME)
    set_property(GLOBAL APPEND PROPERTY TEST_PACKAGES_CONFIGURED ${pkg_name})
endfunction()

function(_kis_create_imported_package_target package_name package_path base_variant)
     message(STATUS "[TEST SPY] _kis_create_imported_package_target called for ${package_name}")
     set_property(GLOBAL APPEND PROPERTY TEST_PACKAGES_IMPORTED ${package_name})
endfunction()

function(_kis_create_skipped_package_stub package_name)
    message(STATUS "[TEST SPY] _kis_create_skipped_package_stub called for ${package_name}")
    set_property(GLOBAL APPEND PROPERTY TEST_PACKAGES_SKIPPED ${package_name})
endfunction()
# --- END MOCKING ---


# --- Test Setup ---
setup_test_env(temp_dir)
file(COPY "${TEST_FIXTURES_DIR}/config_test_packages/" DESTINATION "${temp_dir}")

# --- Test Case 1: Package with 'features: []' should be CONFIGURED ---
begin_test_case("Package with 'features: []' is correctly configured")
    set(package_to_test "${temp_dir}/basic_lib")
    set(KIS_ACTIVE_FEATURES "")
    set(KIS_CONFIG_SUFFIX "release")

    configure_discovered_packages("${package_to_test}")
    assert_succeeds()

    get_property(configured_pkgs GLOBAL PROPERTY TEST_PACKAGES_CONFIGURED)
    get_property(imported_pkgs GLOBAL PROPERTY TEST_PACKAGES_IMPORTED)

    assert_list_contains(configured_pkgs "basic_lib")
    assert_list_does_not_contain(imported_pkgs "basic_lib")
# --- End Test Case ---

# --- Test Case 2: Package requiring an inactive feature should be SKIPPED ---
begin_test_case("Package with unmet feature is skipped")
    # Add a new fixture on-the-fly for this test case
    file(MAKE_DIRECTORY "${temp_dir}/feature_lib")
    file(WRITE "${temp_dir}/feature_lib/kis.package.json" [[
        {"name": "feature_lib", "version": "1.0.0", "type": "LIBRARY", "features": ["tools"]}
    ]])

    set(package_to_test "${temp_dir}/feature_lib")
    set(KIS_ACTIVE_FEATURES "other_feature") # Feature "tools" is NOT active
    set(KIS_CONFIG_SUFFIX "release")
    
    configure_discovered_packages("${package_to_test}")
    assert_succeeds()
    
    get_property(configured_pkgs GLOBAL PROPERTY TEST_PACKAGES_CONFIGURED)
    get_property(imported_pkgs GLOBAL PROPERTY TEST_PACKAGES_IMPORTED)
    get_property(skipped_pkgs GLOBAL PROPERTY TEST_PACKAGES_SKIPPED)

    # A skipped package is neither configured nor imported, but IS skipped.
    assert_list_does_not_contain(configured_pkgs "feature_lib")
    assert_list_does_not_contain(imported_pkgs "feature_lib")
    assert_list_contains(skipped_pkgs "feature_lib")
# --- End Test Case ---

# --- Test Case 3: Package with unsupported variant should be IMPORTED ---
begin_test_case("Package with unsupported variant is imported")
    file(MAKE_DIRECTORY "${temp_dir}/profiling_lib")
    file(WRITE "${temp_dir}/profiling_lib/kis.package.json" [[
        {"name": "profiling_lib", "version": "1.0.0", "type": "LIBRARY", "abi": {"variant": "PER_CONFIG", "supportedVariants": ["release", "debug"]}}
    ]])

    set(package_to_test "${temp_dir}/profiling_lib")
    set(KIS_ACTIVE_FEATURES "")
    set(KIS_CONFIG_SUFFIX "profiling") # We are building a variant the package does not support

    configure_discovered_packages("${package_to_test}")
    assert_succeeds()

    get_property(configured_pkgs GLOBAL PROPERTY TEST_PACKAGES_CONFIGURED)
    get_property(imported_pkgs GLOBAL PROPERTY TEST_PACKAGES_IMPORTED)

    assert_list_contains(imported_pkgs "profiling_lib")
    assert_list_does_not_contain(configured_pkgs "profiling_lib")
# --- End Test Case ---


end_test_script("Package Configuration Integration")