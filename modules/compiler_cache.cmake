# kis_build_system/modules/compiler_cache.cmake
#
# Auto-detects and enables compiler caching tools (ccache/sccache)
# for faster rebuilds

#
# kis_setup_compiler_cache
#
# Automatically detects and configures compiler cache tools
#
function(kis_setup_compiler_cache)
    # Allow user to disable
    if(DEFINED KIS_DISABLE_COMPILER_CACHE AND KIS_DISABLE_COMPILER_CACHE)
        kis_message_verbose("Compiler cache explicitly disabled by user")
        return()
    endif()
    
    # Try to find ccache first (most common)
    find_program(CCACHE_PROGRAM ccache)
    if(CCACHE_PROGRAM)
        set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}" PARENT_SCOPE)
        set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}" PARENT_SCOPE)
        message(STATUS "[OK] Compiler cache enabled: ccache (${CCACHE_PROGRAM})")
        
        # Set recommended ccache options
        set(ENV{CCACHE_SLOPPINESS} "pch_defines,time_macros")
        return()
    endif()
    
    # Try sccache as fallback
    find_program(SCCACHE_PROGRAM sccache)
    if(SCCACHE_PROGRAM)
        set(CMAKE_C_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}" PARENT_SCOPE)
        set(CMAKE_CXX_COMPILER_LAUNCHER "${SCCACHE_PROGRAM}" PARENT_SCOPE)
        message(STATUS "[OK] Compiler cache enabled: sccache (${SCCACHE_PROGRAM})")
        return()
    endif()
    
    # No cache found
    kis_message_verbose("No compiler cache found (ccache/sccache). Consider installing for faster rebuilds.")
    kis_message_verbose("  Windows: choco install ccache")
    kis_message_verbose("  macOS:   brew install ccache")
    kis_message_verbose("  Linux:   apt/yum install ccache")
endfunction()
