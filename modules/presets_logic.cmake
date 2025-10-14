# kis_build_system/modules/presets_logic.cmake

# This function now has two purposes:
# 1. In Standalone mode, it applies presets directly to a real target.
# 2. In Superbuild mode, it applies presets to the central INTERFACE target.
function(apply_kis_build_presets TARGET_NAME)
    # Resolve alias targets to their real underlying target.
    set(TARGET_TO_MODIFY ${TARGET_NAME})
    get_target_property(ALIASED_TARGET_NAME ${TARGET_NAME} ALIASED_TARGET)
    if(ALIASED_TARGET_NAME)
        set(TARGET_TO_MODIFY ${ALIASED_TARGET_NAME})
    endif()

    get_target_property(TARGET_TYPE ${TARGET_TO_MODIFY} TYPE)

    if(TARGET_TYPE STREQUAL "INTERFACE_LIBRARY")
        # Case 1: SUPERBUILD MODE - Applying to the central kis::build_system target
        target_compile_features(${TARGET_TO_MODIFY} INTERFACE cxx_std_17)
        target_compile_definitions(${TARGET_TO_MODIFY} INTERFACE
            $<$<PLATFORM_ID:Windows>:UNICODE;_UNICODE>
            KIS_DISABLE_DEPRECATED
        )
        target_compile_options(${TARGET_TO_MODIFY} INTERFACE
            $<$<CXX_COMPILER_ID:MSVC>:/W4 /WX>
            $<$<AND:$<CXX_COMPILER_ID:GNU,Clang>,$<NOT:$<CXX_COMPILER_ID:AppleClang>>>:-Wall -Wextra -Wpedantic -Werror>
        )
    else()
        # Case 2: STANDALONE MODE - Applying to a package target directly
        target_compile_features(${TARGET_TO_MODIFY} PUBLIC cxx_std_17)
        target_compile_definitions(${TARGET_TO_MODIFY} PUBLIC
            $<$<PLATFORM_ID:Windows>:UNICODE;_UNICODE>
            KIS_DISABLE_DEPRECATED
        )
        target_compile_options(${TARGET_TO_MODIFY} PRIVATE
            $<$<CXX_COMPILER_ID:MSVC>:/W4 /WX>
            $<$<AND:$<CXX_COMPILER_ID:GNU,Clang>,$<NOT:$<CXX_COMPILER_ID:AppleClang>>>:-Wall -Wextra -Wpedantic -Werror>
        )
    endif()
endfunction()


# --- THIS IS THE NEW FUNCTION ---
# This is the definitive solution to the export error. Instead of creating a
# link dependency, it directly copies the build settings from the central
# presets target to a given package target. This creates no link for the
# install(EXPORT) command to complain about.
function(kis_apply_sdk_build_settings_to_target TARGET_NAME)
    if(NOT TARGET kis::build_system)
        message(FATAL_ERROR "kis_apply_sdk_build_settings_to_target called but kis::build_system target does not exist. This should only be called in a superbuild.")
        return()
    endif()

    message(STATUS "Copying SDK build settings from kis::build_system to ${TARGET_NAME}")

    # Get all the INTERFACE properties from the central build system target
    get_target_property(features kis::build_system INTERFACE_COMPILE_FEATURES)
    get_target_property(definitions kis::build_system INTERFACE_COMPILE_DEFINITIONS)
    get_target_property(options kis::build_system INTERFACE_COMPILE_OPTIONS)

    # Apply them PRIVATELY to the package target.
    if(features)
        target_compile_features(${TARGET_NAME} PRIVATE ${features})
    endif()
    if(definitions)
        target_compile_definitions(${TARGET_NAME} PRIVATE ${definitions})
    endif()
    if(options)
        target_compile_options(${TARGET_NAME} PRIVATE ${options})
    endif()
endfunction()