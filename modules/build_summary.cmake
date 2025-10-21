# kis_build_system/modules/build_summary.cmake
#
# Provides functions for printing build configuration summaries

#
# kis_print_build_summary
#
# Prints a summary of what was configured in this build:
# - How many packages compiled vs imported
# - Which variants are active
# - Third-party dependencies status
#
function(kis_print_build_summary)
    set(all_packages ${ARGN})
    
    # Get current variant
    kis_get_current_variant_name(current_variant)
    kis_get_variant_abi_group("${current_variant}" current_abi_group)
    
    # Count packages
    set(compiled_count 0)
    set(imported_count 0)
    set(skipped_count 0)
    
    set(compiled_list "")
    set(imported_list "")
    
    foreach(package_path ${all_packages})
        kis_get_package_name_from_path("${package_path}" package_name)
        
        if(TARGET ${package_name})
            # Check if it's an imported target
            get_target_property(is_imported ${package_name} IMPORTED)
            if(is_imported)
                math(EXPR imported_count "${imported_count} + 1")
                list(APPEND imported_list ${package_name})
            else()
                math(EXPR compiled_count "${compiled_count} + 1")
                list(APPEND compiled_list ${package_name})
            endif()
        else()
            math(EXPR skipped_count "${skipped_count} + 1")
        endif()
    endforeach()
    
    # Get third-party dependencies from the central state
    kis_state_get_tpl_dependency_names(third_party_deps)
    if(third_party_deps)
        list(REMOVE_DUPLICATES third_party_deps)
        list(LENGTH third_party_deps third_party_count)
    else()
        set(third_party_count 0)
    endif()
    
    # Print summary
    message(STATUS "Variant:             ${current_variant} (ABI Group: ${current_abi_group})")
    message(STATUS "Platform:            ${KIS_PLATFORM}")
    message(STATUS "")
    message(STATUS "Packages:")
    message(STATUS "  Built from source: ${compiled_count}")
    
    if(KIS_VERBOSE_BUILD AND compiled_list)
        foreach(pkg ${compiled_list})
            message(STATUS "    • ${pkg}")
        endforeach()
    endif()
    
    if(imported_count GREATER 0)
        message(STATUS "  Imported:          ${imported_count} (from ${current_abi_group} base variant)")
        
        if(KIS_VERBOSE_BUILD AND imported_list)
            foreach(pkg ${imported_list})
                message(STATUS "    • ${pkg}")
            endforeach()
        endif()
    endif()
    
    if(skipped_count GREATER 0)
        message(STATUS "  Skipped:           ${skipped_count} (feature disabled)")
    endif()
    
    if(third_party_count GREATER 0)
        if(current_variant STREQUAL "release" OR current_variant STREQUAL "debug")
            message(STATUS "")
            message(STATUS "Third-party:         ${third_party_count} dependencies (building)")
        else()
            message(STATUS "")
            message(STATUS "Third-party:         ${third_party_count} dependencies (reusing from base)")
        endif()
        
        if(KIS_VERBOSE_BUILD)
            foreach(dep ${third_party_deps})
                message(STATUS "    • ${dep}")
            endforeach()
        endif()
    endif()
    
    message(STATUS "")
    message(STATUS "Build targets:")
    if(KIS_BUILD_TESTS)
        message(STATUS "  ✓ Tests enabled")
    endif()
    if(KIS_BUILD_SAMPLES)
        message(STATUS "  ✓ Samples enabled")
    endif()
    if(KIS_BUILD_BENCHMARKS)
        message(STATUS "  ✓ Benchmarks enabled")
    endif()
    
    message(STATUS "===================================")
    
    # Helpful hints
    if(imported_count GREATER 0 AND NOT KIS_VERBOSE_BUILD)
        message(STATUS "")
        message(STATUS "[TIP] Use -DKIS_VERBOSE_BUILD=ON to see detailed package lists")
    endif()
endfunction()