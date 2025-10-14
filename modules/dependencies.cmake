# cmake/build_system/dependencies.cmake

include(FetchContent)

# --- NEW DATA STRUCTURE ---
# We now use two types of global properties to store dependency info robustly,
# avoiding the fragile string parsing of the previous implementation.
#
# 1. KIS_DECLARED_DEPENDENCY_NAMES: A simple list of all dependency names
#    that have been requested by any package (e.g., "doctest;spdlog;fmt").
#
# 2. KIS_ARGS_<name>: A separate property for EACH dependency that stores its
#    FetchContent arguments as a proper CMake list (e.g., KIS_ARGS_doctest
#    will hold "GIT_REPOSITORY;https://...;GIT_TAG;...").

if(BUILDING_WITH_SUPERBUILD)
    # ==========================================================================
    # SUPERBUILD VERSION of kis_handle_dependency
    # ==========================================================================
    function(kis_handle_dependency NAME)
        # Parse args to find GIT_TAG and create version-aware cache paths
        set(options)
        set(oneValueArgs GIT_TAG)
        set(multiValueArgs)
        cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

        set(FETCHCONTENT_ARGS ${ARG_UNPARSED_ARGUMENTS})
        set(VERSION_SUFFIX "")
        if(ARG_GIT_TAG)
            string(REPLACE "." "_" SAFE_VERSION ${ARG_GIT_TAG})
            string(REGEX REPLACE "^v" "" SAFE_VERSION ${SAFE_VERSION})
            string(REPLACE "/" "_" SAFE_VERSION ${SAFE_VERSION})
            set(VERSION_SUFFIX "-v${SAFE_VERSION}")
            list(APPEND FETCHCONTENT_ARGS GIT_TAG ${ARG_GIT_TAG})
        endif()

        set(FETCHCONTENT_SOURCE_DIR_OVERRIDE
            "${FETCHCONTENT_BASE_DIR}/${NAME}${VERSION_SUFFIX}-src"
        )
        list(APPEND FETCHCONTENT_ARGS SOURCE_DIR ${FETCHCONTENT_SOURCE_DIR_OVERRIDE})

        # Register the dependency using the new, robust method.
        set_property(GLOBAL APPEND PROPERTY KIS_DECLARED_DEPENDENCY_NAMES ${NAME})
        set_property(GLOBAL PROPERTY KIS_ARGS_${NAME} ${FETCHCONTENT_ARGS})
    endfunction()

else()
    # ==========================================================================
    # STANDALONE VERSION of kis_handle_dependency (unchanged)
    # ==========================================================================
    function(kis_handle_dependency NAME)
        message(STATUS "Standalone handling dependency: ${NAME}")
        FetchContent_Declare(${NAME} ${ARGN})
        FetchContent_MakeAvailable(${NAME})
    endfunction()

endif()


#
# kis_populate_declared_dependencies()
#
# SUPERBUILD ONLY: Iterates the new data structure, declares all dependencies,
# and makes them available globally.
#
function(kis_populate_declared_dependencies)
    get_property(dep_names GLOBAL PROPERTY KIS_DECLARED_DEPENDENCY_NAMES)
    if(NOT dep_names)
        return()
    endif()

    # De-duplicate the list of names. This is crucial.
    list(REMOVE_DUPLICATES dep_names)

    # First, declare all unique dependencies.
    foreach(dep_name ${dep_names})
        get_property(dep_args GLOBAL PROPERTY KIS_ARGS_${dep_name})
        message(STATUS "Superbuild is declaring dependency: ${dep_name}")
        FetchContent_Declare(${dep_name} ${dep_args})
    endforeach()

    # Second, make them all available in one go. This is more efficient
    # as FetchContent can resolve the dependency graph.
    message(STATUS "Superbuild making all dependencies available: ${dep_names}")
    FetchContent_MakeAvailable(${dep_names})
endfunction()