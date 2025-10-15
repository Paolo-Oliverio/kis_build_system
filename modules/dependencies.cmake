# cmake/build_system/dependencies.cmake

include(FetchContent)

# --- NEW DATA STRUCTURE ---
# We now use two types of global properties to store dependency info robustly,
# avoiding the fragile string parsing of the previous implementation.
#
# 1. KIS_DECLARED_DEPENDENCY_NAMES: A simple list of all dependency names
#    that have been requested by any package (e.g., "doctest;spdlog;fmt").
#
# 2. KIS_ARGS_<name>: A separate property for EACH dependency that stores its
#    FetchContent arguments as a proper CMake list (e.g., KIS_ARGS_doctest
#    will hold "GIT_REPOSITORY;https://...;GIT_TAG;...").
#
# 3. KIS_PENDING_LINKS_<target>: For each target, stores the linking commands
#    that need to be executed in Phase 2 after all targets are created.

# ==============================================================================
#           FIRST-PARTY DEPENDENCY HANDLING
# ==============================================================================

#
# kis_handle_first_party_dependencies()
#
# This function reads PACKAGE_DEPENDENCIES from kis.package.cmake and handles
# them appropriately based on the build mode:
#
# SUPERBUILD MODE:
#   - Dependencies are expected to be in kis_packages/ directory
#   - They will be discovered and configured by the superbuild
#   - This function does nothing in superbuild mode (deps handled by discovery)
#
# STANDALONE MODE:
#   - Dependencies are fetched from their remote locations
#   - Each dependency is made available via FetchContent
#
# Expected format in PACKAGE_DEPENDENCIES:
#   "name;git_url;git_tag"
#   When set() parses this, it becomes: name git_url git_tag (three list items)
#
function(kis_handle_first_party_dependencies)
    if(NOT DEFINED PACKAGE_DEPENDENCIES)
        return()
    endif()

    if(BUILDING_WITH_SUPERBUILD)
        # In superbuild mode, first-party deps are handled by discovery.cmake
        # The packages should already be present in kis_packages/ or will be
        # cloned there by kis_resolve_and_sync_packages()
        message(STATUS "[${PACKAGE_NAME}] First-party dependencies will be resolved by superbuild")
        return()
    endif()

    # STANDALONE MODE: Fetch first-party dependencies
    message(STATUS "[${PACKAGE_NAME}] Handling first-party dependencies in standalone mode")
    
    list(LENGTH PACKAGE_DEPENDENCIES num_deps)
    if(num_deps EQUAL 0)
        return()
    endif()

    # Process dependencies - they're already split into list items by CMake
    # Format after set(): name url tag name url tag ...
    set(i 0)
    while(i LESS num_deps)
        list(GET PACKAGE_DEPENDENCIES ${i} dep_name)
        math(EXPR i "${i} + 1")
        
        # Check if we have URL and TAG
        set(dep_url "")
        set(dep_tag "")
        
        if(i LESS num_deps)
            list(GET PACKAGE_DEPENDENCIES ${i} potential_url)
            if(potential_url MATCHES "^https?://")
                set(dep_url ${potential_url})
                math(EXPR i "${i} + 1")
                
                if(i LESS num_deps)
                    list(GET PACKAGE_DEPENDENCIES ${i} dep_tag)
                    math(EXPR i "${i} + 1")
                endif()
            endif()
        endif()

        if(NOT dep_url OR NOT dep_tag)
            kis_message_fatal_actionable(
                "Malformed PACKAGE_DEPENDENCIES in ${PACKAGE_NAME}"
                "Package: ${dep_name}\n  Problem: Missing URL or TAG"
                "Use correct format in kis.package.cmake:\n     set(PACKAGE_DEPENDENCIES\n         \"${dep_name};https://github.com/your-org/${dep_name}.git;main\"\n     )\n  \n  Format: \"name;git_url;git_tag\" (semicolons separate the three parts)"
            )
        endif()

        message(STATUS "  -> Fetching first-party dependency: ${dep_name} from ${dep_url}@${dep_tag}")
        
        # Use FetchContent to get the dependency
        FetchContent_Declare(
            ${dep_name}
            GIT_REPOSITORY ${dep_url}
            GIT_TAG ${dep_tag}
        )
        FetchContent_MakeAvailable(${dep_name})
    endwhile()
endfunction()

if(BUILDING_WITH_SUPERBUILD)
    # ==========================================================================
    # SUPERBUILD VERSION of kis_handle_dependency
    # ==========================================================================
    function(kis_handle_dependency NAME)
        # Parse args to find GIT_TAG and create version-aware cache paths
        set(options)
        set(oneValueArgs GIT_TAG)
        set(multiValueArgs)
        cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

        # Check for version conflicts
        get_property(existing_version GLOBAL PROPERTY KIS_DEP_VERSION_${NAME})
        if(existing_version AND ARG_GIT_TAG AND NOT existing_version STREQUAL ARG_GIT_TAG)
            kis_message_warning_actionable(
                "Version Conflict Detected"
                "Dependency: ${NAME}\n  Previously declared: ${existing_version}\n  Now requesting: ${ARG_GIT_TAG}\n  \n  Resolution: Using ${ARG_GIT_TAG} (later declaration wins)"
                "Consider standardizing versions across packages or using a dependency lock file"
            )
        endif()
        
        # Store the version for conflict detection
        if(ARG_GIT_TAG)
            set_property(GLOBAL PROPERTY KIS_DEP_VERSION_${NAME} ${ARG_GIT_TAG})
        endif()

        # Track that this package uses this third-party dependency
        # This allows the package config to include find_dependency() calls
        if(PACKAGE_NAME)
            set_property(GLOBAL APPEND PROPERTY KIS_PACKAGE_${PACKAGE_NAME}_THIRD_PARTY_DEPS ${NAME})
        endif()

        set(FETCHCONTENT_ARGS ${ARG_UNPARSED_ARGUMENTS})
        set(VERSION_SUFFIX "")
        if(ARG_GIT_TAG)
            string(REPLACE "." "_" SAFE_VERSION ${ARG_GIT_TAG})
            string(REGEX REPLACE "^v" "" SAFE_VERSION ${SAFE_VERSION})
            string(REPLACE "/" "_" SAFE_VERSION ${SAFE_VERSION})
            set(VERSION_SUFFIX "-v${SAFE_VERSION}")
            list(APPEND FETCHCONTENT_ARGS GIT_TAG ${ARG_GIT_TAG})
        endif()

        set(FETCHCONTENT_SOURCE_DIR_OVERRIDE
            "${FETCHCONTENT_BASE_DIR}/${NAME}${VERSION_SUFFIX}-src"
        )
        list(APPEND FETCHCONTENT_ARGS SOURCE_DIR ${FETCHCONTENT_SOURCE_DIR_OVERRIDE})

        # Register the dependency using the new, robust method.
        set_property(GLOBAL APPEND PROPERTY KIS_DECLARED_DEPENDENCY_NAMES ${NAME})
        set_property(GLOBAL PROPERTY KIS_ARGS_${NAME} ${FETCHCONTENT_ARGS})
    endfunction()

else()
    # ==========================================================================
    # STANDALONE VERSION of kis_handle_dependency (unchanged)
    # ==========================================================================
    function(kis_handle_dependency NAME)
        message(STATUS "Standalone handling dependency: ${NAME}")
        FetchContent_Declare(${NAME} ${ARGN})
        FetchContent_MakeAvailable(${NAME})
    endfunction()

endif()


#
# kis_populate_declared_dependencies()
#
# SUPERBUILD ONLY: Iterates the new data structure, declares all dependencies,
# and makes them available globally.
#
# IMPORTANT: Third-party libraries are compiled ONLY in plain Debug/Release configurations,
# NOT with variant-specific settings (profiling, asan, etc.). This is because:
# 1. Third-party libraries are pre-built artifacts that don't change with SDK variants
# 2. Variants like "profiling" are ABI-compatible with "release" (both use CMAKE_BUILD_TYPE=Release)
# 3. Compiling the same library multiple times wastes build time and disk space
#
# STRATEGY:
# - If current variant is plain "release" or "debug" → Build third-party deps normally
# - If current variant is anything else (profiling, asan, custom) → Skip build, reuse existing
#
function(kis_populate_declared_dependencies)
    get_property(dep_names GLOBAL PROPERTY KIS_DECLARED_DEPENDENCY_NAMES)
    if(NOT dep_names)
        return()
    endif()

    # De-duplicate the list of names. This is crucial.
    list(REMOVE_DUPLICATES dep_names)

    # Determine current variant
    kis_get_current_variant_name(current_variant)
    
    # Check if we should actually build third-party dependencies
    # Only build for plain "release" and "debug" variants
    set(should_build_third_party FALSE)
    if(current_variant STREQUAL "release" OR current_variant STREQUAL "debug")
        set(should_build_third_party TRUE)
        message(STATUS "Building third-party dependencies for '${current_variant}' variant")
    else()
        message(STATUS "Skipping third-party dependency builds for '${current_variant}' variant")
        message(STATUS "  -> Will reuse existing builds from base variant (ABI group: ${KIS_CURRENT_VARIANT_ABI_GROUP})")
    endif()

    if(should_build_third_party)
        # Use incremental dependency fetching if enabled
        if(KIS_ENABLE_INCREMENTAL_DEPENDENCIES)
            message(STATUS "Superbuild processing dependencies (incremental mode): ${dep_names}")
            kis_fetch_content_make_available_incremental("${dep_names}")
        else()
            # Traditional approach - always fetch/build everything
            foreach(dep_name ${dep_names})
                get_property(dep_args GLOBAL PROPERTY KIS_ARGS_${dep_name})
                message(STATUS "Superbuild is declaring dependency: ${dep_name}")
                FetchContent_Declare(${dep_name} ${dep_args})
            endforeach()

            message(STATUS "Superbuild making all dependencies available: ${dep_names}")
            FetchContent_MakeAvailable(${dep_names})
        endif()
    else()
        # For variant builds (profiling, asan, custom), we need to make the targets
        # available WITHOUT rebuilding. The targets were already built by the base
        # variant (release or debug).
        
        # Determine which base variant to use based on ABI group
        if(KIS_CURRENT_VARIANT_ABI_GROUP STREQUAL "RELEASE")
            set(base_binary_dir "${CMAKE_BINARY_DIR}/../release/_deps")
            set(base_variant "release")
        else()
            set(base_binary_dir "${CMAKE_BINARY_DIR}/../debug/_deps")
            set(base_variant "debug")
        endif()
        
        message(STATUS "Looking for pre-built third-party dependencies in ${base_variant} build...")
        
        foreach(dep_name ${dep_names})
            get_property(dep_args GLOBAL PROPERTY KIS_ARGS_${dep_name})
            
            # Extract SOURCE_DIR from dep_args
            list(FIND dep_args "SOURCE_DIR" source_dir_idx)
            if(source_dir_idx GREATER -1)
                math(EXPR value_idx "${source_dir_idx} + 1")
                list(GET dep_args ${value_idx} source_dir)
            else()
                # Fallback to default FetchContent location
                set(source_dir "${FETCHCONTENT_BASE_DIR}/${dep_name}-src")
            endif()
            
            # Check if the dependency was already built in the base variant
            set(base_build_dir "${base_binary_dir}/${dep_name}-build")
            set(base_source_dir_from_cache "${FETCHCONTENT_BASE_DIR}/${dep_name}-src")
            
            # Check if this is a header-only library (source exists but no build dir)
            set(is_header_only FALSE)
            if(NOT EXISTS "${base_build_dir}" AND EXISTS "${base_source_dir_from_cache}")
                set(is_header_only TRUE)
            endif()
            
            if(EXISTS "${base_build_dir}" OR is_header_only)
                if(is_header_only)
                    message(STATUS "  -> Reusing ${dep_name} from ${base_variant} (header-only)")
                else()
                    message(STATUS "  -> Reusing ${dep_name} from ${base_variant} build")
                endif()
                
                # Declare with SOURCE_DIR but don't populate
                FetchContent_Declare(${dep_name} ${dep_args})
                
                # Manually populate the properties to mark it as available
                FetchContent_GetProperties(${dep_name})
                if(NOT ${dep_name}_POPULATED)
                    if(is_header_only)
                        # For header-only libraries, just set source dir and let CMake include it
                        set(${dep_name}_SOURCE_DIR "${base_source_dir_from_cache}")
                        set(${dep_name}_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/_deps/${dep_name}-build")
                        
                        # Include the library's CMakeLists.txt to define its interface targets
                        add_subdirectory("${base_source_dir_from_cache}" "${${dep_name}_BINARY_DIR}" EXCLUDE_FROM_ALL)
                    else()
                        # For compiled libraries, load the targets from the base build directory
                        # WITHOUT recompiling. We need to import the pre-built libraries.
                        set(${dep_name}_BINARY_DIR "${base_build_dir}")
                        set(${dep_name}_SOURCE_DIR "${source_dir}")
                        
                        # CRITICAL: Do NOT call add_subdirectory as it will trigger a rebuild!
                        # Instead, try to find and load the exported CMake config or manually import targets
                        set(config_loaded FALSE)
                        
                        if(EXISTS "${base_build_dir}/${dep_name}Config.cmake")
                            include("${base_build_dir}/${dep_name}Config.cmake")
                            set(config_loaded TRUE)
                        elseif(EXISTS "${base_build_dir}/${dep_name}-config.cmake")
                            include("${base_build_dir}/${dep_name}-config.cmake")
                            set(config_loaded TRUE)
                        elseif(EXISTS "${base_build_dir}/cmake/${dep_name}Config.cmake")
                            include("${base_build_dir}/cmake/${dep_name}Config.cmake")
                            set(config_loaded TRUE)
                        endif()
                        
                        if(NOT config_loaded)
                            # Fallback: Try to import the built library manually
                            # Look for the library file in the base build directory
                            message(STATUS "    No config file found, attempting manual import...")
                            
                            # Use unified utility to find library files
                            kis_glob_library_files("${base_build_dir}" lib_files)
                            
                            if(lib_files)
                                # Create an imported target
                                if(NOT TARGET ${dep_name})
                                    add_library(${dep_name} STATIC IMPORTED GLOBAL)
                                    list(GET lib_files 0 first_lib_file)
                                    set_target_properties(${dep_name} PROPERTIES
                                        IMPORTED_LOCATION "${first_lib_file}"
                                    )
                                    
                                    # Try to find include directories
                                    if(EXISTS "${source_dir}/include")
                                        target_include_directories(${dep_name} INTERFACE "${source_dir}/include")
                                    endif()
                                    
                                    message(STATUS "    Created imported target: ${dep_name} -> ${first_lib_file}")
                                endif()
                            else()
                                kis_collect_warning("Could not find library files for ${dep_name} in ${base_build_dir} - falling back to add_subdirectory (may cause rebuild)")
                                add_subdirectory("${source_dir}" "${base_build_dir}" EXCLUDE_FROM_ALL)
                            endif()
                        endif()
                    endif()
                    
                    set(${dep_name}_POPULATED TRUE)
                endif()
            else()
                kis_collect_warning("Third-party dependency '${dep_name}' not found in ${base_variant} build! Expected: ${base_build_dir}")
                message(FATAL_ERROR "Missing third-party dependency '${dep_name}'. Please build the '${base_variant}' variant first before building '${current_variant}'")
            endif()
        endforeach()
    endif()
endfunction()

# ==============================================================================
#           PHASE 2: DEPENDENCY LINKING AND OVERRIDES
# ==============================================================================
# This section handles linking package targets to dependency targets,
# applying any user-defined overrides.
#
# IMPORTANT: The linking system now uses a two-phase approach:
#   PHASE 1: Targets are created and configured (in CMakeLists.txt)
#   PHASE 2: Links are established (deferred via kis_defer_link_dependencies)
#
# This ensures all targets exist before any linking occurs, avoiding
# "target not found" errors in complex dependency graphs.

#
# _kis_get_override_map
#
# Internal helper to parse the KIS_DEPENDENCY_OVERRIDES variable and populate
# a set of local variables (map_keys and map_values) for the caller.
# Now delegates to the centralized kis_build_override_map_parse in utils.cmake.
#
function(_kis_get_override_map)
    kis_build_override_map_parse(map_keys map_values)
    set(map_keys ${map_keys} PARENT_SCOPE)
    set(map_values ${map_values} PARENT_SCOPE)
endfunction()


#
# kis_defer_link_dependencies
#
# Registers dependency links to be executed later in Phase 2.
# This function should be called during package configuration (Phase 1).
# The actual linking happens when kis_execute_deferred_links() is called.
#
# This ensures all targets are created before any linking occurs.
#
function(kis_defer_link_dependencies)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs PUBLIC PRIVATE INTERFACE)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_TARGET)
        message(FATAL_ERROR "kis_defer_link_dependencies requires a TARGET argument.")
    endif()

    # Store the linking commands for this target
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
        set_property(GLOBAL APPEND PROPERTY KIS_PENDING_LINKS_${ARG_TARGET} ${link_data})
        message(STATUS "[PHASE 1] Deferred linking for target '${ARG_TARGET}'")
    endif()
endfunction()


#
# kis_execute_deferred_links
#
# Executes all deferred linking commands for a specific target.
# This is called in Phase 2 after all targets have been created.
#
function(kis_execute_deferred_links TARGET_NAME)
    get_property(link_data GLOBAL PROPERTY KIS_PENDING_LINKS_${TARGET_NAME})
    
    if(NOT link_data)
        return()
    endif()

    if(NOT TARGET ${TARGET_NAME})
        message(FATAL_ERROR "Cannot execute deferred links: target '${TARGET_NAME}' does not exist!")
    endif()

    message(STATUS "[Deferred linking] Executing for target '${TARGET_NAME}'")

    # Get override map
    if(BUILDING_WITH_SUPERBUILD)
        get_property(override_keys GLOBAL PROPERTY KIS_OVERRIDE_MAP_KEYS)
        get_property(override_values GLOBAL PROPERTY KIS_OVERRIDE_MAP_VALUES)
    else()
        _kis_get_override_map()
        set(override_keys ${map_keys})
        set(override_values ${map_values})
    endif()

    # Parse the stored link data
    set(visibility "")
    set(resolved_deps "")
    
    foreach(item ${link_data})
        if(item STREQUAL "PUBLIC" OR item STREQUAL "PRIVATE" OR item STREQUAL "INTERFACE")
            # Execute any pending links before switching visibility
            if(visibility AND resolved_deps)
                target_link_libraries(${TARGET_NAME} ${visibility} ${resolved_deps})
                message(STATUS "  -> Linked ${visibility}: ${resolved_deps}")
                set(resolved_deps "")
            endif()
            set(visibility ${item})
        else()
            # Resolve overrides
            list(FIND override_keys "${item}" index)
            if(index GREATER -1)
                list(GET override_values ${index} resolved_dep)
                message(STATUS "  -> Override '${item}' with '${resolved_dep}'")
                list(APPEND resolved_deps ${resolved_dep})
            else()
                list(APPEND resolved_deps ${item})
            endif()
        endif()
    endforeach()

    # Execute final batch
    if(visibility AND resolved_deps)
        target_link_libraries(${TARGET_NAME} ${visibility} ${resolved_deps})
        message(STATUS "  -> Linked ${visibility}: ${resolved_deps}")
    endif()
endfunction()


#
# kis_link_dependencies
#
# Legacy immediate linking function. In superbuild mode, this defers the link.
# In standalone mode, it links immediately (for backward compatibility).
#
# RECOMMENDED: Use kis_defer_link_dependencies explicitly in package CMakeLists.txt
# to make the intent clear.
#
function(kis_link_dependencies)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs PUBLIC PRIVATE INTERFACE)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_TARGET)
        message(FATAL_ERROR "kis_link_dependencies requires a TARGET argument.")
    endif()
    
    # In superbuild mode, always defer linking to Phase 2
    if(BUILDING_WITH_SUPERBUILD)
        kis_defer_link_dependencies(
            TARGET ${ARG_TARGET}
            PUBLIC ${ARG_PUBLIC}
            PRIVATE ${ARG_PRIVATE}
            INTERFACE ${ARG_INTERFACE}
        )
        return()
    endif()

    # In standalone mode, link immediately for backward compatibility
    # In a superbuild, the map is pre-computed and stored globally for efficiency.
    # In standalone, we compute it on the fly.
    _kis_get_override_map()
    set(override_keys ${map_keys})
    set(override_values ${map_values})

    # --- Resolve PUBLIC dependencies ---
    set(resolved_public_deps "")
    foreach(dep ${ARG_PUBLIC})
        list(FIND override_keys "${dep}" index)
        if(index GREATER -1)
            list(GET override_values ${index} resolved_dep)
            message(STATUS "Overriding dependency '${dep}' with '${resolved_dep}' for target ${ARG_TARGET}")
            list(APPEND resolved_public_deps ${resolved_dep})
        else()
            list(APPEND resolved_public_deps ${dep})
        endif()
    endforeach()

    # --- Resolve PRIVATE dependencies ---
    set(resolved_private_deps "")
    foreach(dep ${ARG_PRIVATE})
        list(FIND override_keys "${dep}" index)
        if(index GREATER -1)
            list(GET override_values ${index} resolved_dep)
            message(STATUS "Overriding dependency '${dep}' with '${resolved_dep}' for target ${ARG_TARGET}")
            list(APPEND resolved_private_deps ${resolved_dep})
        else()
            list(APPEND resolved_private_deps ${dep})
        endif()
    endforeach()

    # --- Resolve INTERFACE dependencies ---
    set(resolved_interface_deps "")
    foreach(dep ${ARG_INTERFACE})
        list(FIND override_keys "${dep}" index)
        if(index GREATER -1)
            list(GET override_values ${index} resolved_dep)
            message(STATUS "Overriding dependency '${dep}' with '${resolved_dep}' for target ${ARG_TARGET}")
            list(APPEND resolved_interface_deps ${resolved_dep})
        else()
            list(APPEND resolved_interface_deps ${dep})
        endif()
    endforeach()

    # --- Record in dependency graph (if enabled) ---
    foreach(dep ${resolved_public_deps} ${resolved_private_deps} ${resolved_interface_deps})
        # Determine if this is a first-party or third-party dependency
        set(edge_type "first-party")
        get_property(third_party_deps GLOBAL PROPERTY KIS_DECLARED_DEPENDENCY_NAMES)
        if("${dep}" IN_LIST third_party_deps)
            set(edge_type "third-party")
        endif()
        kis_graph_add_edge("${ARG_TARGET}" "${dep}" "${edge_type}")
    endforeach()
    
    # --- Call the real link command ---
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