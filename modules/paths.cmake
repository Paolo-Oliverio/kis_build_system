# cmake/build_system/paths.cmake

function(setup_sdk_paths)
    if(NOT DEFINED SDK_VERSION)
        set(SDK_VERSION "0.1.0")
    endif()

    message(STATUS "Setting up KIS SDK paths with version: ${SDK_VERSION} for platform: ${KIS_PLATFORM_ID}")

    if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
        set(DEFAULT_SDK_INSTALL_ROOT "${CMAKE_SOURCE_DIR}/_install/kis_sdk-${SDK_VERSION}")
        set(CMAKE_INSTALL_PREFIX "${DEFAULT_SDK_INSTALL_ROOT}"
            CACHE PATH "Root directory for the KIS SDK installation." FORCE
        )
    endif()
    
    include(GNUInstallDirs)

    # --- DEFINE INSTALL PATHS ---
    # Platform-specific base paths (used for DEFAULT packages)
    set(KIS_INSTALL_LIBDIR_PLATFORM "lib/${KIS_PLATFORM_ID}" CACHE INTERNAL "")
    set(KIS_INSTALL_BINDIR_PLATFORM "bin/${KIS_PLATFORM_ID}" CACHE INTERNAL "")
    
    # Config-specific paths with suffix (used for PER_CONFIG packages)
    set(KIS_INSTALL_LIBDIR_PF_ARCH "lib/${KIS_PLATFORM_ID}${KIS_PATH_SUFFIX}" CACHE INTERNAL "")
    set(KIS_INSTALL_BINDIR_PF_ARCH "bin/${KIS_PLATFORM_ID}${KIS_PATH_SUFFIX}" CACHE INTERNAL "")

    # Headers, assets, and CMake configs are common at the top level.
    set(KIS_INSTALL_INCLUDEDIR_COMMON "include" CACHE INTERNAL "")
    set(KIS_INSTALL_ASSETSDIR_COMMON "assets" CACHE INTERNAL "")
    set(KIS_INSTALL_CMAKEDIR_COMMON "lib/cmake" CACHE INTERNAL "")

    # Override the standard GNUInstallDirs variables for our packages.
    # This makes `install(TARGETS ...)` automatically use the correct platform/arch specific paths.
    set(CMAKE_INSTALL_LIBDIR "${KIS_INSTALL_LIBDIR_PF_ARCH}" CACHE PATH "Platform/Arch-specific library directory" FORCE)
    set(CMAKE_INSTALL_BINDIR "${KIS_INSTALL_BINDIR_PF_ARCH}" CACHE PATH "Platform/Arch-specific runtime directory" FORCE)
    set(CMAKE_INSTALL_INCLUDEDIR "${KIS_INSTALL_INCLUDEDIR_COMMON}" CACHE PATH "Common include directory" FORCE)

    message(STATUS "KIS SDK Superbuild")
    message(STATUS "  - Install Root:          ${CMAKE_INSTALL_PREFIX}")
    message(STATUS "  - Platform ID:           ${KIS_PLATFORM_ID}")
    if(KIS_CONFIG_SUFFIX)
        message(STATUS "  - Config Suffix:         ${KIS_CONFIG_SUFFIX}")
    endif()
    message(STATUS "  - Default Libs/Bins:     ${CMAKE_INSTALL_PREFIX}/{lib,bin}/${KIS_PLATFORM_ID}")
    if(KIS_PATH_SUFFIX)
        message(STATUS "  - Config Libs/Bins:      ${CMAKE_INSTALL_PREFIX}/{lib,bin}/${KIS_PLATFORM_ID}${KIS_PATH_SUFFIX}")
    endif()
    message(STATUS "  - Headers Install Dir:   ${CMAKE_INSTALL_PREFIX}/${KIS_INSTALL_INCLUDEDIR_COMMON}")
    message(STATUS "  - CMake Pkg Dir:         ${CMAKE_INSTALL_PREFIX}/${KIS_INSTALL_CMAKEDIR_COMMON}")
endfunction()