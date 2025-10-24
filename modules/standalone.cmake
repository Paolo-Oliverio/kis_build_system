# kis_build_system/modules/standalone.cmake
#
# (INTERNAL) Provides the implementation for building a KIS package in standalone mode.
# This module is loaded and executed by kis_bootstrap_standalone().

include(FetchContent)

#
# _kis_internal_standalone_setup (INTERNAL)
#
# This is the implementation for the standalone package entrypoint.
#
function(_kis_internal_standalone_setup)
    message(STATUS "--- KIS Standalone Mode Initializing ---")
    set(BUILDING_WITH_SUPERBUILD FALSE) # Explicitly set for clarity

    # --- 1. Set up local workspace roots ---
    set(PACKAGES_ROOT "${CMAKE_SOURCE_DIR}/../kis_packages" CACHE PATH "Root for cloned first-party packages")
    file(MAKE_DIRECTORY "${PACKAGES_ROOT}")
    message(STATUS "Standalone: Using first-party package root: ${PACKAGES_ROOT}")

    # --- 2. Iteratively Resolve and Clone Dependencies ---
    set(iteration 1)
    while(TRUE)
        # ... (rest of the logic from the previous answer is unchanged) ...
        # ... (it resolves, clones, and then runs the standard build phases) ...
        message(STATUS "\n--- Dependency Resolution (Iteration ${iteration}) ---")

        set(all_manifests "")
        list(APPEND all_manifests "${CMAKE_CURRENT_SOURCE_DIR}/kis.package.json")
        kis_glob_package_manifests("${PACKAGES_ROOT}" cloned_manifests)
        list(APPEND all_manifests ${cloned_manifests})
        list(REMOVE_DUPLICATES all_manifests)

        set(all_required_deps "")
        foreach(manifest_file ${all_manifests})
            if(EXISTS ${manifest_file})
                kis_read_package_manifest_json("${manifest_file}")
                if(DEFINED MANIFEST_KIS_DEPENDENCIES)
                    string(JSON num_deps ERROR_VARIABLE err LENGTH "${MANIFEST_KIS_DEPENDENCIES}")
                    if(NOT err AND num_deps GREATER 0)
                        math(EXPR last_idx "${num_deps} - 1")
                        foreach(i RANGE ${last_idx})
                            string(JSON dep_obj GET "${MANIFEST_KIS_DEPENDENCIES}" ${i})
                            list(APPEND all_required_deps "${dep_obj}")
                        endforeach()
                    endif()
                endif()
            endif()
        endforeach()
        list(REMOVE_DUPLICATES all_required_deps)
        
        kis_glob_package_directories("${PACKAGES_ROOT}" discovered_on_disk)
        set(packages_on_disk "")
        foreach(pkg_path ${discovered_on_disk})
            kis_get_package_name_from_path("${pkg_path}" pkg_name)
            list(APPEND packages_on_disk ${pkg_name})
        endforeach()
        
        set(packages_to_clone "")
        foreach(dep_json ${all_required_deps})
            string(JSON dep_name GET "${dep_json}" "name")
            if(dep_name AND NOT dep_name IN_LIST packages_on_disk)
                string(JSON dep_url GET "${dep_json}" "url")
                string(JSON dep_tag GET "${dep_json}" "tag")
                set(pkg_destination "${PACKAGES_ROOT}/${dep_name}")
                list(APPEND packages_to_clone "${dep_name}|||${dep_url}|||${dep_tag}|||${pkg_destination}")
            endif()
        endforeach()
        list(REMOVE_DUPLICATES packages_to_clone)

        if(NOT packages_to_clone)
            message(STATUS "All first-party dependencies are present.")
            break()
        endif()

        message(STATUS "Found missing first-party packages to clone...")
        find_package(Git QUIET REQUIRED)
        foreach(package_info ${packages_to_clone})
            string(REPLACE "|||" ";" info_parts "${package_info}")
            list(GET info_parts 0 name)
            list(GET info_parts 1 url)
            list(GET info_parts 2 tag)
            list(GET info_parts 3 dest)
            message(STATUS "  -> Cloning ${name}...")
            execute_process(COMMAND ${GIT_EXECUTABLE} clone --branch ${tag} --depth 1 ${url} ${dest} RESULT_VARIABLE res)
            if(NOT res EQUAL 0)
                message(FATAL_ERROR "Failed to clone ${name} from ${url}")
            endif()
        endforeach()

        math(EXPR iteration "${iteration} + 1")
        if(iteration GREATER 10)
            message(FATAL_ERROR "Dependency resolution exceeded 10 iterations. Check for circular dependencies.")
        endif()
    endwhile()

    message(STATUS "\n--- All Dependencies Resolved. Starting Configuration ---")
    
    set(all_package_dirs "")
    list(APPEND all_package_dirs "${CMAKE_CURRENT_SOURCE_DIR}")
    kis_glob_package_directories("${PACKAGES_ROOT}" cloned_dirs)
    list(APPEND all_package_dirs ${cloned_dirs})

    kis_state_init()
    kis_profile_init()
    kis_init_validation_stats()
    kis_setup_compiler_cache()
    include(sdk_options)

    message(STATUS "\n--- PHASE 1: DISCOVERING AND CONFIGURING PACKAGES ---")
    kis_state_set_all_package_paths("${all_package_dirs}")
    configure_discovered_packages(${all_package_dirs})

    message(STATUS "\n--- PHASE 2: POPULATING THIRD-PARTY DEPENDENCIES ---")
    kis_populate_declared_dependencies()

    message(STATUS "\n--- PHASE 3: LINKING ALL PACKAGE DEPENDENCIES ---")
    link_all_package_dependencies(${all_package_dirs})
    
    message(STATUS "\n--- Standalone Configuration Complete ---")
endfunction()