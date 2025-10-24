# tests/test_utils/test_policies.cmake

# --- Test Script Setup ---
if(NOT COMMAND begin_test_script)
    get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    include("${self_dir}/../test_utilities.cmake")
endif()
# --- End Test Script Setup ---

begin_test_script("CMake Policies Module")

# --- Test Case 1: IN_LIST Operator Works ---
begin_test_case("IN_LIST operator is functional")

# Explicitly ensure CMP0057 is set for this test
if(POLICY CMP0057)
    cmake_policy(SET CMP0057 NEW)
endif()

set(test_list "apple" "banana" "cherry")

if("banana" IN_LIST test_list)
    set(found TRUE)
else()
    set(found FALSE)
endif()
assert_true(found)

if("grape" IN_LIST test_list)
    set(not_found FALSE)
else()
    set(not_found TRUE)
endif()
assert_true(not_found)

# --- Test Case 2: Boolean Constants Recognition ---
begin_test_case("Boolean constants are recognized")

# Explicitly set CMP0012 for this test
if(POLICY CMP0012)
    cmake_policy(SET CMP0012 NEW)
endif()

if(TRUE)
    set(true_works TRUE)
else()
    set(true_works FALSE)
endif()
assert_true(true_works)

if(FALSE)
    set(false_fails TRUE)
else()
    set(false_fails FALSE)
endif()
assert_false(false_fails)

set(MY_OPTION ON)
if(MY_OPTION)
    set(on_works TRUE)
else()
    set(on_works FALSE)
endif()
assert_true(on_works)

# --- Test Case 3: Quoted Variable Dereferencing ---
begin_test_case("Quoted strings are not dereferenced (CMP0054)")

# Explicitly set CMP0054 for this test
if(POLICY CMP0054)
    cmake_policy(SET CMP0054 NEW)
endif()

set(MSVC "should_not_dereference")
set(should_not_dereference "WRONG")

if("${MSVC}" STREQUAL "should_not_dereference")
    set(cmp0054_works TRUE)
else()
    set(cmp0054_works FALSE)
endif()
assert_true(cmp0054_works)

end_test_script("CMake Policies Module")
