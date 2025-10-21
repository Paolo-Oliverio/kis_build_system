# kis_build_system/modules/kis_state.cmake
#
# Manages the global state of the KIS build system.
# Provides a structured API for accessing and modifying build state.
# All state is stored in CACHE INTERNAL variables with a _KIS_CTX_ prefix.

include_guard(GLOBAL)

# ==============================================================================
#           STATE INITIALIZATION
# ==============================================================================
function(kis_state_init)
    # Warning System State
    set(_KIS_CTX_WARNINGS "" CACHE INTERNAL "List of collected configuration warnings" FORCE)
    set(_KIS_CTX_WARNING_COUNT 0 CACHE INTERNAL "Count of collected warnings" FORCE)

    # Package Discovery State
    set(_KIS_CTX_ALL_PACKAGE_PATHS "" CACHE INTERNAL "List of all discovered package paths" FORCE)
    set(_KIS_CTX_OVERRIDE_MAP_KEYS "" CACHE INTERNAL "List of package names to be overridden" FORCE)
    set(_KIS_CTX_OVERRIDE_MAP_VALUES "" CACHE INTERNAL "List of packages that perform overriding" FORCE)

    # Dependency Declaration State
    set(_KIS_CTX_DECLARED_TPL_DEPS "" CACHE INTERNAL "List of structured third-party dependencies" FORCE)
    set(_KIS_CTX_DECLARED_KIS_DEPS "" CACHE INTERNAL "List of first-party KIS dependencies (JSON)" FORCE)
    
    # Graph Visualization State
    set(_KIS_CTX_GRAPH_NODES "" CACHE INTERNAL "Nodes for dependency graph visualization" FORCE)
    set(_KIS_CTX_GRAPH_EDGES "" CACHE INTERNAL "Edges for dependency graph visualization" FORCE)

    # Installation State
    set(_KIS_CTX_SELF_INSTALLING_DEPS "" CACHE INTERNAL "List of third-party deps with their own install rules" FORCE)
    set(_KIS_CTX_THIRD_PARTY_INSTALLED_TARGETS "" CACHE INTERNAL "List of installed third-party targets" FORCE)
    
    message(STATUS "[State] KIS build state initialized in CACHE.")
endfunction()


# ==============================================================================
#           WARNING SYSTEM API
# ==============================================================================
function(kis_state_add_warning formatted_warning_message)
    # Robust append for CACHE list variables
    set(temp_list ${_KIS_CTX_WARNINGS})
    list(APPEND temp_list "${formatted_warning_message}")
    set(_KIS_CTX_WARNINGS "${temp_list}" CACHE INTERNAL "" FORCE)

    math(EXPR count "${_KIS_CTX_WARNING_COUNT} + 1")
    set(_KIS_CTX_WARNING_COUNT ${count} CACHE INTERNAL "" FORCE)
endfunction()

function(kis_state_get_warnings out_warnings_var out_count_var)
    set(${out_warnings_var} "${_KIS_CTX_WARNINGS}" PARENT_SCOPE)
    set(${out_count_var} ${_KIS_CTX_WARNING_COUNT} PARENT_SCOPE)
endfunction()


# ==============================================================================
#           PACKAGE DISCOVERY API
# ==============================================================================
function(kis_state_set_all_package_paths package_list)
    set(_KIS_CTX_ALL_PACKAGE_PATHS "${package_list}" CACHE INTERNAL "" FORCE)
endfunction()

function(kis_state_get_all_package_paths out_var)
    set(${out_var} "${_KIS_CTX_ALL_PACKAGE_PATHS}" PARENT_SCOPE)
endfunction()

function(kis_state_set_override_map keys_list values_list)
    set(_KIS_CTX_OVERRIDE_MAP_KEYS "${keys_list}" CACHE INTERNAL "" FORCE)
    set(_KIS_CTX_OVERRIDE_MAP_VALUES "${values_list}" CACHE INTERNAL "" FORCE)
endfunction()

function(kis_state_get_override_map out_keys_var out_values_var)
    set(${out_keys_var} "${_KIS_CTX_OVERRIDE_MAP_KEYS}" PARENT_SCOPE)
    set(${out_values_var} "${_KIS_CTX_OVERRIDE_MAP_VALUES}" PARENT_SCOPE)
endfunction()


# ==============================================================================
#           DEPENDENCY DECLARATION API
# ==============================================================================
function(kis_state_add_tpl_dependency dep_struct)
    set(sep "_KIS_SEP_")
    # THE FIX: Sanitize the input by replacing newlines with spaces before storing.
    string(REPLACE "\n" " " sanitized_struct "${dep_struct}")
    if(_KIS_CTX_DECLARED_TPL_DEPS)
        set(_KIS_CTX_DECLARED_TPL_DEPS "${_KIS_CTX_DECLARED_TPL_DEPS}${sep}${sanitized_struct}" CACHE INTERNAL "" FORCE)
    else()
        set(_KIS_CTX_DECLARED_TPL_DEPS "${sanitized_struct}" CACHE INTERNAL "" FORCE)
    endif()
endfunction()

function(kis_state_get_tpl_dependencies out_var)
    set(sep "_KIS_SEP_")
    string(REPLACE "${sep}" ";" temp_list "${_KIS_CTX_DECLARED_TPL_DEPS}")
    set(${out_var} "${temp_list}" PARENT_SCOPE)
endfunction()

function(kis_state_get_tpl_dependency_names out_var)
    set(names_list "")
    kis_state_get_tpl_dependencies(all_deps)
    foreach(entry ${all_deps})
        string(REPLACE "|||" ";" entry_parts "${entry}")
        list(GET entry_parts 0 entry_name)
        if(entry_name)
            list(APPEND names_list ${entry_name})
        endif()
    endforeach()
    list(REMOVE_DUPLICATES names_list)
    set(${out_var} "${names_list}" PARENT_SCOPE)
endfunction()

function(kis_state_add_kis_dependency dep_json)
    set(sep "_KIS_SEP_")
    # THE FIX: Sanitize the input by replacing newlines with spaces before storing.
    string(REPLACE "\n" " " sanitized_json "${dep_json}")
    if(_KIS_CTX_DECLARED_KIS_DEPS)
        set(_KIS_CTX_DECLARED_KIS_DEPS "${_KIS_CTX_DECLARED_KIS_DEPS}${sep}${sanitized_json}" CACHE INTERNAL "" FORCE)
    else()
        set(_KIS_CTX_DECLARED_KIS_DEPS "${sanitized_json}" CACHE INTERNAL "" FORCE)
    endif()
endfunction()

function(kis_state_get_kis_dependencies out_var)
    set(sep "_KIS_SEP_")
    string(REPLACE "${sep}" ";" temp_list "${_KIS_CTX_DECLARED_KIS_DEPS}")
    set(${out_var} "${temp_list}" PARENT_SCOPE)
endfunction()

# ==============================================================================
#           GRAPH VISUALIZATION API
# ==============================================================================
function(kis_state_add_graph_node node_data)
    set(temp_list ${_KIS_CTX_GRAPH_NODES})
    list(APPEND temp_list "${node_data}")
    set(_KIS_CTX_GRAPH_NODES "${temp_list}" CACHE INTERNAL "" FORCE)
endfunction()

function(kis_state_get_graph_nodes out_var)
    set(${out_var} "${_KIS_CTX_GRAPH_NODES}" PARENT_SCOPE)
endfunction()

function(kis_state_add_graph_edge edge_data)
    set(temp_list ${_KIS_CTX_GRAPH_EDGES})
    list(APPEND temp_list "${edge_data}")
    set(_KIS_CTX_GRAPH_EDGES "${temp_list}" CACHE INTERNAL "" FORCE)
endfunction()

function(kis_state_get_graph_edges out_var)
    set(${out_var} "${_KIS_CTX_GRAPH_EDGES}" PARENT_SCOPE)
endfunction()

# ==============================================================================
#           INSTALLATION STATE API
# ==============================================================================
function(kis_state_add_self_installing_dep dep_name)
    set(temp_list ${_KIS_CTX_SELF_INSTALLING_DEPS})
    list(APPEND temp_list "${dep_name}")
    set(_KIS_CTX_SELF_INSTALLING_DEPS "${temp_list}" CACHE INTERNAL "" FORCE)
endfunction()

function(kis_state_get_self_installing_deps out_var)
    set(${out_var} "${_KIS_CTX_SELF_INSTALLING_DEPS}" PARENT_SCOPE)
endfunction()

function(kis_state_add_third_party_installed_target target_name)
    set(temp_list ${_KIS_CTX_THIRD_PARTY_INSTALLED_TARGETS})
    list(APPEND temp_list "${target_name}")
    set(_KIS_CTX_THIRD_PARTY_INSTALLED_TARGETS "${temp_list}" CACHE INTERNAL "" FORCE)
endfunction()

function(kis_state_get_third_party_installed_targets out_var)
    set(${out_var} "${_KIS_CTX_THIRD_PARTY_INSTALLED_TARGETS}" PARENT_SCOPE)
endfunction()