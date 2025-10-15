# kis_build_system/modules/file_utils.cmake
#
# Provides unified file globbing utilities for the KIS build system.
# Centralizes file discovery patterns and handling to reduce duplication.

# ==============================================================================
#           PACKAGE DISCOVERY UTILITIES
# ==============================================================================

#
# kis_glob_package_directories
#
# Discovers package directories in a given root path. A valid package directory
# must contain a CMakeLists.txt file.
#
# Usage:
#   kis_glob_package_directories(<root_path> <out_packages_var>)
#
# Arguments:
#   root_path         : Directory to search for packages
#   out_packages_var  : Output variable name (will contain list of full paths)
#
# Example:
#   kis_glob_package_directories("${CMAKE_SOURCE_DIR}/kis_packages" discovered_packages)
#
function(kis_glob_package_directories root_path out_packages_var)
    if(NOT IS_DIRECTORY "${root_path}")
        set(${out_packages_var} "" PARENT_SCOPE)
        return()
    endif()
    
    file(GLOB discovered_dirs
        LIST_DIRECTORIES true
        RELATIVE "${root_path}"
        CONFIGURE_DEPENDS # Re-run configure if directories are added/removed
        "${root_path}/*"
    )
    
    set(valid_packages "")
    foreach(pkg_dir ${discovered_dirs})
        set(full_path "${root_path}/${pkg_dir}")
        if(EXISTS "${full_path}/CMakeLists.txt")
            list(APPEND valid_packages "${full_path}")
        endif()
    endforeach()
    
    set(${out_packages_var} ${valid_packages} PARENT_SCOPE)
endfunction()

#
# kis_glob_package_manifests
#
# Recursively discovers all kis.package.cmake manifest files under a root path.
#
# Usage:
#   kis_glob_package_manifests(<root_path> <out_manifests_var>)
#
# Arguments:
#   root_path         : Directory to search (recursively)
#   out_manifests_var : Output variable name (will contain list of full paths)
#
# Example:
#   kis_glob_package_manifests("${CMAKE_SOURCE_DIR}/kis_packages" all_manifests)
#
function(kis_glob_package_manifests root_path out_manifests_var)
    if(NOT IS_DIRECTORY "${root_path}")
        set(${out_manifests_var} "" PARENT_SCOPE)
        return()
    endif()
    
    file(GLOB_RECURSE manifests 
        "${root_path}/*/kis.package.cmake"
    )
    
    set(${out_manifests_var} ${manifests} PARENT_SCOPE)
endfunction()

# ==============================================================================
#           LIBRARY FILE DISCOVERY
# ==============================================================================

#
# kis_glob_library_files
#
# Recursively discovers library files (.lib, .a, .so, .dylib) in a directory.
# Useful for finding built artifacts when CMake config files are unavailable.
#
# Usage:
#   kis_glob_library_files(<search_path> <out_libs_var>)
#
# Arguments:
#   search_path  : Directory to search (recursively)
#   out_libs_var : Output variable name (will contain list of full paths)
#
# Example:
#   kis_glob_library_files("${build_dir}" found_libraries)
#
function(kis_glob_library_files search_path out_libs_var)
    if(NOT IS_DIRECTORY "${search_path}")
        set(${out_libs_var} "" PARENT_SCOPE)
        return()
    endif()
    
    file(GLOB_RECURSE lib_files 
        "${search_path}/*.lib"
        "${search_path}/*.a"
        "${search_path}/*.so"
        "${search_path}/*.dylib"
    )
    
    set(${out_libs_var} ${lib_files} PARENT_SCOPE)
endfunction()

# ==============================================================================
#           SOURCE FILE DISCOVERY
# ==============================================================================

#
# kis_glob_platform_sources
#
# Discovers C/C++ source files in a platform-specific source directory.
# Used by kis_add_library to find platform-specific implementations.
#
# Usage:
#   kis_glob_platform_sources(<platform_src_dir> <out_sources_var>)
#
# Arguments:
#   platform_src_dir : Directory to search (non-recursive)
#   out_sources_var  : Output variable name (will contain relative paths)
#
# Example:
#   kis_glob_platform_sources("${CMAKE_CURRENT_SOURCE_DIR}/main/platform/windows/src" win_sources)
#
function(kis_glob_platform_sources platform_src_dir out_sources_var)
    if(NOT IS_DIRECTORY "${platform_src_dir}")
        set(${out_sources_var} "" PARENT_SCOPE)
        return()
    endif()
    
    file(GLOB platform_sources 
        RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" 
        "${platform_src_dir}/*.cpp" 
        "${platform_src_dir}/*.c"
    )
    
    set(${out_sources_var} ${platform_sources} PARENT_SCOPE)
endfunction()

# ==============================================================================
#           VALIDATION UTILITIES
# ==============================================================================

#
# kis_validate_directory
#
# Checks if a path exists and is a directory. Provides consistent error handling.
#
# Usage:
#   kis_validate_directory(<path> <out_is_valid_var> [ERROR_MESSAGE <msg>])
#
# Arguments:
#   path            : Path to validate
#   out_is_valid_var: Output variable (TRUE if valid, FALSE otherwise)
#   ERROR_MESSAGE   : Optional custom error message to display if invalid
#
# Example:
#   kis_validate_directory("${packages_root}" is_valid ERROR_MESSAGE "Packages directory not found")
#
function(kis_validate_directory path out_is_valid_var)
    cmake_parse_arguments(ARG "" "ERROR_MESSAGE" "" ${ARGN})
    
    set(is_valid FALSE)
    if(EXISTS "${path}" AND IS_DIRECTORY "${path}")
        set(is_valid TRUE)
    elseif(ARG_ERROR_MESSAGE)
        message(WARNING "${ARG_ERROR_MESSAGE}: ${path}")
    endif()
    
    set(${out_is_valid_var} ${is_valid} PARENT_SCOPE)
endfunction()

# ==============================================================================
#           PATH UTILITIES
# ==============================================================================

#
# kis_get_package_name_from_path
#
# Extracts the package name from a full package path or manifest path.
#
# Usage:
#   kis_get_package_name_from_path(<path> <out_name_var>)
#
# Arguments:
#   path         : Full path to package directory or manifest file
#   out_name_var : Output variable name (will contain package name)
#
# Example:
#   kis_get_package_name_from_path("/path/to/kis_packages/kis_core" pkg_name)
#   # pkg_name = "kis_core"
#
function(kis_get_package_name_from_path path out_name_var)
    # If path is a file, get its directory first
    if(NOT IS_DIRECTORY "${path}")
        get_filename_component(path "${path}" DIRECTORY)
    endif()
    
    get_filename_component(pkg_name "${path}" NAME)
    set(${out_name_var} ${pkg_name} PARENT_SCOPE)
endfunction()
