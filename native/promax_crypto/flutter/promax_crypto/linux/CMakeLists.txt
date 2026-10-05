cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "promax_crypto")
project(${PROJECT_NAME} LANGUAGES C CXX)

set(KC_BUILD_STATIC OFF CACHE BOOL "" FORCE)
set(KC_BUILD_TESTS OFF CACHE BOOL "" FORCE)
get_filename_component(KC_PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
get_filename_component(KC_CORE_DIR "${KC_PLUGIN_DIR}/../../.." ABSOLUTE)
add_subdirectory("${KC_CORE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/promax_crypto_core")

set(promax_crypto_bundled_libraries
  $<TARGET_FILE:promax_crypto>
  PARENT_SCOPE
)
