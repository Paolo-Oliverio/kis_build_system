# kis_build_system/modules/presets_logic.cmake

# This function is for STANDALONE builds.
function(apply_kis_build_presets TARGET_NAME)
    # Add alias-checking to make this function robust. It will resolve an
    # alias like 'kis::build_system' to its real target 'kis_build_system_pkg'
    # before attempting to modify it.
    set(TARGET_TO_MODIFY ${TARGET_NAME})
    get_target_property(ALIASED_TARGET_NAME ${TARGET_NAME} ALIASED_TARGET)
    if(ALIASED_TARGET_NAME)
        set(TARGET_TO_MODIFY ${ALIASED_TARGET_NAME})
    endif()

    get_target_property(target_type ${TARGET_TO_MODIFY} TYPE)
    if(target_type STREQUAL "INTERFACE_LIBRARY")
        # Interface libraries propagate everything via the INTERFACE keyword.
        target_compile_features(${TARGET_TO_MODIFY} INTERFACE cxx_std_17)
        target_compile_definitions(${TARGET_TO_MODIFY} INTERFACE
            $<$<PLAT_ID:Windows>:UNICODE;_UNICODE>
            KIS_DISABLE_DEPRECATED
        )
    else()
        # Regular libraries have public and private properties.
        target_compile_features(${TARGET_TO_MODIFY} PUBLIC cxx_std_17)
        target_compile_definitions(${TARGET_TO_MODIFY} PUBLIC
            $<$<PLAT_ID:Windows>:UNICODE;_UNICODE>
            KIS_DISABLE_DEPRECATED
        )
        target_compile_options(${TARGET_TO_MODIFY} PRIVATE
            $<$<CXX_COMPILER_ID:MSVC>:/W4 /WX>
            $<$<AND:$<CXX_COMPILER_ID:GNU,Clang>,$<NOT:$<CXX_COMPILER_ID:AppleClang>>>:-Wall -Wextra -Wpedantic -Werror>
        )
    endif()
endfunction()


# This function is for SUPERBUILDS. It reads the globally defined SDK settings
# and applies them to a given package target. (This function is already correct).
function(kis_apply_sdk_build_settings_to_target TARGET_NAME)
    message(STATUS "Applying SDK build settings to ${TARGET_NAME}")
    get_property(public_features GLOBAL PROPERTY KIS_SDK_PUBLIC_COMPILE_FEATURES)
    get_property(public_definitions GLOBAL PROPERTY KIS_SDK_PUBLIC_COMPILE_DEFINITIONS)
    get_property(private_options GLOBAL PROPERTY KIS_SDK_PRIVATE_COMPILE_OPTIONS)
    get_target_property(target_type ${TARGET_NAME} TYPE)

    if(target_type STREQUAL "INTERFACE_LIBRARY")
        if(public_features)
            target_compile_features(${TARGET_NAME} INTERFACE ${public_features})
        endif()
        if(public_definitions)
            target_compile_definitions(${TARGET_NAME} INTERFACE ${public_definitions})
        endif()
        if(private_options)
            target_compile_options(${TARGET_NAME} INTERFACE ${private_options})
        endif()
    else()
        if(public_features)
            target_compile_features(${TARGET_NAME} PUBLIC ${public_features})
        endif()
        if(public_definitions)
            target_compile_definitions(${TARGET_NAME} PUBLIC ${public_definitions})
        endif()
        if(private_options)
            target_compile_options(${TARGET_NAME} PRIVATE ${private_options})
        endif()
    endif()
endfunction()