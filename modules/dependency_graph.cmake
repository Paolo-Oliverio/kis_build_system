# kis_build_system/modules/dependency_graph.cmake
#
# Exports dependency relationships to DOT format for visualization

# Initialize graph data collection
set_property(GLOBAL PROPERTY KIS_GRAPH_NODES "")
set_property(GLOBAL PROPERTY KIS_GRAPH_EDGES "")

#
# kis_graph_add_node
#
# Records a package node in the dependency graph
#
# Usage:
#   kis_graph_add_node(package_name "type" "platform")
#
function(kis_graph_add_node node_name node_type node_platform)
    if(NOT KIS_EXPORT_DEPENDENCY_GRAPH)
        return()
    endif()
    
    get_property(nodes GLOBAL PROPERTY KIS_GRAPH_NODES)
    
    # Avoid duplicates
    if("${node_name}" IN_LIST nodes)
        return()
    endif()
    
    list(APPEND nodes "${node_name}|${node_type}|${node_platform}")
    set_property(GLOBAL PROPERTY KIS_GRAPH_NODES "${nodes}")
endfunction()

#
# kis_graph_add_edge
#
# Records a dependency edge in the graph
#
# Usage:
#   kis_graph_add_edge(from_package to_package "type")
#   where type is: "first-party", "third-party", "platform"
#
function(kis_graph_add_edge from_node to_node edge_type)
    if(NOT KIS_EXPORT_DEPENDENCY_GRAPH)
        return()
    endif()
    
    get_property(edges GLOBAL PROPERTY KIS_GRAPH_EDGES)
    
    # Avoid duplicates
    set(edge_key "${from_node}->${to_node}")
    foreach(existing_edge ${edges})
        if(existing_edge MATCHES "^${edge_key}\\|")
            return()
        endif()
    endforeach()
    
    list(APPEND edges "${edge_key}|${edge_type}")
    set_property(GLOBAL PROPERTY KIS_GRAPH_EDGES "${edges}")
endfunction()

#
# kis_export_dependency_graph
#
# Exports the collected graph to a DOT file
#
function(kis_export_dependency_graph)
    if(NOT KIS_EXPORT_DEPENDENCY_GRAPH)
        return()
    endif()
    
    get_property(nodes GLOBAL PROPERTY KIS_GRAPH_NODES)
    get_property(edges GLOBAL PROPERTY KIS_GRAPH_EDGES)
    
    set(output_file "${CMAKE_BINARY_DIR}/dependency_graph.dot")
    
    # Start DOT file
    set(dot_content "digraph KIS_Dependencies {\n")
    set(dot_content "${dot_content}    rankdir=LR;\n")
    set(dot_content "${dot_content}    node [shape=box, style=rounded];\n")
    set(dot_content "${dot_content}    \n")
    
    # Define node styles
    set(dot_content "${dot_content}    // Node styles\n")
    set(dot_content "${dot_content}    node [fillcolor=lightblue, style=\"rounded,filled\"] // First-party\n")
    set(dot_content "${dot_content}    \n")
    
    # Add nodes
    set(dot_content "${dot_content}    // Packages\n")
    foreach(node_data ${nodes})
        string(REPLACE "|" ";" node_parts "${node_data}")
        list(GET node_parts 0 node_name)
        list(GET node_parts 1 node_type)
        list(GET node_parts 2 node_platform)
        
        # Choose color based on type
        set(node_color "lightblue")
        set(node_shape "box")
        if(node_type STREQUAL "INTERFACE")
            set(node_color "lightyellow")
            set(node_shape "hexagon")
        elseif(node_type STREQUAL "EXECUTABLE")
            set(node_color "lightgreen")
            set(node_shape "component")
        elseif(node_type STREQUAL "third-party")
            set(node_color "lightgray")
            set(node_shape "box")
        endif()
        
        # Add platform label if not common
        set(label "${node_name}")
        if(NOT node_platform STREQUAL "common")
            set(label "${node_name}\\n[${node_platform}]")
        endif()
        
        set(dot_content "${dot_content}    \"${node_name}\" [label=\"${label}\", fillcolor=${node_color}, shape=${node_shape}];\n")
    endforeach()
    
    set(dot_content "${dot_content}    \n")
    
    # Add edges
    set(dot_content "${dot_content}    // Dependencies\n")
    foreach(edge_data ${edges})
        string(REPLACE "|" ";" edge_parts "${edge_data}")
        list(GET edge_parts 0 edge_key)
        list(GET edge_parts 1 edge_type)
        
        string(REPLACE "->" ";" edge_nodes "${edge_key}")
        list(GET edge_nodes 0 from_node)
        list(GET edge_nodes 1 to_node)
        
        # Choose style based on type
        set(edge_style "solid")
        set(edge_color "black")
        if(edge_type STREQUAL "third-party")
            set(edge_style "dashed")
            set(edge_color "gray")
        elseif(edge_type STREQUAL "platform")
            set(edge_style "dotted")
            set(edge_color "blue")
        endif()
        
        set(dot_content "${dot_content}    \"${from_node}\" -> \"${to_node}\" [style=${edge_style}, color=${edge_color}];\n")
    endforeach()
    
    # Close graph
    set(dot_content "${dot_content}    \n")
    set(dot_content "${dot_content}    // Legend\n")
    set(dot_content "${dot_content}    subgraph cluster_legend {\n")
    set(dot_content "${dot_content}        label=\"Legend\";\n")
    set(dot_content "${dot_content}        style=filled;\n")
    set(dot_content "${dot_content}        color=lightgray;\n")
    set(dot_content "${dot_content}        \n")
    set(dot_content "${dot_content}        legend_lib [label=\"Library\", fillcolor=lightblue, shape=box, style=\"rounded,filled\"];\n")
    set(dot_content "${dot_content}        legend_interface [label=\"Interface\", fillcolor=lightyellow, shape=hexagon, style=filled];\n")
    set(dot_content "${dot_content}        legend_exe [label=\"Executable\", fillcolor=lightgreen, shape=component, style=filled];\n")
    set(dot_content "${dot_content}        legend_third [label=\"Third-party\", fillcolor=lightgray, shape=box, style=\"rounded,filled\"];\n")
    set(dot_content "${dot_content}        \n")
    set(dot_content "${dot_content}        legend_lib -> legend_interface [label=\"first-party\", style=solid];\n")
    set(dot_content "${dot_content}        legend_lib -> legend_third [label=\"third-party\", style=dashed, color=gray];\n")
    set(dot_content "${dot_content}    }\n")
    set(dot_content "${dot_content}}\n")
    
    # Write to file
    file(WRITE "${output_file}" "${dot_content}")
    
    message(STATUS "")
    message(STATUS "========================================")
    message(STATUS "[OK] Dependency graph exported to:")
    message(STATUS "     ${output_file}")
    message(STATUS "")
    message(STATUS "[TIP] Generate visualization:")
    message(STATUS "     dot -Tpng ${output_file} -o dependency_graph.png")
    message(STATUS "     dot -Tsvg ${output_file} -o dependency_graph.svg")
    message(STATUS "")
    message(STATUS "[INFO] Install Graphviz:")
    message(STATUS "     Windows: choco install graphviz")
    message(STATUS "     macOS:   brew install graphviz")
    message(STATUS "     Linux:   apt/yum install graphviz")
    message(STATUS "========================================")
    message(STATUS "")
endfunction()
