# cmake/build_system/dependency_linking.cmake
#
# Implements the two-phase linking system with centralized resolution.

function(kis_defer_link_dependencies)
    set(options)
    set(oneValueArgs TARGET SCOPE) # Add SCOPE
    set(multiValueArgs PUBLIC PRIVATE INTERFACE)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if(NOT ARG_TARGET) 
        message(FATAL_ERROR "kis_defer_link_dependencies requires a TARGET argument.") 
    endif()

    if(NOT ARG_SCOPE)
        set(ARG_SCOPE "main") # Default scope if not provided
    endif()

    set(link_data "")
    if(ARG_PUBLIC) 
        list(APPEND link_data "PUBLIC;${ARG_PUBLIC}") 
    endif()
    if(ARG_PRIVATE) 
        list(APPEND link_data "PRIVATE;${ARG_PRIVATE}") 
    endif()
    if(ARG_INTERFACE) 
        list(APPEND link_data "INTERFACE;${ARG_INTERFACE}") 
    endif()
    if(link_data)
        # Store link data in a scope-specific cache variable
        set(cache_var "_KIS_CTX_PENDING_LINKS_${ARG_TARGET}_SCOPE_${ARG_SCOPE}")
        
        # Deduplicate: check if each (visibility, dependency) pair already exists
        set(existing_data ${${cache_var}})
        set(deduplicated_data "")
        set(current_visibility "")
        
        foreach(item ${link_data})
            if(item STREQUAL "PUBLIC" OR item STREQUAL "PRIVATE" OR item STREQUAL "INTERFACE")
                set(current_visibility ${item})
                list(APPEND deduplicated_data ${item})
            else()
                # Check if this (visibility, dependency) pair already exists
                set(pair_exists FALSE)
                set(check_visibility "")
                foreach(existing_item ${existing_data})
                    if(existing_item STREQUAL "PUBLIC" OR existing_item STREQUAL "PRIVATE" OR existing_item STREQUAL "INTERFACE")
                        set(check_visibility ${existing_item})
                    elseif(check_visibility STREQUAL current_visibility AND existing_item STREQUAL item)
                        set(pair_exists TRUE)
                        break()
                    endif()
                endforeach()
                
                if(NOT pair_exists)
                    list(APPEND deduplicated_data ${item})
                endif()
            endif()
        endforeach()
        
        # Only update cache if we have new data to add
        if(deduplicated_data)
            set(${cache_var} "${existing_data};${deduplicated_data}" CACHE INTERNAL "Deferred link data" FORCE)
        endif()
        
        # Register this target as needing its links executed later.
        kis_state_add_deferred_link_target(${ARG_TARGET})
    endif()
endfunction()

function(kis_link_from_manifest)
    set(options)
    set(oneValueArgs TARGET SCOPE) # Add SCOPE
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "" ${ARGN})
    if(NOT ARG_TARGET) 
        message(FATAL_ERROR "kis_link_from_manifest requires a TARGET argument.") 
    endif()
    if(NOT ARG_SCOPE)
        set(ARG_SCOPE "main")
    endif()

    kis_read_package_manifest_json()
    set(public_deps "")
    set(private_deps "")
    set(interface_deps "")

    macro(_process_dependency_list dep_list)
        string(JSON num_deps ERROR_VARIABLE err LENGTH "${dep_list}")
        if(err OR num_deps EQUAL 0) 
            return() 
        endif()
        math(EXPR last_idx "${num_deps} - 1")
        foreach(i RANGE ${last_idx})
            string(JSON dep_obj GET "${dep_list}" ${i})
            
            # --- SCOPE CHECK ---
            string(JSON dep_scope_json ERROR_VARIABLE scope_err GET "${dep_obj}" "scope")
            set(is_in_scope FALSE)
            if(scope_err)
                # If scope is not defined, default to 'all'
                set(is_in_scope TRUE)
            else()
                set(dep_scopes "")
                string(JSON num_scopes LENGTH "${dep_scope_json}")
                if(num_scopes GREATER 0)
                    math(EXPR last_scope_idx "${num_scopes} - 1")
                    foreach(j RANGE ${last_scope_idx})
                        string(JSON scope_item GET "${dep_scope_json}" ${j})
                        list(APPEND dep_scopes ${scope_item})
                    endforeach()
                endif()
                
                if("all" IN_LIST dep_scopes OR ARG_SCOPE IN_LIST dep_scopes)
                    set(is_in_scope TRUE)
                endif()
            endif()
            if(NOT is_in_scope)
                continue() # Skip this dependency if it's not for the current scope
            endif()
            # --- END SCOPE CHECK ---

            string(JSON dep_name GET "${dep_obj}" "name")
            string(JSON link_type ERROR_VARIABLE err GET "${dep_obj}" "link")
            if(err) 
                set(link_type "PRIVATE") 
            endif()

            set(targets_to_link "")
            string(JSON targets_json ERROR_VARIABLE targets_err GET "${dep_obj}" "targets")
            if(NOT targets_err)
                string(JSON num_targets LENGTH "${targets_json}")
                if(num_targets GREATER 0)
                    math(EXPR last_target_idx "${num_targets} - 1")
                    foreach(j RANGE ${last_target_idx})
                        string(JSON target_item GET "${targets_json}" ${j})
                        list(APPEND targets_to_link ${target_item})
                    endforeach()
                endif()
            endif()
            if(NOT targets_to_link)
                set(targets_to_link ${dep_name})
            endif()

            string(TOUPPER "${link_type}" link_type)
            if(link_type STREQUAL "PUBLIC") 
                list(APPEND public_deps ${targets_to_link})
            elseif(link_type STREQUAL "PRIVATE") 
                list(APPEND private_deps ${targets_to_link})
            elseif(link_type STREQUAL "INTERFACE") 
                list(APPEND interface_deps ${targets_to_link})
            else()
                list(APPEND private_deps ${targets_to_link}) 
            endif()
        endforeach()
    endmacro()
    if(DEFINED MANIFEST_KIS_DEPENDENCIES) 
        _process_dependency_list("${MANIFEST_KIS_DEPENDENCIES}") 
    endif()
    if(DEFINED MANIFEST_TPL_DEPENDENCIES) 
        _process_dependency_list("${MANIFEST_TPL_DEPENDENCIES}") 
    endif()
    if(public_deps OR private_deps OR interface_deps)
        kis_defer_link_dependencies(TARGET ${ARG_TARGET} SCOPE ${ARG_SCOPE} PUBLIC ${public_deps} PRIVATE ${private_deps} INTERFACE ${interface_deps})
    endif()
endfunction()

#
# Centralized resolution and correction function. Called ONCE.
#
function(kis_resolve_and_correct_all_links)
    message(STATUS "[PHASE 4a] Resolving and correcting all deferred links...")

    kis_state_get_override_map(override_keys override_values)
    kis_state_get_deferred_link_targets(targets_to_process)

    set(scopes "main" "tests" "samples" "benchmarks")

    foreach(package_name ${targets_to_process})
        foreach(scope ${scopes})
            set(cache_var "_KIS_CTX_PENDING_LINKS_${package_name}_SCOPE_${scope}")
            if(NOT DEFINED CACHE{${cache_var}})
                continue()
            endif()

            set(target_type "UNKNOWN")
            if(TARGET ${package_name})
                get_target_property(target_type ${package_name} TYPE)
            endif()

            set(link_data ${${cache_var}})
            set(current_visibility "")
            
            foreach(item ${link_data})
                if(item STREQUAL "PUBLIC" OR item STREQUAL "PRIVATE" OR item STREQUAL "INTERFACE")
                    set(current_visibility ${item})
                else()
                    set(original_dep_name ${item})
                    set(resolved_dep_name ${item})
                    
                    list(FIND override_keys "${resolved_dep_name}" index)
                    if(index GREATER -1)
                        list(GET override_values ${index} resolved_dep)
                        kis_message_verbose("  [${package_name}] Link override: ${original_dep_name} -> ${resolved_dep}")
                        set(resolved_dep_name ${resolved_dep})
                    endif()

                    set(final_link_target ${resolved_dep_name})
                    if(TARGET kis::${resolved_dep_name})
                        set(final_link_target "kis::${resolved_dep_name}")
                    endif()

                    set(final_visibility ${current_visibility})
                    if(target_type STREQUAL "INTERFACE_LIBRARY" AND NOT final_visibility STREQUAL "INTERFACE")
                        kis_message_warning_actionable("Linking Mismatch" ... )
                        set(final_visibility "INTERFACE")
                    endif()
                    
                    set(final_links_var "_KIS_CTX_FINAL_LINKS_${package_name}")
                    set(${final_links_var} "${${final_links_var}};${final_visibility};${final_link_target}" CACHE INTERNAL "Final, corrected link data" FORCE)
                    message(STATUS "  [${package_name}] Storing final link command for scope '${scope}': ${final_visibility} ${final_link_target}")
                endif()
            endforeach()
        endforeach()
    endforeach()
endfunction()


#
# This function is now just a simple executor of pre-processed link commands.
#
function(kis_execute_deferred_links TARGET_NAME)
    # This function remains the same as the previous version, as the resolution
    # logic correctly consolidates all scopes into one final link list.
    set(final_links_var "_KIS_CTX_FINAL_LINKS_${TARGET_NAME}")
    if(NOT DEFINED CACHE{${final_links_var}})
        return()
    endif()

    message(STATUS "[PHASE 4b] Executing links for target '${TARGET_NAME}'")
    
    set(final_link_data ${${final_links_var}})
    #message(STATUS "  [${TARGET_NAME}] Raw final link data from cache: '${final_link_data}'")
    
    set(public_deps "")
    set(private_deps "")
    set(interface_deps "")

    if(final_link_data)
        list(GET final_link_data 0 first_element)
        if("${first_element}" STREQUAL "")
            list(REMOVE_AT final_link_data 0)
        endif()
    endif()
    
    list(LENGTH final_link_data num_items)
    if(num_items GREATER 0)
        math(EXPR is_odd "${num_items} % 2")
        if(is_odd)
            message(FATAL_ERROR "  [${TARGET_NAME}] Malformed link data list (odd number of items): ${final_link_data}")
            return()
        endif()

        math(EXPR last_item_idx "${num_items} - 1")
        foreach(i RANGE 0 ${last_item_idx} 2)
            math(EXPR j "${i} + 1")
            list(GET final_link_data ${i} visibility)
            list(GET final_link_data ${j} dependency)

            if(visibility STREQUAL "PUBLIC")
                list(APPEND public_deps ${dependency})
            elseif(visibility STREQUAL "PRIVATE")
                list(APPEND private_deps ${dependency})
            elseif(visibility STREQUAL "INTERFACE")
                list(APPEND interface_deps ${dependency})
            endif()
        endforeach()
    endif()

    if(public_deps)
        #message(STATUS "  -> Linking PUBLIC: ${public_deps}")
        target_link_libraries(${TARGET_NAME} PUBLIC ${public_deps})
    endif()
    if(private_deps)
        #message(STATUS "  -> Linking PRIVATE: ${private_deps}")
        target_link_libraries(${TARGET_NAME} PRIVATE ${private_deps})
    endif()
    if(interface_deps)
        #message(STATUS "  -> Linking INTERFACE: ${interface_deps}")
        target_link_libraries(${TARGET_NAME} INTERFACE ${interface_deps})
    endif()
endfunction()