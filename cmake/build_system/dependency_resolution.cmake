# cmake/build_system/dependency_resolution.cmake

#
# kis_resolve_and_sync_packages()
#
# Discovers first-party dependencies recursively and clones missing ones
# from trusted, package-provided remote locations.
#
function(kis_resolve_and_sync_packages)
    set(PACKAGES_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/kis_packages")
    find_package(Git QUIET REQUIRED)

    # State tracking
    set(known_remotes "") # Associative list: name -> "url;tag"
    set(resolved_deps "") # All dependencies mentioned by present packages
    set(packages_on_disk "")

    # The main resolution loop. We keep iterating until a full pass finds no new packages to clone.
    while(TRUE)
        set(cloned_this_pass FALSE)

        # 1. Discover all packages currently on disk
        file(GLOB current_packages LIST_DIRECTORIES true RELATIVE "${PACKAGES_ROOT}" "${PACKAGES_ROOT}/*")
        set(packages_on_disk "")
        foreach(pkg_dir ${current_packages})
            if(EXISTS "${PACKAGES_ROOT}/${pkg_dir}/kis.package.cmake")
                get_filename_component(pkg_name ${pkg_dir} NAME)
                list(APPEND packages_on_disk ${pkg_name})
            endif()
        endforeach()

        # 2. Scan manifests of present packages for dependency info
        foreach(pkg_name ${packages_on_disk})
            # Use include in a function scope to read variables without polluting the parent scope
            function(_read_manifest)
                include("${PACKAGES_ROOT}/${pkg_name}/kis.package.cmake")
                set(DEPS ${PACKAGE_DEPENDENCIES} PARENT_SCOPE)
                set(REMOTES ${PACKAGE_REMOTES} PARENT_SCOPE)
            endfunction()
            _read_manifest()

            list(APPEND resolved_deps ${DEPS})
            list(APPEND known_remotes ${REMOTES})
        endforeach()

        list(REMOVE_DUPLICATES resolved_deps)

        # 3. Resolve: Find which dependencies are missing
        foreach(dep_name ${resolved_deps})
            if(NOT dep_name IN_LIST packages_on_disk)
                # This dependency is missing. We need to find its remote and clone it.
                set(remote_found FALSE)
                list(LENGTH known_remotes num_remotes)
                math(EXPR last_remote "${num_remotes} - 1")
                foreach(index RANGE 0 ${last_remote} 3)
                    list(SUBLIST known_remotes ${index} 3 remote_info)
                    list(GET remote_info 0 remote_pkg_name)
                    if(remote_pkg_name STREQUAL dep_name)
                        list(GET remote_info 1 pkg_url)
                        list(GET remote_info 2 pkg_tag)
                        set(remote_found TRUE)
                        break()
                    endif()
                endforeach()

                if(NOT remote_found)
                    message(FATAL_ERROR "Dependency '${dep_name}' is required but no package provides its remote location. Please add it to a kis.package.cmake file.")
                endif()

                # 4. Security Check: Validate against whitelist
                set(is_trusted FALSE)
                foreach(prefix ${KIS_TRUSTED_URL_PREFIXES})
                    if(pkg_url STARTS_WITH "${prefix}")
                        set(is_trusted TRUE)
                        break()
                    endif()
                endforeach()

                if(NOT is_trusted)
                    message(FATAL_ERROR "Package '${dep_name}' remote URL '${pkg_url}' is not in the trusted list (KIS_TRUSTED_URL_PREFIXES).")
                endif()

                # 5. Clone the missing package
                message(STATUS "Resolving missing dependency: Cloning '${dep_name}'...")
                set(pkg_destination "${PACKAGES_ROOT}/${dep_name}")
                execute_process(COMMAND ${GIT_EXECUTABLE} clone --branch ${pkg_tag} --depth 1 --recursive ${pkg_url} ${pkg_destination} RESULT_VARIABLE clone_result OUTPUT_QUIET ERROR_QUIET)
                if(clone_result EQUAL 0)
                    set(cloned_this_pass TRUE)
                    # Add to packages_on_disk so we don't try to clone it again this loop
                    list(APPEND packages_on_disk ${dep_name}) 
                else()
                    message(FATAL_ERROR "Failed to clone '${dep_name}'.")
                endif()
            endif()
        endforeach()
        
        if(NOT cloned_this_pass)
            break() # Exit the while loop if we made a full pass with no new clones
        endif()
    endwhile()
endfunction()