# cmake/build_system/dependency_resolution.cmake

#
# kis_resolve_and_sync_packages()
#
# Discovers first-party dependencies recursively and clones missing ones
# from trusted, package-provided remote locations.
#
# This function processes PACKAGE_DEPENDENCIES in the format:
#   "name;git_url;git_tag"
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

        # 1. Discover all packages currently on disk using unified utility
        kis_glob_package_directories("${PACKAGES_ROOT}" discovered_packages)
        set(packages_on_disk "")
        foreach(pkg_path ${discovered_packages})
            kis_get_package_name_from_path("${pkg_path}" pkg_name)
            list(APPEND packages_on_disk ${pkg_name})
        endforeach()

        # 2. Scan manifests of present packages for dependency info
        foreach(pkg_name ${packages_on_disk})
            # Use include in a function scope to read variables without polluting the parent scope
            function(_read_manifest)
                include("${PACKAGES_ROOT}/${pkg_name}/kis.package.cmake")
                set(DEPS ${PACKAGE_DEPENDENCIES} PARENT_SCOPE)
            endfunction()
            _read_manifest()

            if(NOT DEPS)
                continue()
            endif()

            # Parse PACKAGE_DEPENDENCIES which is in format: name;url;tag (as triplets)
            # When set() is used with quoted strings containing semicolons,
            # CMake automatically splits them into list elements
            # So "name;url;tag" becomes three separate list items
            
            list(LENGTH DEPS num_items)
            set(i 0)
            while(i LESS num_items)
                list(GET DEPS ${i} dep_name)
                math(EXPR i "${i} + 1")
                
                # Check if this looks like a URL (starts with http/https)
                if(dep_name MATCHES "^https?://")
                    # This means we have old-style format or incorrectly parsed
                    # Skip URLs that appear as names
                    kis_collect_warning("Skipping malformed dependency in ${pkg_name}: '${dep_name}' looks like a URL")
                    continue()
                endif()
                
                # Try to get URL and TAG
                set(dep_url "")
                set(dep_tag "")
                
                if(i LESS num_items)
                    list(GET DEPS ${i} potential_url)
                    if(potential_url MATCHES "^https?://")
                        set(dep_url ${potential_url})
                        math(EXPR i "${i} + 1")
                        
                        if(i LESS num_items)
                            list(GET DEPS ${i} dep_tag)
                            math(EXPR i "${i} + 1")
                        endif()
                    endif()
                endif()

                list(APPEND resolved_deps ${dep_name})
                
                if(dep_url AND dep_tag)
                    list(APPEND known_remotes ${dep_name} ${dep_url} ${dep_tag})
                endif()
            endwhile()
        endforeach()

        if(resolved_deps)
            list(REMOVE_DUPLICATES resolved_deps)
        endif()

        # 3. Resolve: Find which dependencies are missing and prepare for parallel clone
        set(packages_to_clone "")  # List of package info for parallel cloning
        
        foreach(dep_name ${resolved_deps})
            if(NOT dep_name IN_LIST packages_on_disk)
                # This dependency is missing. We need to find its remote and clone it.
                set(remote_found FALSE)
                list(LENGTH known_remotes num_remotes)
                set(i 0)
                while(i LESS num_remotes)
                    list(GET known_remotes ${i} remote_pkg_name)
                    math(EXPR i "${i} + 1")
                    if(i LESS num_remotes)
                        list(GET known_remotes ${i} pkg_url)
                        math(EXPR i "${i} + 1")
                    endif()
                    if(i LESS num_remotes)
                        list(GET known_remotes ${i} pkg_tag)
                        math(EXPR i "${i} + 1")
                    endif()
                    
                    if(remote_pkg_name STREQUAL dep_name)
                        set(remote_found TRUE)
                        break()
                    endif()
                endwhile()

                if(NOT remote_found)
                    message(FATAL_ERROR 
                        "\n[ERROR] Dependency Resolution Error\n"
                        "  Package: ${dep_name}\n"
                        "  Problem: No remote location provided\n"
                        "\n"
                        "  [SOLUTION] To fix, add to a kis.package.cmake file:\n"
                        "     set(PACKAGE_DEPENDENCIES\n"
                        "         \"${dep_name};https://github.com/your-org/${dep_name}.git;main\"\n"
                        "     )\n"
                    )
                endif()

                # 4. Security Check: Validate against whitelist
                kis_is_url_trusted(is_trusted "${pkg_url}" "${KIS_TRUSTED_URL_PREFIXES}")
                
                if(NOT is_trusted)
                    # Extract the base URL for helpful error message
                    string(REGEX MATCH "^(https?://[^/]+/[^/]+/)" url_base "${pkg_url}")
                    kis_list_to_string(trusted_list_str "${KIS_TRUSTED_URL_PREFIXES}" "\n         ")
                    kis_message_fatal_actionable(
                        "Security Error: Untrusted Package Source"
                        "Package: ${dep_name}\n  URL: ${pkg_url}\n  \n  This URL is not in the trusted prefix list."
                        "Edit kis_build_system/modules/sdk_options.cmake:\n     \n     set(KIS_TRUSTED_URL_PREFIXES\n         \"https://github.com/Paolo-Oliverio/\"\n         \"${url_base}\"  # <-- Add this line\n         CACHE STRING \"...\" FORCE\n     )\n  \n  Or temporarily via command line:\n     cmake -DKIS_TRUSTED_URL_PREFIXES=\"${url_base}\" ..\n  \n  Current trusted prefixes:\n     ${trusted_list_str}"
                    )
                else()
                    if(KIS_DIAGNOSTIC_MODE)
                        message(STATUS "  [OK] URL '${pkg_url}' validated against trusted prefixes")
                    endif()
                endif()

                # 5. Determine destination for this package (need to check temp location)
                # Create temp location to read manifest
                set(temp_clone_dir "${PACKAGES_ROOT}/_temp_${dep_name}")
                
                # For now, assume platform-agnostic (will be determined after clone)
                set(pkg_destination "${PACKAGES_ROOT}/${dep_name}")
                
                # Add to list for parallel cloning (use ||| separator to avoid CMake list parsing issues)
                list(APPEND packages_to_clone "${dep_name}|||${pkg_url}|||${pkg_tag}|||${pkg_destination}")
            endif()
        endforeach()
        
        # 6. Clone all missing packages in parallel (if any)
        list(LENGTH packages_to_clone num_to_clone)
        if(num_to_clone GREATER 0)
            message(STATUS "Found ${num_to_clone} missing first-party packages to clone...")
            
            # Use parallel cloning if available
            kis_parallel_clone_first_party(packages_to_clone)
            
            # After parallel clone, need to move packages to correct platform location
            foreach(package_info ${packages_to_clone})
                # Parse: name|||url|||tag|||destination
                string(REPLACE "|||" ";" package_info_list "${package_info}")
                list(GET package_info_list 0 dep_name)
                list(GET package_info_list 3 temp_destination)
                
                # Check if package needs to be moved to platform-specific location
                kis_get_package_platform_preference(platform_pref "${temp_destination}")
                
                if(platform_pref)
                    set(final_destination "${PACKAGES_ROOT}/${platform_pref}/${dep_name}")
                    if(NOT final_destination STREQUAL temp_destination)
                        message(STATUS "  -> Moving ${dep_name} to platform-specific location: ${platform_pref}/")
                        
                        # Ensure parent directory exists
                        get_filename_component(final_dest_parent "${final_destination}" DIRECTORY)
                        file(MAKE_DIRECTORY "${final_dest_parent}")
                        
                        # Move to final location
                        file(RENAME "${temp_destination}" "${final_destination}")
                    endif()
                endif()
                
                set(cloned_this_pass TRUE)
                # Add to packages_on_disk so we don't try to clone it again this loop
                list(APPEND packages_on_disk ${dep_name})
            endforeach()
        endif()
        
        if(NOT cloned_this_pass)
            break() # Exit the while loop if we made a full pass with no new clones
        endif()
    endwhile()
    
    message(STATUS "First-party dependency resolution complete. All packages available.")
endfunction()