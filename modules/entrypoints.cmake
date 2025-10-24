# kis_build_system/modules/entrypoints.cmake
#
# Defines the public API for initializing the KIS build system in different
# host environments (e.g., standalone package, embedded project).

include_guard(GLOBAL)

#
# kis_bootstrap_standalone
#
# This is the public entrypoint for configuring a standalone KIS package.
# It ensures it's called correctly and then loads and executes the
# standalone-specific configuration logic.
#
function(kis_bootstrap_standalone)
    # --- Safety Guard 1: Must be the top-level project ---
    if(NOT CMAKE_PROJECT_IS_TOP_LEVEL)
        message(FATAL_ERROR "kis_bootstrap_standalone() can only be called from the top-level CMakeLists.txt.")
    endif()

    # --- Safety Guard 2: Must only be called once ---
    if(DEFINED _KIS_STANDALONE_BOOTSTRAPPED)
        message(FATAL_ERROR "kis_bootstrap_standalone() has already been called. It must be called only once.")
    endif()
    set(_KIS_STANDALONE_BOOTSTRAPPED TRUE CACHE INTERNAL "Guard to ensure standalone bootstrap is run once.")

    # --- Load and Execute Host-Specific Logic ---
    # This function's sole purpose is to load the module containing the
    # implementation and then call it. This keeps the core engine clean.
    get_filename_component(module_path "${CMAKE_CURRENT_LIST_FILE}" PATH)
    include("${module_path}/standalone.cmake")

    # Call the internal implementation function
    _kis_internal_standalone_setup()
endfunction()

# Add future entrypoints like kis_bootstrap_embedded() here...