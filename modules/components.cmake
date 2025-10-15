# cmake/build_system/components.cmake
#
# Provides helper functions for adding optional components like tests, samples,
# and benchmarks in a consistent way across all KIS SDK packages.

#
# kis_add_component
#
# Internal helper function to avoid code duplication.
#
function(_kis_add_component COMPONENT_TYPE TARGET_NAME)
    set(options)
    set(oneValueArgs)
    set(multiValueArgs SOURCES LINK_LIBRARIES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Create the executable target
    add_executable(${TARGET_NAME} ${ARG_SOURCES})

    # Set properties for IDE organization and build behavior
    set_target_properties(${TARGET_NAME} PROPERTIES
        # Group targets neatly in IDEs like Visual Studio and VS Code
        FOLDER "${COMPONENT_TYPE}/${PROJECT_NAME}"
    )

    if(NOT KIS_BUILD_COMPONENTS_IN_ALL)
        # If the option is OFF, restore the old behavior.        
        # It must be built explicitly or via a meta-target (e.g., 'all_tests').
        list(APPEND component_properties EXCLUDE_FROM_ALL TRUE)
    endif()

    # Link libraries
    target_link_libraries(${TARGET_NAME} PRIVATE ${ARG_LINK_LIBRARIES})

    # If the corresponding meta-target exists (in superbuild mode), add a dependency.
    string(TOLOWER ${COMPONENT_TYPE} meta_target_name_suffix)
    set(meta_target_name "all_${meta_target_name_suffix}")
    if(TARGET ${meta_target_name})
        add_dependencies(${meta_target_name} ${TARGET_NAME})
    endif()
endfunction()


#
# kis_add_test
#
# Adds a test executable.
#
function(kis_add_test TARGET_NAME)
    _kis_add_component("Tests" ${TARGET_NAME} ${ARGN})
    message(STATUS "Registering test: ${TARGET_NAME}")
    add_test(NAME ${TARGET_NAME} COMMAND ${TARGET_NAME})
endfunction()

#
# kis_add_sample
#
# Adds a sample executable.
#
function(kis_add_sample TARGET_NAME)
    _kis_add_component("Samples" ${TARGET_NAME} ${ARGN})
endfunction()


#
# kis_add_benchmark
#
# Adds a benchmark executable.
#
function(kis_add_benchmark TARGET_NAME)
    _kis_add_component("Benchmarks" ${TARGET_NAME} ${ARGN})
endfunction()