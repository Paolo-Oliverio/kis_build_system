# cmake/build_system/package_configuration.cmake

#
# _kis_create_skipped_package_stub (INTERNAL)
#
# Creates a dummy INTERFACE target for a package that is being skipped.
# This prevents link errors in packages that may still depend on it.
# This function is mocked during testing.
#
function(_kis_create_skipped_package_stub package_name)
    if(NOT TARGET ${package_name})
        add_library(${package_name} INTERFACE IMPORTED GLOBAL)
        message(STATUS "  -> Created stub target for skipped package: ${package_name}")
    endif()
    if(NOT TARGET kis::${package_name})
        add_library(kis::${package_name} ALIAS ${package_name})
    endif()
endfunction()


# ==============================================================================
#           PHASE 1: PACKAGE CONFIGURATION
# ==============================================================================
function(configure_discovered_packages)
    set(package_paths ${ARGN})
    # Use the new state function to set package paths
    kis_state_set_all_package_paths("${package_paths}")
    
    kis_get_current_variant_name(current_variant)
    kis_get_variant_abi_group("${current_variant}" current_abi_group)
    message(STATUS "Configuring packages for variant: ${current_variant} (ABI: ${current_abi_group})")
    set(base_variant "release")
    if(current_abi_group STREQUAL "DEBUG")
        set(base_variant "debug")
    endif()

    foreach(package_path ${package_paths})
        kis_get_package_name_from_path("${package_path}" package_name)
        set(should_build TRUE)
        set(should_import FALSE)
        set(skip_reason "")
        
        kis_read_package_manifest_json(PACKAGE_PATH "${package_path}")
        
        # A package should only be built if its feature requirements are met.
        # An empty "features" list means it has no requirements and should always be considered.
        if(DEFINED MANIFEST_FEATURES AND NOT "${MANIFEST_FEATURES}" STREQUAL "")
            set(should_build FALSE) # Assume skip, unless a feature matches
            foreach(required_feature ${MANIFEST_FEATURES})
                if(required_feature IN_LIST KIS_ACTIVE_FEATURES)
                    set(should_build TRUE)
                    break()
                endif()
            endforeach()
            if(NOT should_build)
                set(skip_reason "requires one of features [${MANIFEST_FEATURES}], but active features are [${KIS_ACTIVE_FEATURES}]")
            endif()
        endif()

        if(NOT DEFINED MANIFEST_ABI_VARIANT)
            set(MANIFEST_ABI_VARIANT "PER_CONFIG")
        endif()
        if(should_build)
            if(MANIFEST_ABI_VARIANT STREQUAL "ABI_INVARIANT")
                if(NOT current_variant STREQUAL "release" AND NOT current_variant STREQUAL "debug")
                    set(should_build FALSE)
                    set(should_import TRUE)
                    set(skip_reason "ABI_INVARIANT package only builds in release/debug variants")
                endif()
            elseif(MANIFEST_ABI_VARIANT STREQUAL "PER_CONFIG")
                if(DEFINED MANIFEST_SUPPORTED_VARIANTS)
                    set(supported_variants "${MANIFEST_SUPPORTED_VARIANTS}")
                else()
                    set(supported_variants "release;debug")
                endif()
                if(NOT "release" IN_LIST supported_variants)
                    list(APPEND supported_variants "release")
                endif()
                if(NOT "debug" IN_LIST supported_variants)
                    list(APPEND supported_variants "debug")
                endif()
                if(NOT current_variant IN_LIST supported_variants)
                    set(should_build FALSE)
                    set(should_import TRUE)
                    set(skip_reason "PER_CONFIG package does not support variant '${current_variant}' (supports: ${supported_variants})")
                endif()
            endif()
        endif()
        
        if(should_build)
            # Add KIS dependencies to the central state, respecting implicit conditions
            if(DEFINED MANIFEST_KIS_DEPENDENCIES AND MANIFEST_KIS_DEPENDENCIES)
                string(JSON num_deps ERROR_VARIABLE err LENGTH "${MANIFEST_KIS_DEPENDENCIES}")
                if(NOT err AND num_deps GREATER 0)
                    math(EXPR last_idx "${num_deps} - 1")
                    foreach(i RANGE ${last_idx})
                        string(JSON dep_obj GET "${MANIFEST_KIS_DEPENDENCIES}" ${i})
                        
                        set(is_active TRUE)
                        string(JSON dep_scope_json ERROR_VARIABLE scope_err GET "${dep_obj}" "scope")
                        if(NOT scope_err)
                            set(dep_scopes "")
                            string(JSON num_scopes LENGTH "${dep_scope_json}")
                            math(EXPR last_scope_idx "${num_scopes} - 1")
                            foreach(j RANGE ${last_scope_idx})
                                string(JSON scope_item GET "${dep_scope_json}" ${j})
                                list(APPEND dep_scopes ${scope_item})
                            endforeach()
                            
                            list(LENGTH dep_scopes num_scopes_val)
                            if(num_scopes_val EQUAL 1)
                                list(GET dep_scopes 0 single_scope)
                                if(single_scope STREQUAL "tests" AND NOT KIS_BUILD_TESTS)
                                    set(is_active FALSE)
                                elseif(single_scope STREQUAL "samples" AND NOT KIS_BUILD_SAMPLES)
                                    set(is_active FALSE)
                                elseif(single_scope STREQUAL "benchmarks" AND NOT KIS_BUILD_BENCHMARKS)
                                    set(is_active FALSE)
                                endif()
                            endif()
                        endif()

                        if(is_active)
                            kis_state_add_kis_dependency("${dep_obj}")
                        endif()
                    endforeach()
                endif()
            endif()
            # Handle TPL dependencies using the refactored function which also has implicit conditions
            if(DEFINED MANIFEST_TPL_DEPENDENCIES AND MANIFEST_TPL_DEPENDENCIES)
                kis_handle_third_party_dependencies("${package_name}" "${MANIFEST_TPL_DEPENDENCIES}")
            endif()
        endif()
        
        if(NOT should_build)
            if(should_import)
                kis_message_verbose("Package '${package_name}': ${skip_reason}")
                message(STATUS "  -> Importing ${package_name} from ${base_variant} variant")
                _kis_create_imported_package_target("${package_name}" "${package_path}" "${base_variant}")
            else()
                kis_message_verbose("Skipping package '${package_name}': ${skip_reason}")
                # THE FIX: Call the new helper function which can be mocked.
                _kis_create_skipped_package_stub(${package_name})
            endif()
        else()
            kis_profile_begin("${package_name}" "configure")
            if(DEFINED MANIFEST_TYPE)
                set(pkg_platform "common")
                if(DEFINED MANIFEST_PLATFORMS AND MANIFEST_PLATFORMS) 
                    list(GET MANIFEST_PLATFORMS 0 pkg_platform) 
                endif()
                kis_graph_add_node("${package_name}" "${MANIFEST_TYPE}" "${pkg_platform}")
            endif()
            set(source_dir ${package_path})
            set(binary_dir "${CMAKE_BINARY_DIR}/_deps/${package_name}-build")

            # --- THE CHANGE: Create the context sandwich around add_subdirectory ---
            set(_KIS_CTX_CURRENT_PACKAGE_ROOT "${package_path}" CACHE INTERNAL "Active package context for add_subdirectory")
            add_subdirectory(${source_dir} ${binary_dir})
            # Unset the context variable to keep state clean for the next package.
            unset(_KIS_CTX_CURRENT_PACKAGE_ROOT CACHE)

            kis_profile_end("${package_name}" "configure")
        endif()
    endforeach()
endfunction()

# ==============================================================================
#           PHASE 2: DEPENDENCY LINKING
# ==============================================================================
function(link_all_package_dependencies)
    set(all_packages ${ARGN})
    foreach(package_path ${all_packages})
        kis_get_package_name_from_path("${package_path}" package_name)
        if(TARGET ${package_name})
            # Check for pending links using the new CACHE variable pattern
            set(cache_var "_KIS_CTX_PENDING_LINKS_${package_name}")
            if(DEFINED CACHE{${cache_var}})
                kis_execute_deferred_links(${package_name})
            else()
                kis_message_verbose("No deferred links for '${package_name}' (imported or no dependencies)")
            endif()
        else()
            kis_message_verbose("Skipping deferred links for '${package_name}' (target does not exist)")
        endif()
    endforeach()
endfunction()