# cmake/build_system/discovery.cmake

# ------------------------------------------------------------------------------
# FUNCTION: discover_packages
# Discovers all valid packages in a given directory.
# ------------------------------------------------------------------------------
function(discover_packages group_path out_var)
    file(GLOB packages LIST_DIRECTORIES true RELATIVE "${group_path}" "${group_path}/*")

    set(found_package_paths "")
    foreach(package_dir ${packages})
        if(EXISTS "${group_path}/${package_dir}/CMakeLists.txt")
            list(APPEND found_package_paths "${group_path}/${package_dir}")
        endif()
    endforeach()

    set(${out_var} ${${out_var}} ${found_package_paths} PARENT_SCOPE)
endfunction()

# ------------------------------------------------------------------------------
# FUNCTION: configure_discovered_packages
# Calls add_subdirectory for a list of packages. It assumes CMAKE_INSTALL_PREFIX
# has already been set by the superbuild.
# ------------------------------------------------------------------------------
function(configure_discovered_packages)
    set(package_paths ${ARGN})

    foreach(package_path ${package_paths})
        get_filename_component(package_name ${package_path} NAME)
        message(STATUS "Configuring package: ${package_name}")

        set(source_dir ${package_path})
        set(binary_dir "${CMAKE_BINARY_DIR}/_deps/${package_name}-build")

        add_subdirectory(${source_dir} ${binary_dir})
    endforeach()
endfunction()

# ------------------------------------------------------------------------------
# FUNCTION: link_all_package_dependencies
# Loops through a list of all discovered packages and calls their linking function.
# ------------------------------------------------------------------------------
function(link_all_package_dependencies)
    set(all_packages ${ARGN})
    message(STATUS "\n--- PHASE 2: LINKING PACKAGE DEPENDENCIES ---")

    foreach(package_path ${all_packages})
        
        get_filename_component(package_name ${package_path} NAME)
        set(link_function_name "${package_name}_link_dependencies")
        if(COMMAND ${link_function_name})
            cmake_language(CALL ${link_function_name})
        endif()
    endforeach()
endfunction()
