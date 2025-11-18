# kis_build_system/tests/test_utilities.cmake

# =============================================================================
# POLICY SETUP FOR TESTS (Directly included to avoid scoping issues)
# =============================================================================
# This block is a copy of policies.cmake to ensure that all test scripts
# run with a consistent, modern CMake policy environment.

if(POLICY CMP0011)
    cmake_policy(SET CMP0011 NEW)
endif()
if(POLICY CMP0012)
    cmake_policy(SET CMP0012 NEW)
endif()
if(POLICY CMP0054)
    cmake_policy(SET CMP0054 NEW)
endif()
if(POLICY CMP0057)
    cmake_policy(SET CMP0057 NEW)
endif()
if(POLICY CMP0077)
    cmake_policy(SET CMP0077 NEW)
endif()
if(POLICY CMP0010)
    cmake_policy(SET CMP0010 NEW)
endif()
if(POLICY CMP0053)
    cmake_policy(SET CMP0053 NEW)
endif()
if(POLICY CMP0022)
    cmake_policy(SET CMP0022 NEW)
endif()
if(POLICY CMP0028)
    cmake_policy(SET CMP0028 NEW)
endif()
if(POLICY CMP0038)
    cmake_policy(SET CMP0038 NEW)
endif()
if(POLICY CMP0046)
    cmake_policy(SET CMP0046 NEW)
endif()
if(POLICY CMP0060)
    cmake_policy(SET CMP0060 NEW)
endif()
if(POLICY CMP0065)
    cmake_policy(SET CMP0065 NEW)
endif()
if(POLICY CMP0087)
    cmake_policy(SET CMP0087 NEW)
endif()
if(POLICY CMP0074)
    cmake_policy(SET CMP0074 NEW)
endif()
if(POLICY CMP0025)
    cmake_policy(SET CMP0025 NEW)
endif()
if(POLICY CMP0056)
    cmake_policy(SET CMP0056 NEW)
endif()
if(POLICY CMP0066)
    cmake_policy(SET CMP0066 NEW)
endif()
if(POLICY CMP0069)
    cmake_policy(SET CMP0069 NEW)
endif()
if(POLICY CMP0076)
    cmake_policy(SET CMP0076 NEW)
endif()
if(POLICY CMP0045)
    cmake_policy(SET CMP0045 NEW)
endif()
if(POLICY CMP0051)
    cmake_policy(SET CMP0051 NEW)
endif()
if(POLICY CMP0091)
    cmake_policy(SET CMP0091 NEW)
endif()
if(POLICY CMP0092)
    cmake_policy(SET CMP0092 NEW)
endif()
# =============================================================================

# Set KIS_TESTING_MODE to TRUE so that macros like kis_message_fatal_actionable
# will set a variable instead of halting the script.
set(KIS_TESTING_MODE TRUE)

# Set the root of the build system so tests can find it
get_filename_component(self_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
set(KIS_BUILD_SYSTEM_ROOT "${self_dir}/..")
list(APPEND CMAKE_MODULE_PATH "${KIS_BUILD_SYSTEM_ROOT}/modules")

# --- THE FIX: Load the entire core build system for a complete environment ---
# This single include replaces the manual includes for policies, cache, state, etc.
# and ensures all functions (like kis_profile_begin) are always available.
include(kis_build_system)

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

function(assert_target_exists TARGET_NAME)
    if(NOT TARGET ${TARGET_NAME})
        message(FATAL_ERROR "Assertion failed: Target '${TARGET_NAME}' was expected to exist, but it does not.")
    endif()
endfunction()

# NEW: Assertions for the spy pattern
function(assert_list_contains LIST_VAR ITEM)
    list(FIND ${LIST_VAR} "${ITEM}" _index)
    if(_index EQUAL -1)
        message(FATAL_ERROR "Assertion failed: Expected list [${${LIST_VAR}}] to contain '${ITEM}'.")
    endif()
endfunction()

function(assert_list_does_not_contain LIST_VAR ITEM)
    list(FIND ${LIST_VAR} "${ITEM}" _index)
    if(NOT _index EQUAL -1)
        message(FATAL_ERROR "Assertion failed: Expected list [${${LIST_VAR}}] to NOT contain '${ITEM}'.")
    endif()
endfunction()


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
    # Clear state for spies
    set_property(GLOBAL PROPERTY KIS_TEST_LAST_ERROR "")
    set_property(GLOBAL PROPERTY TEST_PACKAGES_CONFIGURED "")
    set_property(GLOBAL PROPERTY TEST_PACKAGES_IMPORTED "")
    set_property(GLOBAL PROPERTY TEST_PACKAGES_SKIPPED "")
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