# kis_build_system/modules/platforms.cmake
#
# PURPOSE: Provides platform-related helper functions (the public API) for
# individual KIS packages to use in their CMakeLists.txt files.

function(kis_add_platform_specializations)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Allow either: kis_add_platform_specializations(TARGET <name>)
    # or the simpler positional form: kis_add_platform_specializations(<name>)
    if(NOT ARG_TARGET)
        if(ARG_UNPARSED_ARGUMENTS)
            list(GET ARG_UNPARSED_ARGUMENTS 0 _pos_target)
            set(ARG_TARGET ${_pos_target})
            # remove it from unparsed args so it won't be used elsewhere
            list(REMOVE_AT ARG_UNPARSED_ARGUMENTS 0)
        else()
            message(FATAL_ERROR "kis_add_platform_specializations requires a TARGET argument.")
        endif()
    endif()

    if(NOT CMAKE_CURRENT_SOURCE_DIR)
        message(FATAL_ERROR "This function must be called from a package's CMakeLists.txt")
    endif()

    # --- FIX: The base path for platform specializations is main/platform, NOT main/src/platform ---
    # This directory parallels main/include and main/src, containing platform-specific overrides.
    set(base_path "${CMAKE_CURRENT_SOURCE_DIR}/main/platform")

    if(NOT IS_DIRECTORY "${base_path}")
        return() # No platform specializations in this package.
    endif()

    message(STATUS "Scanning for platform include specializations for target '${ARG_TARGET}'...")

    set(reversed_tags ${KIS_PLATFORM_TAGS})
    list(REVERSE reversed_tags)

    foreach(tag ${reversed_tags})
        # e.g., .../main/platform/windows
        set(platform_dir "${base_path}/${tag}")
        if(NOT IS_DIRECTORY "${platform_dir}")
            continue()
        endif()

        # Add platform-specific include directory.
        # e.g., .../main/platform/windows/include
        set(platform_include_dir "${platform_dir}/include")
        message(STATUS "Checking for platform include directory: '${platform_include_dir}'")
        if(IS_DIRECTORY "${platform_include_dir}")
            message(STATUS "--> Applying include specialization for platform tag: '${tag}'")
            target_include_directories(${ARG_TARGET} PUBLIC
                $<BUILD_INTERFACE:${platform_include_dir}>
                $<INSTALL_INTERFACE:include>
            )
        endif()
    endforeach()

    # --- Handle Installation of Platform-Specific Headers ---
    # This logic is now correct because it uses the fixed base_path variable.
    foreach(tag ${KIS_PLATFORM_TAGS})
        set(platform_include_dir "${base_path}/${tag}/include")
        if(IS_DIRECTORY "${platform_include_dir}")
            message(STATUS "--> Installing header overrides from '${tag}' tag.")
            install(DIRECTORY "${platform_include_dir}/" DESTINATION "platform_include/${tag}")
        endif()
    endforeach()
endfunction()