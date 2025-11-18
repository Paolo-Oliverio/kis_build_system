# cmake/build_system/components.cmake
#
# Provides helper functions for adding optional components like tests, samples,
# and benchmarks in a consistent way across all KIS SDK packages.

#
# kis_add_component
#
# Internal helper function to avoid code duplication. It now uses the deferred linking system.
#
function(_kis_add_component COMPONENT_TYPE TARGET_NAME)
    set(options)
    set(oneValueArgs)
    set(multiValueArgs SOURCES PUBLIC_LINK_LIBRARIES PRIVATE_LINK_LIBRARIES INTERFACE_LINK_LIBRARIES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # --- THE FIX: Use the explicit context to automatically link against the parent package ---
    if(DEFINED CACHE{_KIS_CTX_CURRENT_PACKAGE_ROOT})
        # We are in a package context, so we can infer the parent library.
        # Read the manifest for the package we are currently inside of.
        kis_read_package_manifest_json(PACKAGE_PATH "${_KIS_CTX_CURRENT_PACKAGE_ROOT}")
 
        if(DEFINED MANIFEST_NAME AND (MANIFEST_TYPE STREQUAL "LIBRARY" OR MANIFEST_TYPE STREQUAL "INTERFACE"))
            # If the parent is a library, automatically link it privately.
            # Check if the user hasn't already added it.
            list(FIND ARG_PRIVATE_LINK_LIBRARIES "${MANIFEST_NAME}" _index)
            list(FIND ARG_PUBLIC_LINK_LIBRARIES "${MANIFEST_NAME}" _index2)
            list(FIND ARG_INTERFACE_LINK_LIBRARIES "${MANIFEST_NAME}" _index3)
            if(_index EQUAL -1 AND _index2 EQUAL -1 AND _index3 EQUAL -1)
                 kis_message_verbose(STATUS "  [${TARGET_NAME}] Automatically linking against parent package: ${MANIFEST_NAME}")
                 list(APPEND ARG_PRIVATE_LINK_LIBRARIES "${MANIFEST_NAME}")
            endif()
        endif()
    endif()
    # --- END OF FIX ---

    # Create the executable target
    add_executable(${TARGET_NAME} ${ARG_SOURCES})

    # Set properties for IDE organization and build behavior
    set_target_properties(${TARGET_NAME} PROPERTIES
        FOLDER "${COMPONENT_TYPE}/${PROJECT_NAME}"
    )

    if(NOT KIS_BUILD_COMPONENTS_IN_ALL)
        set_target_properties(${TARGET_NAME} PROPERTIES EXCLUDE_FROM_ALL TRUE)
        set_target_properties(${TARGET_NAME} PROPERTIES VS_HIDE_TARGET_FROM_SOLUTION ON)
    endif()

    # Link dependencies from the manifest that are declared for this component's scope.
    string(TOLOWER ${COMPONENT_TYPE} scope_name)
    kis_message_verbose(STATUS "  [${TARGET_NAME}] Linking ${scope_name}-scoped dependencies from manifest")
    kis_link_from_manifest(TARGET ${TARGET_NAME} SCOPE ${scope_name})

    # Link any additional dependencies passed directly to this function.
    # This now includes our automatically added parent package library.
    kis_defer_link_dependencies(
        TARGET ${TARGET_NAME}
        SCOPE ${scope_name}
        PUBLIC ${ARG_PUBLIC_LINK_LIBRARIES}
        PRIVATE ${ARG_PRIVATE_LINK_LIBRARIES}
        INTERFACE ${ARG_INTERFACE_LINK_LIBRARIES}
    )

    # If the corresponding meta-target exists, add a dependency.
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
    kis_message_verbose(STATUS "Registering test: ${TARGET_NAME}")
    if(COMMAND add_test)
        add_test(NAME ${TARGET_NAME} COMMAND ${TARGET_NAME})
    endif()
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