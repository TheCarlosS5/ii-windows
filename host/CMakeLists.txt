cmake_minimum_required(VERSION 3.21)
project(ii-host LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Static CRT: ii-host and the rescue path must work with nothing else installed.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(ii-host WIN32
	src/main.cpp
	src/common.cpp
	src/taskbar.cpp
	src/desktop.cpp
	src/keyboard.cpp
	src/showdesktop.cpp
	src/banners.cpp
	src/theme.cpp
	src/nightlight.cpp
	src/nightlight_core.cpp
)

target_compile_definitions(ii-host PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(ii-host PRIVATE user32 shell32 ole32 dwmapi advapi32 gdi32)

# Console multi-call binary: Windows stand-ins for small Linux commands ii calls.
# Google's material-color-utilities (Apache-2.0), fetched by tools/dev/fetch_mcu.ps1, for the
# wallpaper palette. host/compat stands in for the two bits of Abseil it uses.
set(MCU_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/material-color-utilities)
file(GLOB_RECURSE MCU_SOURCES ${MCU_DIR}/cpp/*.cc)
list(FILTER MCU_SOURCES EXCLUDE REGEX "_test\.cc$")
if(NOT MCU_SOURCES)
	message(FATAL_ERROR "material-color-utilities missing: run tools/dev/fetch_mcu.ps1")
endif()

add_executable(ii-shim src/shim.cpp src/brightness.cpp src/capture.cpp src/switchwall.cpp src/randomwall.cpp
	src/http.h src/http.cpp src/weather.cpp src/sidebar.cpp src/fileops.cpp src/nightlight_core.cpp ${MCU_SOURCES})
target_include_directories(ii-shim PRIVATE ${MCU_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/compat)
# M_PI, and the C99 compound literals it uses (build with clang-cl, as Quickshell).
target_compile_definitions(ii-shim PRIVATE _USE_MATH_DEFINES)
set_source_files_properties(${MCU_SOURCES} PROPERTIES COMPILE_OPTIONS "-Wno-everything;/FIoptional")
target_compile_definitions(ii-shim PRIVATE UNICODE _UNICODE)
# capture.cpp uses C++/WinRT for Windows' OCR.
target_compile_options(ii-shim PRIVATE /EHsc)
target_link_libraries(ii-shim PRIVATE user32 gdi32 shell32 ole32 oleaut32 wbemuuid dxva2 powrprof windowscodecs uuid windowsapp winhttp advapi32)

# Console-only safety tests with fake displays. Never calls a display or power setter.
add_executable(ii-sidebar-test src/nightlight_test.cpp src/nightlight_core.cpp)
