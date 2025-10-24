# tests/test_state/test_state_api.cmake

# --- Test Script Setup ---
if(NOT COMMAND begin_test_script)
    get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    include("${self_dir}/../test_utilities.cmake")
endif()
# --- End Test Script Setup ---

begin_test_script("KIS State Management")

# --- Test Case 1: Package Paths ---
begin_test_case("Package path storage and retrieval")
kis_state_init()
set(my_paths "path/a;path/b;path/c")
kis_state_set_all_package_paths("${my_paths}")
kis_state_get_all_package_paths(retrieved_paths)
assert_equal("${retrieved_paths}" "${my_paths}")

# --- Test Case 2: Override Map ---
begin_test_case("Override map storage and retrieval")
kis_state_init()
set(my_keys "key1;key2")
set(my_values "val1;val2")
kis_state_set_override_map("${my_keys}" "${my_values}")
kis_state_get_override_map(retrieved_keys retrieved_values)
assert_equal("${retrieved_keys}" "${my_keys}")
assert_equal("${retrieved_values}" "${my_values}")

# --- Test Case 3: Dependency Declaration (TPL) ---
begin_test_case("Third-party dependency declaration")
kis_state_init()
kis_state_add_tpl_dependency("doctest|||git1|||tag1|||url1|||hash1|||pkgA|||opts1")
kis_state_add_tpl_dependency("glfw|||git2|||tag2|||url2|||hash2|||pkgB|||opts2")
kis_state_get_tpl_dependencies(all_deps)
list(LENGTH all_deps dep_count)
assert_equal(${dep_count} 2)
list(GET all_deps 0 dep1)
assert_equal("${dep1}" "doctest|||git1|||tag1|||url1|||hash1|||pkgA|||opts1")

kis_state_get_tpl_dependency_names(dep_names)
assert_equal("${dep_names}" "doctest;glfw")

end_test_script("KIS State Management")