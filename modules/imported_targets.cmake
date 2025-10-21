# cmake/build_system/imported_targets.cmake
#
# Provides the logic for creating IMPORTED CMake targets. This is a critical
# feature for variant-based builds, allowing packages that do not support a
# specific variant (e.g., 'profiling') to be consumed by linking against
# their pre-compiled artifacts from a compatible base variant (e.g., 'release').
# Includes robust circular dependency detection.

#
# _kis_create_imported_package_target
#
# Creates an IMPORTED library target that points to a pre-compiled package
# from a compatible base variant (release or debug).
#
# This is used when a package doesn't support the current variant.
#
# Includes circular dependency detection to prevent infinite recursion.
#
function(_kis_create_imported_package_target package_name package_path base_variant)
    if(TARGET ${package_name})
        return()  # Target already exists
    endif()
    
    # Circular dependency detection using CACHE variables
    set(creating_var "_KIS_CTX_CREATING_IMPORTED_${package_name}")
    if(DEFINED CACHE{${creating_var}} AND ${${creating_var}})
        # We've detected a circular dependency
        set(dependency_stack "${_KIS_CTX_IMPORT_DEPENDENCY_STACK}")
        list(APPEND dependency_stack ${package_name})
        
        kis_message_fatal_actionable(
            "Circular Dependency Detected"
            "Cannot create IMPORTED target for '${package_name}'\n  \n  Dependency cycle:\n  ${dependency_stack}\n  \n  This means packages depend on each other in a loop."
            "Fix the package dependencies to remove the cycle:\n     1. Review kis.package.json files in the cycle\n     2. Reorganize dependencies to be acyclic\n     3. Consider extracting common code to a new package"
        )
    endif()
    
    # Mark this package as being created (push to stack)
    set(${creating_var} TRUE CACHE INTERNAL "Import guard" FORCE)
    set(_KIS_CTX_IMPORT_DEPENDENCY_STACK "${_KIS_CTX_IMPORT_DEPENDENCY_STACK};${package_name}" CACHE INTERNAL "Import stack" FORCE)
    
    # Cache install path globally to avoid repeated filesystem searches
    if(NOT DEFINED CACHE{KIS_BASE_INSTALL_PATH})
        # Determine the base build directory - look for installed artifacts
        # Try multiple possible install locations
        set(possible_install_dirs
            "${CMAKE_INSTALL_PREFIX}"
            "${CMAKE_BINARY_DIR}/../_install/kis_sdk-0.1.0"
            "${CMAKE_SOURCE_DIR}/../_install/kis_sdk-0.1.0"
            "${CMAKE_SOURCE_DIR}/_install/kis_sdk-0.1.0"
        )
        
        set(found_install_dir "")
        foreach(try_dir ${possible_install_dirs})
            if(EXISTS "${try_dir}/lib")
                set(found_install_dir "${try_dir}")
                break()
            endif()
        endforeach()
        
        set(KIS_BASE_INSTALL_PATH "${found_install_dir}" CACHE INTERNAL "Cached install path for imported targets")
    endif()
    
    set(base_install_dir "${KIS_BASE_INSTALL_PATH}")
    
    if(NOT base_install_dir)
        message(STATUS "  -> Cannot create imported target: no installed artifacts found")
        message(STATUS "     Please build and install the ${base_variant} variant first")
        message(STATUS "     Commands: cmake --build --preset ${base_variant} && cmake --install build/${base_variant}")
        return()
    endif()
    
    # Read the package manifest to determine library type
    kis_read_package_manifest_json("${package_path}")
    if(NOT DEFINED MANIFEST_TYPE)
        kis_collect_warning("Cannot create imported target for ${package_name}: 'type' not found in manifest")
        return()
    endif()
    
    # Determine the package type (library or executable)
    set(is_interface FALSE)
    set(is_executable FALSE)
    
    if(MANIFEST_TYPE STREQUAL "INTERFACE")
        set(is_interface TRUE)
        kis_message_verbose("[OK] Package '${package_name}' explicitly declares type \"INTERFACE\"")
    elseif(MANIFEST_TYPE STREQUAL "EXECUTABLE")
        set(is_executable TRUE)
        kis_message_verbose("[OK] Package '${package_name}' explicitly declares type \"EXECUTABLE\"")
    endif()
    
    if(is_interface)
        # For interface libraries, create an interface target with the include directories
        message(STATUS "  -> Creating IMPORTED INTERFACE target: ${package_name} (header-only)")
        add_library(${package_name} INTERFACE IMPORTED GLOBAL)
        
        # Add include directories from the installed location
        if(EXISTS "${base_install_dir}/include")
            set_target_properties(${package_name} PROPERTIES
                INTERFACE_INCLUDE_DIRECTORIES "${base_install_dir}/include"
            )
        endif()
        
        # Create kis:: namespace alias for consistency with built packages
        if(NOT TARGET kis::${package_name})
            add_library(kis::${package_name} ALIAS ${package_name})
        endif()
    elseif(is_executable)
        # For executables, create a dummy interface target for dependency tracking
        message(STATUS "  -> Creating IMPORTED EXECUTABLE target: ${package_name}")
        add_library(${package_name} INTERFACE IMPORTED GLOBAL)
        
        # Store executable location as property for consumers who need to run it
        if(WIN32)
            set(exe_location "${base_install_dir}/bin/${package_name}.exe")
        else()
            set(exe_location "${base_install_dir}/bin/${package_name}")
        endif()
        
        if(EXISTS "${exe_location}")
            set_target_properties(${package_name} PROPERTIES
                IMPORTED_LOCATION "${exe_location}"
            )
            kis_message_verbose("     Executable location: ${exe_location}")
        endif()
        
        # Create kis:: namespace alias for consistency with built packages
        if(NOT TARGET kis::${package_name})
            add_library(kis::${package_name} ALIAS ${package_name})
        endif()
    else()
        # For compiled libraries, create an imported target pointing to the base variant build
        message(STATUS "  -> Creating IMPORTED target: ${package_name} from ${base_variant} variant")
        kis_message_verbose("     Searching for pre-built artifacts...")
        
        # Use the correct platform identifier that includes architecture
        # KIS_PLATFORM_ID is set by platform_setup.cmake (e.g., "windows-x64", "linux-x64")
        if(NOT DEFINED KIS_PLATFORM_ID)
            kis_message_fatal_actionable(
                "Missing Platform Configuration"
                "KIS_PLATFORM_ID is not defined - platform_setup.cmake may not have been included"
                "Ensure platform_setup.cmake is included before discovery.cmake"
            )
        endif()
        
        # Determine library file naming based on platform
        if(WIN32)
            set(lib_prefix "")
            set(lib_suffix ".lib")
        elseif(APPLE)
            set(lib_prefix "lib")
            set(lib_suffix ".a")
        else()
            set(lib_prefix "lib")
            set(lib_suffix ".a")
        endif()
        
        # Try multiple possible library locations:
        # 1. Platform+arch-specific with base variant: lib/windows-x64-release/
        # 2. Platform+arch-specific without variant: lib/windows-x64/
        # 3. Direct in lib: lib/
        set(possible_lib_paths
            "${base_install_dir}/lib/${KIS_PLATFORM_ID}-${base_variant}/${lib_prefix}${package_name}${lib_suffix}"
            "${base_install_dir}/lib/${KIS_PLATFORM_ID}/${lib_prefix}${package_name}${lib_suffix}"
            "${base_install_dir}/lib/${lib_prefix}${package_name}${lib_suffix}"
        )
        
        set(lib_file "")
        foreach(try_path ${possible_lib_paths})
            if(EXISTS "${try_path}")
                set(lib_file "${try_path}")
                break()
            endif()
        endforeach()
        
        if(NOT lib_file)
            set(search_list "")
            foreach(try_path ${possible_lib_paths})
                string(APPEND search_list "       • ${try_path}\n")
            endforeach()
            
            kis_message_fatal_actionable(
                "Missing Pre-Built Library: ${package_name}"
                "Cannot import package '${package_name}' for variant '${current_variant}'\n  \n  Reason: No pre-built library found for base variant '${base_variant}'\n  \n  Searched locations:\n${search_list}  \n  This usually means the '${base_variant}' variant hasn't been built and installed yet."
                "Build and install the base variant first:\n     cmake --build --preset ${base_variant}\n     cmake --install build/${base_variant}\n     cmake --build --preset ${current_variant}"
            )
        endif()
        
        # Create the imported target
        add_library(${package_name} STATIC IMPORTED GLOBAL)
        set_target_properties(${package_name} PROPERTIES
            IMPORTED_LOCATION "${lib_file}"
        )
        
        # Add include directories
        if(EXISTS "${base_install_dir}/include")
            set_target_properties(${package_name} PROPERTIES
                INTERFACE_INCLUDE_DIRECTORIES "${base_install_dir}/include"
            )
        endif()
        
        # Create kis:: namespace alias for consistency with built packages
        if(NOT TARGET kis::${package_name})
            add_library(kis::${package_name} ALIAS ${package_name})
        endif()
        
        kis_message_verbose("     Imported location: ${lib_file}")
    endif()
    
    # Resolve dependencies of imported packages transitively
    # This ensures that if package A depends on package B (both unsupported),
    # and package C depends on A, then C gets both A and B's IMPORTED targets
    if(DEFINED MANIFEST_KIS_DEPENDENCIES)
        kis_message_verbose("     Resolving dependencies of imported package '${package_name}'")
        
        string(JSON num_deps LENGTH "${MANIFEST_KIS_DEPENDENCIES}")
        if(num_deps GREATER 0)
            math(EXPR last_idx "${num_deps} - 1")
            foreach(i RANGE ${last_idx})
                string(JSON dep_obj GET "${MANIFEST_KIS_DEPENDENCIES}" ${i})
                string(JSON dep_name GET "${dep_obj}" "name")

                # Each dependency might be just a name or need to be created as IMPORTED too
                if(NOT TARGET ${dep_name})
                    # Dependency doesn't exist - it might also need to be imported
                    # Find its package path from the central state
                    kis_state_get_all_package_paths(all_pkg_paths)
                    foreach(dep_path ${all_pkg_paths})
                        get_filename_component(pkg_name_from_path ${dep_path} NAME)
                        if(pkg_name_from_path STREQUAL dep_name)
                            kis_message_verbose("       -> Dependency '${dep_name}' not found, creating IMPORTED target")
                            _kis_create_imported_package_target("${dep_name}" "${dep_path}" "${base_variant}")
                            break()
                        endif()
                    endforeach()
                endif()
                
                # Add the dependency to this IMPORTED target's interface
                if(TARGET ${dep_name})
                    set_property(TARGET ${package_name} APPEND PROPERTY
                        INTERFACE_LINK_LIBRARIES ${dep_name}
                    )
                elseif(TARGET kis::${dep_name})
                    set_property(TARGET ${package_name} APPEND PROPERTY
                        INTERFACE_LINK_LIBRARIES kis::${dep_name}
                    )
                endif()
            endforeach()
        endif()
    endif()
    
    # Unmark this package as being created (pop from stack)
    set(${creating_var} FALSE CACHE INTERNAL "Import guard" FORCE)
    set(dependency_stack "${_KIS_CTX_IMPORT_DEPENDENCY_STACK}")
    list(REMOVE_AT dependency_stack -1)
    set(_KIS_CTX_IMPORT_DEPENDENCY_STACK "${dependency_stack}" CACHE INTERNAL "Import stack" FORCE)
endfunction()