# kis_build_system/modules/targets.cmake

function(kis_add_library)
    # Support two call styles:
    # 1) Named: kis_add_library(TARGET <name> SOURCES <files...>)
    # 2) Positional: kis_add_library(<name> <files...>) -- easier for templates
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs SOURCES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # If TARGET wasn't provided as a named arg, allow the first positional
    # argument to act as the target name. This keeps backward compatibility
    # with existing packages while enabling the simpler call form.
    if(NOT ARG_TARGET)
        if(ARG_UNPARSED_ARGUMENTS)
            list(GET ARG_UNPARSED_ARGUMENTS 0 _pos_target)
            set(ARG_TARGET ${_pos_target})

            # Remove the positional target from the unparsed args and treat
            # the remaining as SOURCES when no explicit SOURCES were given.
            list(REMOVE_AT ARG_UNPARSED_ARGUMENTS 0)
            if(NOT ARG_SOURCES)
                set(ARG_SOURCES ${ARG_UNPARSED_ARGUMENTS})
            endif()
        else()
            message(FATAL_ERROR "kis_add_library requires a TARGET argument.")
        endif()
    endif()

    set(final_source_list "")
    # --- FIX: Point to the new, cleaner platform directory ---
    set(platform_src_base_path "${CMAKE_CURRENT_SOURCE_DIR}/main/platform")

    # Get platform tags sorted from most-specific to least-specific
    set(reversed_tags ${KIS_PLATFORM_TAGS})
    list(REVERSE reversed_tags)

    # --- Step 1: Resolve common sources, applying overrides ---
    foreach(common_source ${ARG_SOURCES})
        get_filename_component(common_filename ${common_source} NAME)
        set(override_found FALSE)

        # Check for an override in each platform tag directory, in order of specificity
        foreach(tag ${reversed_tags})
            # This path is now correct: .../main/platform/windows/src/file.cpp
            set(potential_override "${platform_src_base_path}/${tag}/src/${common_filename}")
            if(EXISTS "${potential_override}")
                message(STATUS "Source override found: '${potential_override}' replaces '${common_source}'")
                list(APPEND final_source_list "${potential_override}")
                set(override_found TRUE)
                break()
            endif()
        endforeach()

        if(NOT override_found)
            list(APPEND final_source_list "${common_source}")
        endif()
    endforeach()

    # --- Step 2: Add purely platform-specific sources (no common equivalent) ---
    foreach(tag ${reversed_tags})
        # This path is also now correct: .../main/platform/windows/src/
        set(platform_src_dir "${platform_src_base_path}/${tag}/src")
        # Use unified utility for consistent source file discovery
        kis_glob_platform_sources("${platform_src_dir}" platform_only_sources)
        foreach(platform_source ${platform_only_sources})
            if(NOT platform_source IN_LIST final_source_list)
                message(STATUS "Adding platform-specific source: '${platform_source}'")
                list(APPEND final_source_list "${platform_source}")
            endif()
        endforeach()
    endforeach()

    # --- Step 3: Create the actual library target with the final list ---
    message(STATUS "Creating library '${ARG_TARGET}' with resolved sources.")
    add_library(${ARG_TARGET} ${final_source_list})
    add_library(kis::${ARG_TARGET} ALIAS ${ARG_TARGET})

    # --- Step 4: Apply config-specific compile definitions ---
    # Set compile definitions based on config suffix (for PER_CONFIG packages)
    if(KIS_CONFIG_SUFFIX STREQUAL "debug")
        target_compile_definitions(${ARG_TARGET} PRIVATE KIS_DEBUG=1)
    endif()
    
    if(KIS_ENABLE_PROFILING)
        target_compile_definitions(${ARG_TARGET} PRIVATE KIS_PROFILING_ENABLED=1)
    endif()

endfunction()