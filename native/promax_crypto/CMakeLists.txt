cmake_minimum_required(VERSION 3.18)

project(promax_crypto VERSION 0.2.0 LANGUAGES C)

set(KC_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

file(GLOB KC_SOURCES CONFIGURE_DEPENDS ${KC_ROOT}/src/*.c)
list(FILTER KC_SOURCES EXCLUDE REGEX "kc_all\\.c$")

if(MSVC)
    set(KC_WARNINGS /W4)
    set(KC_MONOCYPHER_WARNINGS /W3)
else()
    set(KC_WARNINGS -Wall -Wextra -Werror -pedantic -Wshadow -Wconversion -Wstrict-prototypes)
    set(KC_MONOCYPHER_WARNINGS -Wall -Wextra -pedantic)
endif()

add_library(kc_monocypher OBJECT ${KC_ROOT}/third_party/monocypher/monocypher.c)
target_include_directories(kc_monocypher PUBLIC ${KC_ROOT}/third_party/monocypher)
target_compile_options(kc_monocypher PRIVATE ${KC_MONOCYPHER_WARNINGS})
set_target_properties(kc_monocypher PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF
    C_VISIBILITY_PRESET hidden
    POSITION_INDEPENDENT_CODE ON)

function(kc_configure_target target)
    target_include_directories(${target}
        PUBLIC ${KC_ROOT}/include
        PRIVATE ${KC_ROOT}/src ${KC_ROOT}/third_party/monocypher)
    target_compile_definitions(${target} PRIVATE KC_BUILDING)
    target_compile_options(${target} PRIVATE ${KC_WARNINGS})
    set_target_properties(${target} PROPERTIES
        C_STANDARD 99
        C_STANDARD_REQUIRED ON
        C_EXTENSIONS OFF
        C_VISIBILITY_PRESET hidden
        POSITION_INDEPENDENT_CODE ON
        PUBLIC_HEADER ${KC_ROOT}/include/promax_crypto.h)
    if(NOT MSVC)
        target_compile_options(${target} PRIVATE -ffunction-sections -fdata-sections)
    endif()
endfunction()

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    option(KC_BUILD_TESTS "Build the promax_crypto test binary" ON)
else()
    option(KC_BUILD_TESTS "Build the promax_crypto test binary" OFF)
endif()

option(KC_BUILD_SHARED "Build the promax_crypto shared library" ON)
option(KC_BUILD_STATIC "Build the promax_crypto_static library" ON)

if(KC_BUILD_SHARED)
    add_library(promax_crypto SHARED ${KC_SOURCES} $<TARGET_OBJECTS:kc_monocypher>)
    kc_configure_target(promax_crypto)
    set_target_properties(promax_crypto PROPERTIES OUTPUT_NAME promax_crypto)
    if(ANDROID)
        target_link_options(promax_crypto PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
    elseif(APPLE)
        target_link_options(promax_crypto PRIVATE -Wl,-dead_strip)
    elseif(NOT MSVC)
        target_link_options(promax_crypto PRIVATE -Wl,--gc-sections)
    endif()
endif()

if(KC_BUILD_STATIC OR KC_BUILD_TESTS)
    add_library(promax_crypto_static STATIC ${KC_SOURCES} $<TARGET_OBJECTS:kc_monocypher>)
    kc_configure_target(promax_crypto_static)
    target_compile_definitions(promax_crypto_static PUBLIC KC_STATIC)
endif()


if(KC_BUILD_TESTS)
    enable_testing()
    add_executable(kc_test ${KC_ROOT}/tests/test_core.c ${KC_ROOT}/tests/test_v2.c)
    target_include_directories(kc_test PRIVATE ${KC_ROOT}/src ${KC_ROOT}/third_party/monocypher)
    target_link_libraries(kc_test PRIVATE promax_crypto_static)
    set_target_properties(kc_test PROPERTIES C_STANDARD 99 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
    if(NOT MSVC)
        target_compile_options(kc_test PRIVATE ${KC_WARNINGS})
    endif()
    add_test(NAME kc_test COMMAND kc_test)

    add_executable(kc_gen_vectors ${KC_ROOT}/tools/gen_vectors.c)
    target_include_directories(kc_gen_vectors PRIVATE ${KC_ROOT}/third_party/monocypher)
    target_link_libraries(kc_gen_vectors PRIVATE promax_crypto_static)
    set_target_properties(kc_gen_vectors PROPERTIES C_STANDARD 99 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
endif()
