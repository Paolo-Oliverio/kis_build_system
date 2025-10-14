# kis_build_system/CMakeLists.txt
#
# This file's primary purpose is to be included by other KIS SDK packages
# when they are being built in standalone mode. It provides the path to the
# shared CMake modules.

cmake_minimum_required(VERSION 3.20)
project(kis_build_system)

# Set variables in the PARENT_SCOPE so the including project can use them.
# This is the crucial mechanism for sharing the build system logic.

# 1. Provide the path to the directory containing all the *.cmake helper modules.
set(KIS_BUILD_SYSTEM_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/build_system" PARENT_SCOPE)

# 2. Provide the full path to the generic config template for the packaging module.
set(KIS_GENERIC_CONFIG_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/cmake/templates/GenericPackageConfig.cmake.in" PARENT_SCOPE)

message(STATUS "kis_build_system included, providing module path: ${KIS_BUILD_SYSTEM_MODULE_PATH}")