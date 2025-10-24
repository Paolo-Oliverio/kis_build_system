# kis_build_system/CMakeLists.txt

cmake_minimum_required(VERSION 3.22)
include(kis.package.cmake)
project(${PACKAGE_NAME} VERSION ${PACKAGE_VERSION})

# --- Installation Logic ---
# This package's "product" is a set of CMake scripts and a config file
# that allows other projects to use them via find_package().

include(CMakePackageConfigHelpers)
include(GNUInstallDirs)

# 1. Define where the CMake modules will be installed.
set(INSTALL_CMAKEDIR "${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}")

# 2. Install all the CMake script files and templates.
install(
    DIRECTORY modules/ templates/
    DESTINATION ${INSTALL_CMAKEDIR}
    FILES_MATCHING PATTERN "*.cmake" PATTERN "*.in"
)

# 3. Generate and install the package configuration file.
configure_package_config_file(
    "modules/kis_build_system-config.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config.cmake"
    INSTALL_DESTINATION ${INSTALL_CMAKEDIR}
)

# 4. Generate the version file.
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-configVersion.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)

# 5. Install the config and version files.
install(
    FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}-configVersion.cmake"
    DESTINATION ${INSTALL_CMAKEDIR}
)

# 6. Define the INTERFACE target for consistency.
if(NOT TARGET kis_build_system_pkg)
    add_library(kis_build_system_pkg INTERFACE)
    add_library(kis::build_system ALIAS kis_build_system_pkg)
endif()

# 7. Include tests if tests are enabled at the SDK level.
if(KIS_BUILD_TESTS)
    add_subdirectory(tests)
endif()

message(STATUS "Configured kis_build_system package. It provides CMake functions, not libraries.")