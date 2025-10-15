# cmake/build_system/discovery.cmake
#
# Provides functions for discovering KIS SDK packages, including handling
# platform-specific packages and platform abstraction groups (e.g., 'desktop', 'unix').

# ==============================================================================
#           PRIMARY DISCOVERY FUNCTION
# ==============================================================================

#
# discover_and_map_packages
#
# Discovers all common, platform-group, and platform-specific packages.
# It builds a final list of all packages to be configured and a definitive
# "override map" that specifies which packages replace others. The logic
# ensures that more specific platforms (e.g., 'windows') always take
# precedence over more general groups (e.g., 'desktop').
#
# This function requires KIS_PLATFORM_TAGS to be set globally.
#
function(discover_and_map_packages out_all_package_paths out_override_map_keys out_override_map_values)
    set(all_packages "")
    set(override_keys "")
    set(override_values "")
    set(packages_root "${CMAKE_CURRENT_SOURCE_DIR}/kis_packages")

    # 1. Define the search order: from the most general (common) to the most specific.
    # KIS_PLATFORM_TAGS should be pre-sorted from general to specific.
    set(search_paths "${packages_root}") # Start with common packages
    foreach(tag ${KIS_PLATFORM_TAGS})
        list(APPEND search_paths "${packages_root}/${tag}")
    endforeach()

    message(STATUS "Discovering packages in search paths: ${search_paths}")

    # 2. Process packages in each path.
    foreach(current_path ${search_paths})
        # Use unified globbing utility for consistent package discovery
        kis_glob_package_directories("${current_path}" discovered_packages)
        
        foreach(full_package_path ${discovered_packages})
            list(APPEND all_packages "${full_package_path}")
            kis_get_package_name_from_path("${full_package_path}" pkg_name)

            # 3. Validate platform compatibility using manifest
            kis_validate_package_platform(
                "${pkg_name}"
                "${full_package_path}"
                "${KIS_PLATFORM}"
                "${KIS_ACTIVE_TAGS}"
                is_compatible
                error_message
            )
            
            if(NOT is_compatible)
                kis_message_fatal_actionable(
                    "Platform Incompatibility"
                    "${error_message}"
                    "Either:\n     1. Remove the package from kis_packages/ if not needed\n     2. Move it to a platform-specific subdirectory (e.g., kis_packages/windows/)\n     3. Update the package's kis.package.cmake to support ${KIS_PLATFORM}\n     4. Build for a compatible platform using -DKIS_PLATFORM=<platform>"
                )
            endif()

            # 4. Check for and register overrides from the package manifest.
            set(manifest_file "${full_package_path}/kis.package.cmake")
            if(EXISTS "${manifest_file}")
                set(OVERRIDES "")
                function(_read_override_manifest)
                    include("${manifest_file}")
                    if(DEFINED PACKAGE_OVERRIDES)
                        set(OVERRIDES ${PACKAGE_OVERRIDES} PARENT_SCOPE)
                    endif()
                endfunction()
                _read_override_manifest()

                if(OVERRIDES)
                    foreach(overridden_pkg ${OVERRIDES})
                        message(STATUS "Platform Logic: Package '${pkg_name}' declares override for '${overridden_pkg}'")

                        list(FIND override_keys "${overridden_pkg}" index)
                        if(index GREATER -1)
                            list(GET override_values ${index} old_override_pkg)
                            message(STATUS "--> Specificity win: '${pkg_name}' replaces previous override '${old_override_pkg}' for '${overridden_pkg}'.")
                            list(REMOVE_AT override_values ${index})
                            list(INSERT override_values ${index} ${pkg_name})
                        else()
                            message(STATUS "--> Registering new override for '${overridden_pkg}' -> '${pkg_name}'.")
                            list(APPEND override_keys ${overridden_pkg})
                            list(APPEND override_values ${pkg_name})
                        endif()
                    endforeach()
                endif()
            endif()
        endforeach()
    endforeach()

    # 4. Final cleanup and output.
    list(REMOVE_DUPLICATES all_packages) # <-- TYPO CORRECTED HERE
    
    # 5. Validate all discovered manifests (with incremental optimization)
    list(LENGTH all_packages pkg_count)
    if(KIS_ENABLE_INCREMENTAL_VALIDATION)
        message(STATUS "Validating ${pkg_count} package manifests (incremental mode)...")
    else()
        message(STATUS "Validating ${pkg_count} package manifests (full validation)...")
    endif()
    foreach(pkg_path ${all_packages})
        kis_validate_package_if_needed("${pkg_path}")
    endforeach()

    set(${out_all_package_paths} ${all_packages} PARENT_SCOPE)
    set(${out_override_map_keys} ${override_keys} PARENT_SCOPE)
    set(${out_override_map_values} ${override_values} PARENT_SCOPE)
endfunction()


# ==============================================================================
#           PHASE 1: PACKAGE CONFIGURATION
# ==============================================================================

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
    
    # Circular dependency detection
    # Check if we're already in the process of creating this target
    get_property(is_creating GLOBAL PROPERTY KIS_CREATING_IMPORTED_${package_name})
    if(is_creating)
        # We've detected a circular dependency
        get_property(dependency_stack GLOBAL PROPERTY KIS_IMPORT_DEPENDENCY_STACK)
        list(APPEND dependency_stack ${package_name})
        
        kis_message_fatal_actionable(
            "Circular Dependency Detected"
            "Cannot create IMPORTED target for '${package_name}'\n  \n  Dependency cycle:\n  ${dependency_stack}\n  \n  This means packages depend on each other in a loop."
            "Fix the package dependencies to remove the cycle:\n     1. Review kis.package.cmake files in the cycle\n     2. Reorganize dependencies to be acyclic\n     3. Consider extracting common code to a new package"
        )
    endif()
    
    # Mark this package as being created (push to stack)
    set_property(GLOBAL PROPERTY KIS_CREATING_IMPORTED_${package_name} TRUE)
    get_property(dependency_stack GLOBAL PROPERTY KIS_IMPORT_DEPENDENCY_STACK)
    list(APPEND dependency_stack ${package_name})
    set_property(GLOBAL PROPERTY KIS_IMPORT_DEPENDENCY_STACK "${dependency_stack}")
    
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
    set(manifest_file "${package_path}/kis.package.cmake")
    if(NOT EXISTS "${manifest_file}")
        kis_collect_warning("Cannot create imported target for ${package_name}: manifest not found")
        return()
    endif()
    
    # Read manifest in clean scope
    unset(PACKAGE_ABI_VARIANT)
    unset(PACKAGE_TYPE)
    include("${manifest_file}")
    
    # Determine the package type (library or executable)
    # Priority 1: Use explicit PACKAGE_TYPE from manifest
    # Priority 2: Infer from PACKAGE_ABI_VARIANT (ABI_INVARIANT often means header-only) + CMakeLists.txt
    # Priority 3: Parse CMakeLists.txt as fallback
    set(is_interface FALSE)
    set(is_executable FALSE)
    
    if(DEFINED PACKAGE_TYPE)
        if(PACKAGE_TYPE STREQUAL "INTERFACE")
            set(is_interface TRUE)
            kis_message_verbose("[OK] Package '${package_name}' explicitly declares PACKAGE_TYPE \"INTERFACE\"")
        elseif(PACKAGE_TYPE STREQUAL "EXECUTABLE")
            set(is_executable TRUE)
            kis_message_verbose("[OK] Package '${package_name}' explicitly declares PACKAGE_TYPE \"EXECUTABLE\"")
        endif()
    elseif(DEFINED PACKAGE_ABI_VARIANT)
        # Heuristic: ABI_INVARIANT packages are often header-only or executables
        # But we should verify by checking CMakeLists.txt
        if(PACKAGE_ABI_VARIANT STREQUAL "ABI_INVARIANT" OR PACKAGE_ABI_VARIANT STREQUAL "DEFAULT")
            if(EXISTS "${package_path}/CMakeLists.txt")
                file(READ "${package_path}/CMakeLists.txt" cmakelists_content)
                if(cmakelists_content MATCHES "add_library\\(${package_name}[^)]*INTERFACE")
                    set(is_interface TRUE)
                    kis_message_verbose("[OK] Package '${package_name}' detected as INTERFACE (ABI_INVARIANT + CMakeLists.txt pattern)")
                elseif(cmakelists_content MATCHES "add_executable\\(${package_name}")
                    set(is_executable TRUE)
                    kis_message_verbose("[OK] Package '${package_name}' detected as EXECUTABLE (ABI_INVARIANT + CMakeLists.txt pattern)")
                endif()
            endif()
        endif()
    else()
        # Fallback: Parse CMakeLists.txt
        if(EXISTS "${package_path}/CMakeLists.txt")
            file(READ "${package_path}/CMakeLists.txt" cmakelists_content)
            if(cmakelists_content MATCHES "add_library\\(${package_name}[^)]*INTERFACE")
                set(is_interface TRUE)
                kis_message_verbose("[WARNING] Package '${package_name}' detected as INTERFACE from CMakeLists.txt only - consider adding explicit PACKAGE_TYPE")
            elseif(cmakelists_content MATCHES "add_executable\\(${package_name}")
                set(is_executable TRUE)
                kis_message_verbose("[WARNING] Package '${package_name}' detected as EXECUTABLE from CMakeLists.txt only - consider adding explicit PACKAGE_TYPE")
            endif()
        endif()
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
    set(manifest_file "${package_path}/kis.package.cmake")
    if(EXISTS "${manifest_file}")
        unset(PACKAGE_DEPENDENCIES)
        function(_read_imported_pkg_deps)
            include("${manifest_file}")
            if(DEFINED PACKAGE_DEPENDENCIES)
                set(PACKAGE_DEPENDENCIES "${PACKAGE_DEPENDENCIES}" PARENT_SCOPE)
            endif()
        endfunction()
        _read_imported_pkg_deps()
        
        if(DEFINED PACKAGE_DEPENDENCIES AND PACKAGE_DEPENDENCIES)
            kis_message_verbose("     Resolving dependencies of imported package '${package_name}': ${PACKAGE_DEPENDENCIES}")
            
            foreach(dep ${PACKAGE_DEPENDENCIES})
                # Each dependency might be just a name or need to be created as IMPORTED too
                if(NOT TARGET ${dep})
                    # Dependency doesn't exist - it might also need to be imported
                    # Find its package path
                    get_property(all_pkg_paths GLOBAL PROPERTY KIS_ALL_PACKAGE_PATHS)
                    foreach(dep_path ${all_pkg_paths})
                        get_filename_component(dep_name ${dep_path} NAME)
                        if(dep_name STREQUAL dep)
                            kis_message_verbose("       -> Dependency '${dep}' not found, creating IMPORTED target")
                            _kis_create_imported_package_target("${dep}" "${dep_path}" "${base_variant}")
                            break()
                        endif()
                    endforeach()
                endif()
                
                # Add the dependency to this IMPORTED target's interface
                if(TARGET ${dep})
                    set_property(TARGET ${package_name} APPEND PROPERTY
                        INTERFACE_LINK_LIBRARIES ${dep}
                    )
                elseif(TARGET kis::${dep})
                    set_property(TARGET ${package_name} APPEND PROPERTY
                        INTERFACE_LINK_LIBRARIES kis::${dep}
                    )
                endif()
            endforeach()
        endif()
    endif()
    
    # Unmark this package as being created (pop from stack)
    set_property(GLOBAL PROPERTY KIS_CREATING_IMPORTED_${package_name} FALSE)
    get_property(dependency_stack GLOBAL PROPERTY KIS_IMPORT_DEPENDENCY_STACK)
    list(REMOVE_AT dependency_stack -1)
    set_property(GLOBAL PROPERTY KIS_IMPORT_DEPENDENCY_STACK "${dependency_stack}")
endfunction()

#
# configure_discovered_packages
#
# Calls add_subdirectory for a list of packages.
# Filters packages based on:
#   1. PACKAGE_FEATURE_REQUIREMENTS - Required features must be active
#   2. PACKAGE_ABI_VARIANT - ABI_INVARIANT packages only build in plain release/debug
#   3. PACKAGE_SUPPORTED_VARIANTS - For PER_CONFIG packages, variant must be supported
#
# For packages that don't support the current variant, creates IMPORTED targets
# pointing to pre-compiled artifacts from a compatible base variant.
#
# By checking these BEFORE calling add_subdirectory(), we ensure that:
#   - Package CMakeLists.txt never runs for unsupported variants
#   - No third-party dependencies are registered for skipped packages
#   - No compilation happens for packages that won't be installed
#   - Linking phase succeeds because IMPORTED targets exist for all dependencies
#
function(configure_discovered_packages)
    set(package_paths ${ARGN})
    
    # Store package paths globally for recursive IMPORTED target creation
    set_property(GLOBAL PROPERTY KIS_ALL_PACKAGE_PATHS "${package_paths}")
    
    # Determine current variant once
    kis_get_current_variant_name(current_variant)
    kis_get_variant_abi_group("${current_variant}" current_abi_group)
    message(STATUS "Configuring packages for variant: ${current_variant} (ABI: ${current_abi_group})")
    
    # Determine base variant for fallback (release for RELEASE ABI group, debug for DEBUG)
    set(base_variant "release")
    if(current_abi_group STREQUAL "DEBUG")
        set(base_variant "debug")
    endif()

    foreach(package_path ${package_paths})
        get_filename_component(package_name ${package_path} NAME)
        
        set(manifest_file "${package_path}/kis.package.cmake")
        set(should_build TRUE)
        set(should_import FALSE)
        set(skip_reason "")
        
        if(EXISTS "${manifest_file}")
            # Read manifest to check build requirements
            # Use a clean scope to avoid variable pollution
            unset(PACKAGE_FEATURE_REQUIREMENTS)
            unset(PACKAGE_FEATURES)
            unset(PACKAGE_ABI_VARIANT)
            unset(PACKAGE_SUPPORTED_VARIANTS)
            include("${manifest_file}")

            # Check 1: Feature requirements
            if(DEFINED PACKAGE_FEATURES)
                set(_required_features ${PACKAGE_FEATURES})
            elseif(DEFINED PACKAGE_FEATURE_REQUIREMENTS)
                set(_required_features ${PACKAGE_FEATURE_REQUIREMENTS})
            else()
                set(_required_features "")
            endif()

            if(_required_features)
                set(should_build FALSE)
                foreach(required_feature ${_required_features})
                    if(required_feature IN_LIST KIS_ACTIVE_FEATURES)
                        set(should_build TRUE)
                        break()
                    endif()
                endforeach()

                if(NOT should_build)
                    set(skip_reason "requires features [${_required_features}], active: [${KIS_ACTIVE_FEATURES}]")
                endif()
            endif()
            
            # Default to PER_CONFIG if not specified
            if(NOT DEFINED PACKAGE_ABI_VARIANT)
                set(PACKAGE_ABI_VARIANT "PER_CONFIG")
            endif()
            
            # Check 2: ABI variant compatibility
            if(should_build)
                if(PACKAGE_ABI_VARIANT STREQUAL "ABI_INVARIANT" OR PACKAGE_ABI_VARIANT STREQUAL "DEFAULT")
                    # ABI_INVARIANT (formerly DEFAULT) packages only build in plain release/debug
                    # This is for header-only libraries or libraries with no variant-specific code
                    if(NOT current_variant STREQUAL "release" AND NOT current_variant STREQUAL "debug")
                        set(should_build FALSE)
                        set(should_import TRUE)
                        set(skip_reason "ABI_INVARIANT package only builds in release/debug variants")
                    endif()
                elseif(PACKAGE_ABI_VARIANT STREQUAL "PER_CONFIG")
                    # PER_CONFIG packages can support specific variants
                    # Get supported variants for this package
                    if(DEFINED PACKAGE_SUPPORTED_VARIANTS)
                        set(supported_variants "${PACKAGE_SUPPORTED_VARIANTS}")
                    else()
                        # By default, only release and debug are supported
                        set(supported_variants "release;debug")
                    endif()
                    
                    # Debug and release are ALWAYS implicitly supported
                    if(NOT "release" IN_LIST supported_variants)
                        list(APPEND supported_variants "release")
                    endif()
                    if(NOT "debug" IN_LIST supported_variants)
                        list(APPEND supported_variants "debug")
                    endif()
                    
                    # Check if current variant is supported
                    if(NOT current_variant IN_LIST supported_variants)
                        set(should_build FALSE)
                        set(should_import TRUE)
                        set(skip_reason "PER_CONFIG package does not support variant '${current_variant}' (supports: ${supported_variants})")
                    endif()
                endif()
            endif()
        endif()
        
        if(NOT should_build)
            if(should_import)
                kis_message_verbose("Package '${package_name}': ${skip_reason}")
                message(STATUS "  -> Importing ${package_name} from ${base_variant} variant")
                _kis_create_imported_package_target("${package_name}" "${package_path}" "${base_variant}")
            else()
                # Package is completely skipped (e.g., feature not enabled)
                # Create a dummy INTERFACE target to prevent link errors
                kis_message_verbose("Skipping package '${package_name}': ${skip_reason}")
                
                # Create stub target so dependencies don't fail
                if(NOT TARGET ${package_name})
                    add_library(${package_name} INTERFACE IMPORTED GLOBAL)
                    message(STATUS "  -> Created stub target for skipped package: ${package_name}")
                endif()
                
                # Create kis:: alias
                if(NOT TARGET kis::${package_name})
                    add_library(kis::${package_name} ALIAS ${package_name})
                endif()
            endif()
        else()
            message(STATUS "Configuring package: ${package_name}")
            
            # Start profiling this package (if enabled)
            kis_profile_begin("${package_name}" "configure")
            
            # Add to dependency graph (if enabled)
            if(DEFINED PACKAGE_TYPE)
                set(pkg_platform "common")
                if(DEFINED PACKAGE_PLATFORMS)
                    list(GET PACKAGE_PLATFORMS 0 pkg_platform)
                endif()
                kis_graph_add_node("${package_name}" "${PACKAGE_TYPE}" "${pkg_platform}")
            endif()
            
            set(source_dir ${package_path})
            set(binary_dir "${CMAKE_BINARY_DIR}/_deps/${package_name}-build")
            # Only call add_subdirectory if package should be built
            # This prevents CMakeLists.txt from running and registering dependencies
            add_subdirectory(${source_dir} ${binary_dir})
            
            # End profiling this package (if enabled)
            kis_profile_end("${package_name}" "configure")
        endif()
    endforeach()
endfunction()


# ==============================================================================
#           PHASE 2: DEPENDENCY LINKING
# ==============================================================================

#
# link_all_package_dependencies
#
# Executes all deferred dependency links for all discovered packages.
# This is Phase 2 of the build process - all targets must exist before calling this.
#
function(link_all_package_dependencies)
    set(all_packages ${ARGN})
    foreach(package_path ${all_packages})
        get_filename_component(package_name ${package_path} NAME)

        # Execute any deferred links for this package's main target
        if(TARGET ${package_name})
            # Only execute if there are actually pending links (avoid wasted property lookups)
            get_property(has_pending_links GLOBAL PROPERTY KIS_PENDING_LINKS_${package_name} SET)
            if(has_pending_links)
                kis_execute_deferred_links(${package_name})
            else()
                kis_message_verbose("No deferred links for '${package_name}' (imported or no dependencies)")
            endif()
        else()
            kis_message_verbose("Skipping deferred links for '${package_name}' (target does not exist)")
        endif()
    endforeach()
endfunction()