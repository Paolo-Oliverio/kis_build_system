# kis_build_system/tests/test_utilities.cmake

# Set policies for consistent behavior in script mode
# Note: The policies module will set these more comprehensively, but we set
# these critical ones here for standalone test execution.
cmake_policy(SET CMP0011 NEW) # Included scripts do automatic PUSH/POP
cmake_policy(SET CMP0012 NEW) # if() recognizes boolean constants like TRUE/FALSE

# Set KIS_TESTING_MODE to TRUE so that macros like kis_message_fatal_actionable
# will set a variable instead of halting the script.
set(KIS_TESTING_MODE TRUE)

# Set the root of the build system so tests can find it
get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
set(KIS_BUILD_SYSTEM_ROOT "${self_dir}/..")
list(APPEND CMAKE_MODULE_PATH "${KIS_BUILD_SYSTEM_ROOT}/modules")

# Load the policies module to ensure consistent behavior across all tests
include(policies)

# Load the caching system
include(cache)

# Load the state module, as it's foundational for most tests.
include(kis_state)

# Initialize the state once for the test run context.
# Individual tests can re-initialize if needed.
kis_state_init()

# --- Assertion Library ---
function(assert_equal A B)
    if(NOT "${A}" STREQUAL "${B}")
        message(FATAL_ERROR "Assertion failed: '${A}' does not equal '${B}'")
    endif()
endfunction()

function(assert_true CONDITION)
    if(NOT (${CONDITION}))
        message(FATAL_ERROR "Assertion failed: Condition '${CONDITION}' is not true.")
    endif()
endfunction()

function(assert_false CONDITION)
    if(${CONDITION})
        message(FATAL_ERROR "Assertion failed: Condition '${CONDITION}' is not false.")
    endif()
endfunction()

function(assert_defined VAR)
    if(NOT DEFINED ${VAR})
        message(FATAL_ERROR "Assertion failed: Variable '${VAR}' is not defined.")
    endif()
endfunction()

function(assert_not_defined VAR)
    if(DEFINED ${VAR})
        message(FATAL_ERROR "Assertion failed: Variable '${VAR}' was expected to be undefined but was defined with value '${${VAR}}'")
    endif()
endfunction()

function(assert_empty VAR)
    if(NOT DEFINED ${VAR})
        message(FATAL_ERROR "Assertion failed: Variable '${VAR}' was expected to be empty, but it was not defined.")
    elseif(NOT "${${VAR}}" STREQUAL "")
        message(FATAL_ERROR "Assertion failed: Variable '${VAR}' was expected to be empty, but had value '${${VAR}}'.")
    endif()
endfunction()

# FIX: These now use a GLOBAL PROPERTY which is visible across all function scopes.
function(assert_succeeds)
    get_property(last_error GLOBAL PROPERTY KIS_TEST_LAST_ERROR)
    if(last_error)
        message(FATAL_ERROR "Assertion failed: Expected success, but got error:\n${last_error}")
    endif()
endfunction()

function(assert_fails_with_substring SUBSTRING)
    get_property(last_error GLOBAL PROPERTY KIS_TEST_LAST_ERROR)
    if(NOT last_error)
        message(FATAL_ERROR "Assertion failed: Expected an error, but none occurred.")
    elseif(NOT last_error MATCHES ".*${SUBSTRING}.*")
        message(FATAL_ERROR "Assertion failed: Expected error to contain '${SUBSTRING}', but was:\n${last_error}")
    endif()
endfunction()


# --- Test Case Management ---
macro(begin_test_script SCRIPT_NAME)
    message(STATUS "\n--- Running Test Script: ${SCRIPT_NAME} ---")
endmacro()

macro(end_test_script SCRIPT_NAME)
    message(STATUS "--- PASS: ${SCRIPT_NAME} ---\n")
endmacro()

macro(begin_test_case CASE_NAME)
    # FIX: Clear the global property before each test case.
    set_property(GLOBAL PROPERTY KIS_TEST_LAST_ERROR "")
    message(STATUS "  - Case: ${CASE_NAME}")
endmacro()


# --- Fixture Management ---
set(TEST_FIXTURES_DIR "${self_dir}/fixtures")

function(setup_test_env out_temp_dir)
    if(DEFINED ENV{CMAKE_JOB_ID})
        set(job_id "_${ENV{CMAKE_JOB_ID}}")
    else()
        set(job_id "")
    endif()
    
    set(temp_dir "${CMAKE_BINARY_DIR}/temp_test${job_id}")
    file(REMOVE_RECURSE "${temp_dir}")
    file(MAKE_DIRECTORY "${temp_dir}")
    set(${out_temp_dir} "${temp_dir}" PARENT_SCOPE)

    kis_state_init()
endfunction()