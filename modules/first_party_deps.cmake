# cmake/build_system/first_party_deps.cmake
#
# Handles first-party dependencies declared in a package's manifest.
# These are other KIS packages that are fetched from a git repository
# in standalone mode or discovered in the kis_packages/ directory in
# superbuild mode.

include(FetchContent)

# ==============================================================================
#           FIRST-PARTY DEPENDENCY HANDLING
# ==============================================================================

#
# kis_handle_first_party_dependencies()
#
# This function reads dependencies from the package's JSON manifest and handles
# them appropriately based on the build mode:
#
# SUPERBUILD MODE:
#   - Dependencies are expected to be in kis_packages/ directory
#   - They will be discovered and configured by the superbuild
#   - This function does nothing in superbuild mode (deps handled by discovery)
#
# STANDALONE MODE:
#   - Dependencies are fetched from their remote locations
#   - Each dependency is made available via FetchContent
#
# Expected format in manifest:
#   "dependencies": { "kis": [ { "name": "...", "url": "...", "tag": "..." } ] }
#
function(kis_handle_first_party_dependencies)
    if(NOT DEFINED MANIFEST_KIS_DEPENDENCIES)
        return()
    endif()

    if(BUILDING_WITH_SUPERBUILD)
        # In superbuild mode, first-party deps are handled by discovery.cmake
        # The packages should already be present in kis_packages/ or will be
        # cloned there by kis_resolve_and_sync_packages()
        message(STATUS "[${MANIFEST_NAME}] First-party dependencies will be resolved by superbuild")
        return()
    endif()

    # STANDALONE MODE: Fetch first-party dependencies
    message(STATUS "[${MANIFEST_NAME}] Handling first-party dependencies in standalone mode")
    
    string(JSON num_deps ERROR_VARIABLE err LENGTH "${MANIFEST_KIS_DEPENDENCIES}")
    if(err OR num_deps EQUAL 0)
        return()
    endif()

    math(EXPR last_idx "${num_deps} - 1")
    foreach(i RANGE ${last_idx})
        string(JSON dep_obj GET "${MANIFEST_KIS_DEPENDENCIES}" ${i})
        string(JSON dep_name GET "${dep_obj}" "name")
        string(JSON dep_url GET "${dep_obj}" "url")
        string(JSON dep_tag GET "${dep_obj}" "tag")

        if(NOT dep_name OR NOT dep_url OR NOT dep_tag)
            kis_message_fatal_actionable(
                "Malformed kis dependency"
                "Problem: Missing name, url, or tag in kis.package.json"
                "Use correct format:\n     { \"name\": \"...\", \"url\": \"...\", \"tag\": \"...\" }"
                PACKAGE "${MANIFEST_NAME}"
            )
        endif()

        message(STATUS "  -> Fetching first-party dependency: ${dep_name} from ${dep_url}@${dep_tag}")
        
        # Use FetchContent to get the dependency
        FetchContent_Declare(
            ${dep_name}
            GIT_REPOSITORY ${dep_url}
            GIT_TAG ${dep_tag}
        )
        FetchContent_MakeAvailable(${dep_name})
    endforeach()
endfunction()