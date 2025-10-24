# tests/test_utils/test_fatal_error.cmake
include("${CMAKE_CURRENT_LIST_DIR}/../test_utilities.cmake")

message(STATUS "Running test: kis_message_fatal_actionable")

set(failing_script "${CMAKE_CURRENT_LIST_DIR}/helpers/script_that_fails.cmake")

execute_process(
    COMMAND ${CMAKE_COMMAND} -P "${failing_script}"
    RESULT_VARIABLE result
    ERROR_VARIABLE error_output
)

# A FATAL_ERROR should result in a non-zero exit code
if(${result} EQUAL 0)
    message(FATAL_ERROR "Assertion failed: Process was expected to fail but succeeded.")
endif()

# Check that our actionable message is in the output
string(FIND "${error_output}" "[SOLUTION] How to fix:" find_result)
if(${find_result} EQUAL -1)
    message(FATAL_ERROR "Assertion failed: Fatal error message did not contain the solution hint.")
endif()

message(STATUS "PASS: kis_message_fatal_actionable")