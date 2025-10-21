# parallel_fetch.cmake
#
# Parallel dependency fetching for both third-party (FetchContent) and
# first-party (git clone) dependencies.
#
# This module provides parallel execution of git clone/fetch operations
# using Python's ThreadPoolExecutor, dramatically speeding up first-time
# configuration.
#
# Performance:
#   - Sequential: 300s for 20 deps → Parallel (4 workers): ~75s (4x faster)
#   - Automatic worker count tuning based on available cores
#   - Graceful fallback to sequential if Python unavailable
#
# Usage:
#   kis_parallel_fetch_dependencies(dep_names dep_args_list)
#   kis_parallel_clone_first_party(package_info_list)

# Find Python interpreter for parallel execution
find_package(Python3 COMPONENTS Interpreter QUIET)

if(Python3_FOUND AND KIS_ENABLE_PARALLEL_FETCH)
    set(KIS_PARALLEL_FETCH_AVAILABLE TRUE CACHE INTERNAL "")
    message(STATUS "Parallel fetch: Enabled (Python ${Python3_VERSION})")
else()
    set(KIS_PARALLEL_FETCH_AVAILABLE FALSE CACHE INTERNAL "")
    if(KIS_ENABLE_PARALLEL_FETCH)
        message(STATUS "Parallel fetch: Disabled (Python not found, falling back to sequential)")
    endif()
endif()

#
# kis_parallel_fetch_dependencies(dep_names_var dep_args_list_var)
#
# Parallel fetch for third-party FetchContent dependencies.
#
# Arguments:
#   dep_names_var - Name of variable containing list of dependency names
#   dep_args_list_var - Name of variable containing list of "name;args..." entries
#
# Example:
#   set(deps "doctest;glfw")
#   set(args_list
#       "doctest;GIT_REPOSITORY;https://github.com/doctest/doctest.git;GIT_TAG;v2.4.11"
#       "glfw;GIT_REPOSITORY;https://github.com/glfw/glfw.git;GIT_TAG;3.4"
#   )
#   kis_parallel_fetch_dependencies(deps args_list)
#
function(kis_parallel_fetch_dependencies dep_names_var dep_args_list_var)
    set(dep_names ${${dep_names_var}})
    set(dep_args_list ${${dep_args_list_var}})
    
    if(NOT KIS_PARALLEL_FETCH_AVAILABLE OR NOT dep_names)
        # Fallback to sequential FetchContent
        foreach(dep_name ${dep_names})
            # Find args for this dependency
            foreach(entry ${dep_args_list})
                string(REPLACE ";" "|" entry_escaped "${entry}")
                list(GET entry 0 entry_name)
                if(entry_name STREQUAL dep_name)
                    list(SUBLIST entry 1 -1 dep_args)
                    FetchContent_Declare(${dep_name} ${dep_args})
                    break()
                endif()
            endforeach()
        endforeach()
        FetchContent_MakeAvailable(${dep_names})
        return()
    endif()

    # Prepare data file for Python script
    set(fetch_data_file "${CMAKE_BINARY_DIR}/_parallel_fetch_data.json")
    set(json_content "{\n  \"dependencies\": [\n")
    
    set(first TRUE)
    foreach(dep_name ${dep_names})
        # Find args for this dependency
        set(dep_git_repo "")
        set(dep_git_tag "")
        set(dep_url "")
        set(dep_url_hash "")
        
        foreach(entry ${dep_args_list})
            list(GET entry 0 entry_name)
            if(entry_name STREQUAL dep_name)
                list(SUBLIST entry 1 -1 dep_args)
                
                # Parse FetchContent args
                set(i 0)
                list(LENGTH dep_args num_args)
                while(i LESS num_args)
                    list(GET dep_args ${i} key)
                    math(EXPR i "${i} + 1")
                    if(i LESS num_args)
                        list(GET dep_args ${i} value)
                        math(EXPR i "${i} + 1")
                        
                        if(key STREQUAL "GIT_REPOSITORY")
                            set(dep_git_repo "${value}")
                        elseif(key STREQUAL "GIT_TAG")
                            set(dep_git_tag "${value}")
                        elseif(key STREQUAL "URL")
                            set(dep_url "${value}")
                        elseif(key STREQUAL "URL_HASH")
                            set(dep_url_hash "${value}")
                        endif()
                    endif()
                endwhile()
                break()
            endif()
        endforeach()
        
        # Get FetchContent destination directory
        FetchContent_GetProperties(${dep_name})
        if(NOT ${dep_name}_POPULATED)
            string(TOLOWER ${dep_name} dep_name_lower)
            set(dep_source_dir "${FETCHCONTENT_BASE_DIR}/${dep_name_lower}-src")
            set(dep_binary_dir "${FETCHCONTENT_BASE_DIR}/${dep_name_lower}-build")
            
            if(NOT first)
                string(APPEND json_content ",\n")
            endif()
            set(first FALSE)
            
            string(APPEND json_content "    {\n")
            string(APPEND json_content "      \"name\": \"${dep_name}\",\n")
            string(APPEND json_content "      \"source_dir\": \"${dep_source_dir}\",\n")
            string(APPEND json_content "      \"binary_dir\": \"${dep_binary_dir}\",\n")
            if(dep_git_repo)
                string(APPEND json_content "      \"git_repository\": \"${dep_git_repo}\",\n")
                string(APPEND json_content "      \"git_tag\": \"${dep_git_tag}\",\n")
                string(APPEND json_content "      \"type\": \"git\"\n")
            elseif(dep_url)
                string(APPEND json_content "      \"url\": \"${dep_url}\",\n")
                string(APPEND json_content "      \"url_hash\": \"${dep_url_hash}\",\n")
                string(APPEND json_content "      \"type\": \"url\"\n")
            endif()
            string(APPEND json_content "    }")
        endif()
    endforeach()
    
    string(APPEND json_content "\n  ],\n")
    string(APPEND json_content "  \"worker_count\": ${KIS_PARALLEL_FETCH_WORKERS}\n")
    string(APPEND json_content "}\n")
    
    file(WRITE "${fetch_data_file}" "${json_content}")
    
    # Execute Python parallel fetch script
    set(parallel_script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../tools/parallel_fetch.py")
    
    message(STATUS "Fetching ${list(LENGTH dep_names)} dependencies in parallel (${KIS_PARALLEL_FETCH_WORKERS} workers)...")
    
    execute_process(
        COMMAND ${Python3_EXECUTABLE} "${parallel_script}" "${fetch_data_file}"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        RESULT_VARIABLE fetch_result
        OUTPUT_VARIABLE fetch_output
        ERROR_VARIABLE fetch_error
    )
    
    if(NOT fetch_result EQUAL 0)
        message(WARNING 
            "Parallel fetch failed, falling back to sequential:\n"
            "${fetch_output}\n${fetch_error}"
        )
        # Fallback to sequential
        foreach(dep_name ${dep_names})
            foreach(entry ${dep_args_list})
                list(GET entry 0 entry_name)
                if(entry_name STREQUAL dep_name)
                    list(SUBLIST entry 1 -1 dep_args)
                    FetchContent_Declare(${dep_name} ${dep_args})
                    break()
                endif()
            endforeach()
        endforeach()
        FetchContent_MakeAvailable(${dep_names})
    else()
        message(STATUS "${fetch_output}")
        
        # Now declare and populate (sources already fetched by Python)
        foreach(dep_name ${dep_names})
            foreach(entry ${dep_args_list})
                list(GET entry 0 entry_name)
                if(entry_name STREQUAL dep_name)
                    list(SUBLIST entry 1 -1 dep_args)
                    FetchContent_Declare(${dep_name} ${dep_args})
                    break()
                endif()
            endforeach()
        endforeach()
        FetchContent_MakeAvailable(${dep_names})
    endif()
endfunction()

#
# kis_parallel_clone_first_party(packages_to_clone_var)
#
# Parallel git clone for missing first-party packages.
#
# Arguments:
#   packages_to_clone_var - Name of variable containing list of package info:
#                          Each entry: "name|||url|||tag|||destination"
#                          (Using ||| separator to avoid CMake list parsing issues)
#
# Example:
#   set(packages_to_clone
#       "kis_rendering|||https://github.com/org/kis_rendering.git|||main|||/path/to/kis_packages/kis_rendering"
#       "kis_physics|||https://github.com/org/kis_physics.git|||main|||/path/to/kis_packages/kis_physics"
#   )
#   kis_parallel_clone_first_party(packages_to_clone)
#
function(kis_parallel_clone_first_party packages_to_clone_var)
    set(packages_to_clone ${${packages_to_clone_var}})
    
    list(LENGTH packages_to_clone num_packages)
    if(num_packages EQUAL 0)
        return()
    endif()
    
    if(NOT KIS_PARALLEL_FETCH_AVAILABLE)
        # Fallback to sequential (call original sequential logic)
        set(${packages_to_clone_var} ${packages_to_clone} PARENT_SCOPE)
        return()
    endif()

    find_package(Git QUIET REQUIRED)
    
    # Prepare data file for Python script
    set(clone_data_file "${CMAKE_BINARY_DIR}/_parallel_clone_data.json")
    set(json_content "{\n  \"packages\": [\n")
    
    set(first TRUE)
    foreach(package_info ${packages_to_clone})
        # Parse: name|||url|||tag|||destination (using ||| separator to avoid CMake list issues)
        string(REPLACE "|||" ";" package_info_list "${package_info}")
        
        list(LENGTH package_info_list info_length)
        if(info_length LESS 4)
            message(WARNING "Malformed package info: ${package_info} (expected 4 parts, got ${info_length})")
            continue()
        endif()
        
        list(GET package_info_list 0 pkg_name)
        list(GET package_info_list 1 pkg_url)
        list(GET package_info_list 2 pkg_tag)
        list(GET package_info_list 3 pkg_destination)
        
        if(NOT first)
            string(APPEND json_content ",\n")
        endif()
        set(first FALSE)
        
        # Use temp location for atomic move (at same level as destination, not inside it)
        get_filename_component(pkg_parent "${pkg_destination}" DIRECTORY)
        set(temp_clone_dir "${pkg_parent}/_temp_${pkg_name}")
        
        # Escape backslashes for JSON (Windows paths)
        string(REPLACE "\\" "\\\\" temp_clone_dir_json "${temp_clone_dir}")
        string(REPLACE "\\" "\\\\" pkg_destination_json "${pkg_destination}")
        
        string(APPEND json_content "    {\n")
        string(APPEND json_content "      \"name\": \"${pkg_name}\",\n")
        string(APPEND json_content "      \"url\": \"${pkg_url}\",\n")
        string(APPEND json_content "      \"tag\": \"${pkg_tag}\",\n")
        string(APPEND json_content "      \"temp_dir\": \"${temp_clone_dir_json}\",\n")
        string(APPEND json_content "      \"final_dir\": \"${pkg_destination_json}\"\n")
        string(APPEND json_content "    }")
    endforeach()
    
    # Escape Git executable path for JSON
    string(REPLACE "\\" "\\\\" git_executable_json "${GIT_EXECUTABLE}")
    
    string(APPEND json_content "\n  ],\n")
    string(APPEND json_content "  \"worker_count\": ${KIS_PARALLEL_FETCH_WORKERS},\n")
    string(APPEND json_content "  \"git_executable\": \"${git_executable_json}\"\n")
    string(APPEND json_content "}\n")
    
    file(WRITE "${clone_data_file}" "${json_content}")
    
    # Execute Python parallel clone script
    set(parallel_script "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../tools/parallel_fetch.py")
    
    message(STATUS "Cloning ${num_packages} first-party packages in parallel (${KIS_PARALLEL_FETCH_WORKERS} workers)...")
    
    execute_process(
        COMMAND ${Python3_EXECUTABLE} "${parallel_script}" "${clone_data_file}" "--mode=clone"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        RESULT_VARIABLE clone_result
        OUTPUT_VARIABLE clone_output
        ERROR_VARIABLE clone_error
    )
    
    if(NOT clone_result EQUAL 0)
        message(FATAL_ERROR 
            "Parallel first-party clone failed:\n"
            "${clone_output}\n${clone_error}\n"
            "\n"
            "This usually indicates network issues or invalid git URLs.\n"
            "Check the error messages above for specific package failures."
        )
    else()
        message(STATUS "${clone_output}")
        message(STATUS "Successfully cloned all first-party packages")
        
        # Packages were cloned during this configuration run
        # CMake needs to re-run to properly detect the new directories
        message(STATUS "")
        message(STATUS "==============================================================")
        message(STATUS "New packages were cloned. Please re-run CMake configuration:")
        message(STATUS "  cmake --preset release")
        message(STATUS "==============================================================")
        message(STATUS "")
        message(FATAL_ERROR "Configuration incomplete - re-run required after cloning packages")
    endif()
endfunction()