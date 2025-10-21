# cmake/build_system/dependency_linking.cmake
#
# Implements the two-phase linking system.

# ==============================================================================
#           PHASE 2: DEPENDENCY LINKING AND OVERRIDES
# ==============================================================================
function(_kis_get_override_map)
    # This internal helper now reads directly from the state module
    kis_state_get_override_map(map_keys map_values)
    set(map_keys ${map_keys} PARENT_SCOPE)
    set(map_values ${map_values} PARENT_SCOPE)
endfunction()

function(kis_defer_link_dependencies)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs PUBLIC PRIVATE INTERFACE)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_TARGET)
        message(FATAL_ERROR "kis_defer_link_dependencies requires a TARGET argument.")
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
        # Use a CACHE variable to scope state to the build directory
        set(cache_var "_KIS_CTX_PENDING_LINKS_${ARG_TARGET}")
        set(${cache_var} "${${cache_var}};${link_data}" CACHE INTERNAL "Deferred link data" FORCE)
        kis_message_verbose("[PHASE 1] Deferred linking for target '${ARG_TARGET}'")
    endif()
endfunction()

function(kis_execute_deferred_links TARGET_NAME)
    set(cache_var "_KIS_CTX_PENDING_LINKS_${TARGET_NAME}")
    
    # Check CACHE directly instead of using get_property
    if(NOT DEFINED CACHE{${cache_var}})
        return()
    endif()
    set(link_data ${${cache_var}})

    if(NOT TARGET ${TARGET_NAME})
        message(FATAL_ERROR "Cannot execute deferred links: target '${TARGET_NAME}' does not exist!")
    endif()

    message(STATUS "[PHASE 2] Linking dependencies for target '${TARGET_NAME}'")

    # Get override map from the state module
    kis_state_get_override_map(override_keys override_values)

    set(visibility "")
    set(resolved_deps "")
    
    foreach(item ${link_data})
        if(item STREQUAL "PUBLIC" OR item STREQUAL "PRIVATE" OR item STREQUAL "INTERFACE")
            if(visibility AND resolved_deps)
                target_link_libraries(${TARGET_NAME} ${visibility} ${resolved_deps})
                kis_message_verbose("  -> Linked ${visibility}: ${resolved_deps}")
                set(resolved_deps "")
            endif()
            set(visibility ${item})
        else()
            list(FIND override_keys "${item}" index)
            if(index GREATER -1)
                list(GET override_values ${index} resolved_dep)
                kis_message_verbose("  -> Override '${item}' with '${resolved_dep}'")
                list(APPEND resolved_deps ${resolved_dep})
            else()
                list(APPEND resolved_deps ${item})
            endif()
        endif()
    endforeach()

    if(visibility AND resolved_deps)
        target_link_libraries(${TARGET_NAME} ${visibility} ${resolved_deps})
        kis_message_verbose("  -> Linked ${visibility}: ${resolved_deps}")
    endif()
endfunction()

function(kis_link_dependencies)
    message(DEPRECATION "[kis_build_system] The function 'kis_link_dependencies' is deprecated. "
        "Please use 'kis_defer_link_dependencies' instead.")
        
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs PUBLIC PRIVATE INTERFACE)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_TARGET)
        message(FATAL_ERROR "kis_link_dependencies requires a TARGET argument.")
    endif()
    
    if(BUILDING_WITH_SUPERBUILD)
        kis_defer_link_dependencies(
            TARGET ${ARG_TARGET}
            PUBLIC ${ARG_PUBLIC}
            PRIVATE ${ARG_PRIVATE}
            INTERFACE ${ARG_INTERFACE}
        )
        return()
    endif()

    _kis_get_override_map()
    set(override_keys ${map_keys})
    set(override_values ${map_values})

    set(resolved_public_deps "")
    foreach(dep ${ARG_PUBLIC})
        list(FIND override_keys "${dep}" index)
        if(index GREATER -1)
            list(GET override_values ${index} resolved_dep)
            list(APPEND resolved_public_deps ${resolved_dep})
        else()
            list(APPEND resolved_public_deps ${dep})
        endif()
    endforeach()

    set(resolved_private_deps "")
    foreach(dep ${ARG_PRIVATE})
        list(FIND override_keys "${dep}" index)
        if(index GREATER -1)
            list(GET override_values ${index} resolved_dep)
            list(APPEND resolved_private_deps ${resolved_dep})
        else()
            list(APPEND resolved_private_deps ${dep})
        endif()
    endforeach()

    set(resolved_interface_deps "")
    foreach(dep ${ARG_INTERFACE})
        list(FIND override_keys "${dep}" index)
        if(index GREATER -1)
            list(GET override_values ${index} resolved_dep)
            list(APPEND resolved_interface_deps ${resolved_dep})
        else()
            list(APPEND resolved_interface_deps ${dep})
        endif()
    endforeach()

    foreach(dep ${resolved_public_deps} ${resolved_private_deps} ${resolved_interface_deps})
        set(edge_type "first-party")
        # Get TPL names from the new state function
        kis_state_get_tpl_dependency_names(third_party_deps)
        if("${dep}" IN_LIST third_party_deps)
            set(edge_type "third-party")
        endif()
        kis_graph_add_edge("${ARG_TARGET}" "${dep}" "${edge_type}")
    endforeach()
    
    if(resolved_public_deps)
        target_link_libraries(${ARG_TARGET} PUBLIC ${resolved_public_deps})
    endif()
    if(resolved_private_deps)
        target_link_libraries(${ARG_TARGET} PRIVATE ${resolved_private_deps})
    endif()
    if(resolved_interface_deps)
        target_link_libraries(${ARG_TARGET} INTERFACE ${resolved_interface_deps})
    endif()
endfunction()