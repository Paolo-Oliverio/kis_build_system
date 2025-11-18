# kis_build_system/modules/targets.cmake

# ==============================================================================
#           INTERNAL HELPER FUNCTIONS
# ==============================================================================

#
# _kis_setup_package_target (INTERNAL)
#
# This helper function applies all standard KIS conventions to an already
# existing target. This is the logic we are abstracting away from the
# individual package CMakeLists.txt files.
#
function(_kis_setup_package_target TARGET_NAME)
    # 1. Set up standard include directories with correct visibility.
    set(public_include_dir "${CMAKE_CURRENT_SOURCE_DIR}/main/include")
    if(IS_DIRECTORY "${public_include_dir}")
        # Determine the correct keyword based on the package type.
        if(MANIFEST_TYPE STREQUAL "LIBRARY")
            kis_message_verbose(STATUS "  [${TARGET_NAME}] Adding PUBLIC include: ${public_include_dir}")
            target_include_directories(${TARGET_NAME} PUBLIC
                $<BUILD_INTERFACE:${public_include_dir}>
                $<INSTALL_INTERFACE:include>
            )
        elseif(MANIFEST_TYPE STREQUAL "INTERFACE")
            kis_message_verbose(STATUS "  [${TARGET_NAME}] Adding INTERFACE include: ${public_include_dir}")
            target_include_directories(${TARGET_NAME} INTERFACE
                $<BUILD_INTERFACE:${public_include_dir}>
                $<INSTALL_INTERFACE:include>
            )
        elseif(MANIFEST_TYPE STREQUAL "EXECUTABLE")
            kis_message_verbose(STATUS "  [${TARGET_NAME}] Adding PRIVATE include: ${public_include_dir}")
            target_include_directories(${TARGET_NAME} PRIVATE
                "${public_include_dir}"
            )
        endif()
    endif()

    # 2. Add platform-specific include directories.
    kis_add_platform_specializations(TARGET ${TARGET_NAME})

    # 3. Apply standard SDK build settings (warnings, C++ standard, etc.).
    if(BUILDING_WITH_SUPERBUILD)
        kis_apply_sdk_build_settings_to_target(${TARGET_NAME})
    else()
        apply_kis_build_presets(${TARGET_NAME})
    endif()

    # 4. Automatically link dependencies declared for the 'main' scope.
    kis_link_from_manifest(TARGET ${TARGET_NAME} SCOPE main)

    # 5. Install the package artifacts based on its type from the manifest.
    if(MANIFEST_TYPE STREQUAL "INTERFACE")
        kis_install_interface_package()
    else() # Handles LIBRARY and EXECUTABLE
        kis_install_package()
    endif()

    # 6. Install any public assets.
    kis_install_assets()
endfunction()


# ==============================================================================
#           PRIMARY PUBLIC API
# ==============================================================================

#
# kis_define_package
#
# This is the new, primary function for defining a KIS package.
# It reads the manifest, creates the target, and applies all conventions.
#
function(kis_define_package)
    set(options)
    set(oneValueArgs)
    set(multiValueArgs SOURCES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # This function NO LONGER manages the context. It relies on the context
    # being set by the caller (configure_discovered_packages).
    
    # Read the manifest to get the package's name and type.
    # This call now reliably finds the correct manifest because the context
    # variable _KIS_CTX_CURRENT_PACKAGE_ROOT was set by the calling loop.
    kis_read_package_manifest_json()

    if(NOT DEFINED MANIFEST_NAME OR NOT DEFINED MANIFEST_TYPE)
        message(FATAL_ERROR "Could not define package. 'name' and 'type' must be set in kis.package.json.")
    endif()
    
    message(STATUS "Defining KIS package: ${MANIFEST_NAME} (Type: ${MANIFEST_TYPE})")

    # Create the target based on the manifest type.
    if(MANIFEST_TYPE STREQUAL "LIBRARY")
        kis_add_library(${MANIFEST_NAME} SOURCES ${ARG_SOURCES})
    elseif(MANIFEST_TYPE STREQUAL "EXECUTABLE")
        add_executable(${MANIFEST_NAME} ${ARG_SOURCES})
        add_library(kis::${MANIFEST_NAME} ALIAS ${MANIFEST_NAME})
    elseif(MANIFEST_TYPE STREQUAL "INTERFACE")
        if(ARG_SOURCES)
            message(WARNING "SOURCES provided for INTERFACE package '${MANIFEST_NAME}' will be ignored.")
        endif()
        add_library(${MANIFEST_NAME} INTERFACE)
        add_library(kis::${MANIFEST_NAME} ALIAS ${MANIFEST_NAME})
    else()
        message(FATAL_ERROR "Unknown package type '${MANIFEST_TYPE}' in manifest for '${MANIFEST_NAME}'.")
    endif()

    # Apply all the standard boilerplate setup to the new target.
    _kis_setup_package_target(${MANIFEST_NAME})
endfunction()


#
# kis_add_library (Now primarily an implementation detail for kis_define_package)
#
function(kis_add_library)
    # ... (this function's implementation remains unchanged) ...
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs SOURCES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if(NOT ARG_TARGET)
        if(ARG_UNPARSED_ARGUMENTS)
            list(GET ARG_UNPARSED_ARGUMENTS 0 _pos_target)
            set(ARG_TARGET ${_pos_target})
            list(REMOVE_AT ARG_UNPARSED_ARGUMENTS 0)
            if(NOT ARG_SOURCES)
                set(ARG_SOURCES ${ARG_UNPARSED_ARGUMENTS})
            endif()
        else()
            message(FATAL_ERROR "kis_add_library requires a TARGET argument.")
        endif()
    endif()
    set(final_source_list "")
    set(platform_src_base_path "${CMAKE_CURRENT_SOURCE_DIR}/main/platform")
    set(reversed_tags ${KIS_PLATFORM_TAGS})
    list(REVERSE reversed_tags)
    foreach(common_source ${ARG_SOURCES})
        get_filename_component(common_filename ${common_source} NAME)
        set(override_found FALSE)
        foreach(tag ${reversed_tags})
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
    foreach(tag ${reversed_tags})
        set(platform_src_dir "${platform_src_base_path}/${tag}/src")
        kis_glob_platform_sources("${platform_src_dir}" platform_only_sources)
        foreach(platform_source ${platform_only_sources})
            if(NOT platform_source IN_LIST final_source_list)
                message(STATUS "Adding platform-specific source: '${platform_source}'")
                list(APPEND final_source_list "${platform_source}")
            endif()
        endforeach()
    endforeach()
    kis_message_verbose(STATUS "Creating library '${ARG_TARGET}' with resolved sources.")
    add_library(${ARG_TARGET} ${final_source_list})
    add_library(kis::${ARG_TARGET} ALIAS ${ARG_TARGET})
    if(KIS_CONFIG_SUFFIX STREQUAL "debug")
        target_compile_definitions(${ARG_TARGET} PRIVATE KIS_DEBUG=1)
    endif()
    if(KIS_ENABLE_PROFILING)
        target_compile_definitions(${ARG_TARGET} PRIVATE KIS_PROFILING_ENABLED=1)
    endif()
endfunction()