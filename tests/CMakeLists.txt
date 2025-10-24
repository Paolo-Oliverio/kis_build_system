# kis_build_system/tests/CMakeLists.txt
cmake_minimum_required(VERSION 3.22)
project(kis-build-system-tests)

# Enable CTest
enable_testing()

# Make the build system modules available to the tests
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../modules")

# Recursively find and add all test scripts
file(GLOB_RECURSE test_scripts RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "test_*.cmake")

foreach(test_script ${test_scripts})
    get_filename_component(test_name ${test_script} NAME_WE)
    add_test(
        NAME ${test_name}
        COMMAND ${CMAKE_COMMAND} -P "${CMAKE_CURRENT_SOURCE_DIR}/${test_script}"
    )
endforeach()