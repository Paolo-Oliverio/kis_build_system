# cmake/build_system/package_discovery.cmake
#
# Provides the primary function for discovering KIS SDK packages. It scans
# the filesystem, respects platform-specific directories, and builds the
# definitive override map based on package manifests.

# ==============================================================================
#           PRIMARY DISCOVERY FUNCTION
# ==============================================================================

#
# discover_and_map_packages
#
# Discovers all packages and stores the results (package list and override map)
# in the global state module.
#
function(discover_and_map_packages)
    set(all_packages "")
    set(override_keys "")
    set(override_values "")
    set(packages_root "${CMAKE_CURRENT_SOURCE_DIR}/kis_packages")

    set(search_paths "${packages_root}")
    foreach(tag ${KIS_PLATFORM_TAGS})
        list(APPEND search_paths "${packages_root}/${tag}")
    endforeach()

    message(STATUS "Discovering packages in search paths: ${search_paths}")

    foreach(current_path ${search_paths})
        # Robustness: Skip search paths that don't actually exist.
        if(NOT IS_DIRECTORY "${current_path}")
            continue()
        endif()

        kis_glob_package_directories("${current_path}" discovered_packages)
        
        foreach(full_package_path ${discovered_packages})
            list(APPEND all_packages "${full_package_path}")
            kis_get_package_name_from_path("${full_package_path}" pkg_name)

            kis_validate_package_platform(
                "${pkg_name}"
                "${full_package_path}"
                "${KIS_PLATFORM}"
                "${KIS_ACTIVE_TAGS}"
                is_compatible
                error_message
            )
            
            if(NOT is_compatible)
                kis_message_fatal_actionable(
                    "Platform Incompatibility"
                    "${error_message}"
                    "Update the package's kis.package.json to support ${KIS_PLATFORM}"
                    PACKAGE ${pkg_name}
                    FILE "${full_package_path}/kis.package.json"
                )
            endif()

            kis_read_package_manifest_json(PACKAGE_PATH "${full_package_path}")

            if(DEFINED MANIFEST_OVERRIDES)
                foreach(overridden_pkg ${MANIFEST_OVERRIDES})
                    message(STATUS "Platform Logic: Package '${pkg_name}' declares override for '${overridden_pkg}'")

                    list(FIND override_keys "${overridden_pkg}" index)
                    if(index GREATER -1)
                        list(GET override_values ${index} old_override_pkg)
                        message(STATUS "--> Specificity win: '${pkg_name}' replaces previous override '${old_override_pkg}' for '${overridden_pkg}'.")
                        list(REMOVE_AT override_values ${index})
                        list(INSERT override_values ${index} ${pkg_name})
                    else()
                        message(STATUS "--> Registering new override for '${overridden_pkg}' -> '${pkg_name}'.")
                        list(APPEND override_keys ${overridden_pkg})
                        list(APPEND override_values ${pkg_name})
                    endif()
                endforeach()
            endif()
        endforeach()
    endforeach()

    list(REMOVE_DUPLICATES all_packages)
    
    list(LENGTH all_packages pkg_count)
    if(KIS_ENABLE_INCREMENTAL_VALIDATION)
        message(STATUS "Validating ${pkg_count} package manifests (incremental mode)...")
    else()
        message(STATUS "Validating ${pkg_count} package manifests (full validation)...")
    endif()
    foreach(pkg_path ${all_packages})
        kis_validate_package_if_needed("${pkg_path}")
    endforeach()

    # Store results in the state module instead of returning
    kis_state_set_all_package_paths("${all_packages}")
    kis_state_set_override_map("${override_keys}" "${override_values}")
endfunction()