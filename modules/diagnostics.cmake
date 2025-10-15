# kis_build_system/modules/diagnostics.cmake
# Diagnostic and troubleshooting utilities

#
# kis_validate_environment()
#
# Validates that all required tools and settings are correct before build.
# Call this early in the superbuild to catch issues upfront.
#
function(kis_validate_environment)
    set(has_errors FALSE)
    
    message(STATUS "Validating build environment...")
    list(APPEND CMAKE_MESSAGE_INDENT "  ")
    
    # Check Git availability
    find_package(Git QUIET)
    if(NOT Git_FOUND)
        if(KIS_SDK_RESOLVE_PACKAGES)
            message(SEND_ERROR 
                "[ERROR] Git is required for KIS_SDK_RESOLVE_PACKAGES=ON\n"
                "   Install Git or set -DKIS_SDK_RESOLVE_PACKAGES=OFF"
            )
            set(has_errors TRUE)
        else()
            message(STATUS "[WARNING] Git not found (not needed with KIS_SDK_RESOLVE_PACKAGES=OFF)")
        endif()
    else()
        message(STATUS "[OK] Git found: ${GIT_EXECUTABLE}")
    endif()
    
    # Check CMake version vs features
    if(CMAKE_VERSION VERSION_LESS "3.20")
        message(SEND_ERROR "[ERROR] CMake 3.20+ required, found ${CMAKE_VERSION}")
        set(has_errors TRUE)
    else()
        message(STATUS "[OK] CMake version: ${CMAKE_VERSION}")
    endif()
    
    # Check compiler
    if(CMAKE_CXX_COMPILER)
        message(STATUS "[OK] C++ Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
    else()
        message(SEND_ERROR "[ERROR] No C++ compiler found")
        set(has_errors TRUE)
    endif()
    
    # Validate platform detection
    if(NOT DEFINED KIS_PLATFORM_TAGS)
        kis_collect_warning("KIS_PLATFORM_TAGS not set - platform detection may have failed")
    else()
        message(STATUS "[OK] Platform tags: ${KIS_PLATFORM_TAGS}")
    endif()
    
    # Check for ninja if specified
    if(CMAKE_GENERATOR MATCHES "Ninja")
        find_program(NINJA_EXECUTABLE ninja)
        if(NOT NINJA_EXECUTABLE)
            kis_collect_warning("Ninja generator specified but ninja not found in PATH")
        else()
            message(STATUS "[OK] Ninja found: ${NINJA_EXECUTABLE}")
        endif()
    endif()
    
    list(POP_BACK CMAKE_MESSAGE_INDENT)
    
    if(has_errors)
        message(FATAL_ERROR 
            "[ERROR] Environment validation failed!\n"
            "   See errors above. Fix them and reconfigure."
        )
    else()
        message(STATUS "[OK] Environment validation passed")
    endif()
endfunction()


#
# kis_print_dependency_summary()
#
# Prints a summary of all resolved dependencies for diagnostic purposes.
#
function(kis_print_dependency_summary)
    message(STATUS "\n=== Dependency Summary ===")
    
    # Third-party dependencies
    get_property(third_party_deps GLOBAL PROPERTY KIS_DECLARED_DEPENDENCY_NAMES)
    if(third_party_deps)
        list(REMOVE_DUPLICATES third_party_deps)
        message(STATUS "\nThird-Party Dependencies (${CMAKE_CURRENT_LIST_LENGTH third_party_deps}):")
        foreach(dep ${third_party_deps})
            get_property(dep_version GLOBAL PROPERTY KIS_DEP_VERSION_${dep})
            if(dep_version)
                message(STATUS "  • ${dep} @ ${dep_version}")
            else()
                message(STATUS "  • ${dep}")
            endif()
        endforeach()
    endif()
    
    # Package count
    message(STATUS "\nFirst-Party Packages: ${SDK_PACKAGES}")
    
    message(STATUS "========================\n")
endfunction()


#
# kis_dump_cache_variables()
#
# Dumps all KIS_* cache variables for debugging.
#
function(kis_dump_cache_variables)
    message(STATUS "\n=== KIS Cache Variables ===")
    
    get_cmake_property(cache_vars CACHE_VARIABLES)
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_")
            message(STATUS "${var} = ${${var}}")
        endif()
    endforeach()
    
    message(STATUS "===========================\n")
endfunction()


#
# kis_check_cache_staleness()
#
# Checks if cache might have stale values by comparing to current file.
# Warns if sdk_options.cmake was modified after last configure.
#
function(kis_check_cache_staleness)
    set(options_file "${CMAKE_CURRENT_SOURCE_DIR}/kis_build_system/modules/sdk_options.cmake")
    set(cache_file "${CMAKE_BINARY_DIR}/CMakeCache.txt")
    
    if(EXISTS "${options_file}" AND EXISTS "${cache_file}")
        file(TIMESTAMP "${options_file}" options_time)
        file(TIMESTAMP "${cache_file}" cache_time)
        
        if(options_time GREATER cache_time)
            kis_collect_warning("Cache Staleness: sdk_options.cmake modified after last configure. Recommend clean build: rm -rf build/ && cmake --preset sdk-base")
        endif()
    endif()
endfunction()
