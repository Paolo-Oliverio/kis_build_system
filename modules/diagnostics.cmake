# kis_build_system/modules/diagnostics.cmake
#
# Provides build environment validation, cache staleness detection,
# and collects/reports configuration warnings.

include_guard(GLOBAL)

# ==============================================================================
#           WARNING COLLECTION & SUMMARY
# ==============================================================================
function(kis_collect_warning)
    if(ARGC EQUAL 1)
        set(warning_text "${ARGV0}")
    elseif(ARGC EQUAL 3)
        set(warning_text "${ARGV0}: ${ARGV1} | Hint: ${ARGV2}")
    else()
        message(FATAL_ERROR "kis_collect_warning expects 1 or 3 arguments")
    endif()
    kis_state_add_warning("${warning_text}")
endfunction()

function(kis_print_warning_summary)
    kis_state_get_warnings(warnings count)
    if(count GREATER 0)
        message(STATUS "")
        message(STATUS "╔═══════════════════════════════════════════════════════════════════════╗")
        message(STATUS "              [WARNING] Configuration Warnings (${count})")
        message(STATUS "╚═══════════════════════════════════════════════════════════════════════╝")
        message(STATUS "")
        set(warning_num 1)
        foreach(warning ${warnings})
            message(STATUS "  ${warning_num}. ${warning}")
            math(EXPR warning_num "${warning_num} + 1")
        endforeach()
        message(STATUS "")
        message(STATUS "┌──────────────────────────────────────────────────────────────────────┐")
        message(STATUS "│ [TIP] Address these warnings to ensure optimal build configuration   │")
        message(STATUS "└──────────────────────────────────────────────────────────────────────┘")
        message(STATUS "")
    else()
        kis_message_verbose("No configuration warnings")
    endif()
endfunction()

# ==============================================================================
#           CACHE STALENESS DETECTION
# ==============================================================================
function(kis_check_cache_staleness)
    if(NOT EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt")
        return()
    endif()
    set(issues_found FALSE)
    if(DEFINED CACHE{KIS_PLATFORM_CACHED})
        if(NOT "${KIS_PLATFORM}" STREQUAL "${KIS_PLATFORM_CACHED}")
            kis_collect_warning("Cache Staleness" "Platform changed..." "Delete build dir...")
            set(issues_found TRUE)
        endif()
    else()
        set(KIS_PLATFORM_CACHED "${KIS_PLATFORM}" CACHE INTERNAL "...")
    endif()
    if(DEFINED CACHE{KIS_GENERATOR_CACHED})
        if(NOT "${CMAKE_GENERATOR}" STREQUAL "${KIS_GENERATOR_CACHED}")
            kis_collect_warning("Cache Staleness" "Generator changed..." "Delete build dir...")
            set(issues_found TRUE)
        endif()
    else()
        set(KIS_GENERATOR_CACHED "${CMAKE_GENERATOR}" CACHE INTERNAL "...")
    endif()
    if(DEFINED CACHE{KIS_SOURCE_DIR_CACHED})
        if(NOT "${CMAKE_SOURCE_DIR}" STREQUAL "${KIS_SOURCE_DIR_CACHED}")
            kis_collect_warning("Cache Staleness" "Source directory changed..." "Delete build dir...")
            set(issues_found TRUE)
        endif()
    else()
        set(KIS_SOURCE_DIR_CACHED "${CMAKE_SOURCE_DIR}" CACHE INTERNAL "...")
    endif()
    if(issues_found)
        message(STATUS "\n━━━━━━━━━━━━━━━━━━━━━━━━\n⚠️  CACHE STALENESS DETECTED\n━━━━━━━━━━━━━━━━━━━━━━━━")
    endif()
endfunction()

# ==============================================================================
#           ENVIRONMENT VALIDATION
# ==============================================================================
function(kis_validate_environment)
    if("${CMAKE_SOURCE_DIR}" STREQUAL "${CMAKE_BINARY_DIR}")
        kis_collect_warning("Environment Validation" "In-source build detected..." "Use out-of-source build...")
    endif()
    find_package(Git QUIET)
    if(NOT Git_FOUND AND KIS_SDK_RESOLVE_PACKAGES)
        message(FATAL_ERROR "[ERROR] Git is required...")
    endif()
endfunction()

# ==============================================================================
#           DIAGNOSTIC UTILITIES
# ==============================================================================
function(kis_dump_cache_variables)
    if(NOT KIS_DIAGNOSTIC_MODE) 
    return() 
    endif()
    message(STATUS "\n=== KIS Cache Variables ===")
    get_cmake_property(cache_vars CACHE_VARIABLES)
    list(SORT cache_vars)
    foreach(var ${cache_vars})
        if(var MATCHES "^KIS_")
            message(STATUS "${var} = ${${var}}")
        endif()
    endforeach()
    message(STATUS "===========================\n")
endfunction()

function(kis_print_dependency_summary)
    message(STATUS "\n=== Dependency Summary ===")
    
    kis_state_get_tpl_dependencies(third_party_deps)
    if(third_party_deps)
        list(LENGTH third_party_deps num_deps)
        message(STATUS "\nThird-Party Dependencies (${num_deps}):")
        foreach(dep_entry ${third_party_deps})
            string(REPLACE "|||" ";" dep_parts "${dep_entry}")
            list(GET dep_parts 0 dep_name)
            list(GET dep_parts 2 dep_tag) # Correct index
            
            if(dep_tag)
                message(STATUS "  • ${dep_name} @ ${dep_tag}")
            else()
                message(STATUS "  • ${dep_name}")
            endif()
        endforeach()
    endif()
    
    kis_state_get_all_package_paths(sdk_packages)
    if(sdk_packages)
        list(LENGTH sdk_packages pkg_count)
        message(STATUS "\nFirst-Party Packages: ${pkg_count}")
    endif()
    
    message(STATUS "========================\n")
endfunction()