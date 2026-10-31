cmake_minimum_required(VERSION 3.18)

project(promax_effects LANGUAGES CXX)

add_library(promax_effects SHARED src/main/cpp/promax_effects_jni.cpp)

target_include_directories(promax_effects PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes")
target_compile_features(promax_effects PRIVATE cxx_std_17)
target_compile_options(promax_effects PRIVATE -O2 -fvisibility=hidden -ffunction-sections -fdata-sections)
target_link_options(promax_effects PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
