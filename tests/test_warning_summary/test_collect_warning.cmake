# tests/test_diagnostics/test_warnings.cmake

# --- Test Script Setup ---
if(NOT COMMAND begin_test_script)
    get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    include("${self_dir}/../test_utilities.cmake")
endif()
# --- End Test Script Setup ---

# Include the module to test
include(diagnostics)

begin_test_script("Warning Collection")

# --- Test Case 1: Collect a single warning ---
begin_test_case("Collect a single warning")
kis_state_init() # Ensure clean state
kis_collect_warning("This is a simple warning")
kis_state_get_warnings(warnings count)
assert_equal(${count} 1)
assert_equal("${warnings}" "This is a simple warning")

# --- Test Case 2: Collect a structured warning ---
begin_test_case("Collect a structured warning")
kis_state_init()
kis_collect_warning("Category" "Message text" "Hint text")
kis_state_get_warnings(warnings count)
assert_equal(${count} 1)
assert_equal("${warnings}" "Category: Message text | Hint: Hint text")

# --- Test Case 3: Test deduplication ---
begin_test_case("Warning deduplication")
kis_state_init()
kis_collect_warning("Unique message 1")
kis_collect_warning("Duplicate message")
kis_collect_warning("Duplicate message") # Should be ignored
kis_collect_warning("Unique message 2")
kis_collect_warning("Duplicate message") # Should be ignored
kis_state_get_warnings(warnings count)
assert_equal(${count} 3)
assert_equal("${warnings}" "Unique message 1;Duplicate message;Unique message 2")

end_test_script("Warning Collection")