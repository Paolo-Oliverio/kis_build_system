# cmake/build_system/presets_logic.cmake
# Contains the raw logic for applying KIS SDK build presets.
# This can be applied to an INTERFACE target (superbuild) or a regular target (standalone).

function(apply_kis_build_presets TARGET_NAME)
    # Get the type of the target we are applying presets to.
    get_target_property(TARGET_TYPE ${TARGET_NAME} TYPE)

    if(TARGET_TYPE STREQUAL "INTERFACE_LIBRARY")
        # --- Case 1: SUPERBUILD MODE ---
        # We are applying presets to the central 'kis_sdk_presets' INTERFACE target.

        # These are PUBLIC API requirements. They must be INTERFACE so they
        # propagate to packages AND to final consumers.
        target_compile_features(${TARGET_NAME} INTERFACE cxx_std_17)

        target_compile_definitions(${TARGET_NAME} INTERFACE
            $<$<PLATFORM_ID:Windows>:UNICODE;_UNICODE>
            KIS_DISABLE_DEPRECATED
        )

        # We want to apply these settings (temp they will change), but we do NOT 
        # want to propagate these flags into the install interface.
        target_compile_options(${TARGET_NAME} INTERFACE
            $<$<CXX_COMPILER_ID:MSVC>:/W4 /WX>
            $<$<AND:$<CXX_COMPILER_ID:GNU,Clang>,$<NOT:$<CXX_COMPILER_ID:AppleClang>>>:-Wall -Wextra -Wpedantic -Werror>
        )
    else()
        # --- Case 2: STANDALONE MODE ---
        # We are applying presets to a regular package (e.g., STATIC_LIBRARY).
        # We must use PUBLIC and PRIVATE keywords.

        # Features and definitions should be PUBLIC so consumers of this package inherit them.
        target_compile_features(${TARGET_NAME} PUBLIC cxx_std_17)

        target_compile_definitions(${TARGET_NAME} PUBLIC
            $<$<PLATFORM_ID:Windows>:UNICODE;_UNICODE>
            KIS_DISABLE_DEPRECATED
        )

        # Compile options (like warnings) should be PRIVATE. This applies them to our
        # package during its build but does NOT force these strict flags on consumers.
        target_compile_options(${TARGET_NAME} PRIVATE
            $<$<CXX_COMPILER_ID:MSVC>:/W4 /WX>
            $<$<AND:$<CXX_COMPILER_ID:GNU,Clang>,$<NOT:$<CXX_COMPILER_ID:AppleClang>>>:-Wall -Wextra -Wpedantic -Werror>
        )
    endif()
endfunction()