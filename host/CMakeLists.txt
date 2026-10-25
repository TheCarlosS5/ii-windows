cmake_minimum_required(VERSION 3.21)
project(ii-host LANGUAGES CXX RC)

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
	src/keyrouter.cpp
	src/volume.cpp
	src/windowfx.cpp
	src/showdesktop.cpp
	src/banners.cpp
	src/theme.cpp
	src/nightlight.cpp
	src/nightlight_core.cpp
	src/splash.cpp
	src/health.cpp
	src/rollout.cpp
	src/jsonlite.cpp
	src/configtool.cpp
	src/screentime.cpp
)

target_compile_definitions(ii-host PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(ii-host PRIVATE user32 shell32 ole32 dwmapi advapi32 gdi32 windowscodecs gdiplus wtsapi32 Magnification dxgi)

# Console multi-call binary: Windows stand-ins for small Linux commands ii calls.
# Google's material-color-utilities (Apache-2.0), fetched by tools/dev/fetch_mcu.ps1, for the
# wallpaper palette. host/compat stands in for the two bits of Abseil it uses.
set(MCU_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/material-color-utilities)
file(GLOB_RECURSE MCU_SOURCES ${MCU_DIR}/cpp/*.cc)
list(FILTER MCU_SOURCES EXCLUDE REGEX "_test\.cc$")
if(NOT MCU_SOURCES)
	message(FATAL_ERROR "material-color-utilities missing: run tools/dev/fetch_mcu.ps1")
endif()

add_executable(ii-shim src/shim.cpp src/brightness.cpp src/capture.cpp src/switchwall.cpp src/extwall.cpp src/randomwall.cpp
	src/http.h src/http.cpp src/airequest.cpp src/weather.cpp src/cava.cpp src/ydotool.cpp src/secrettool.cpp src/cliphist.cpp src/fsutil.cpp src/hyprpicker.cpp src/trans.cpp src/sidebar.cpp src/fileops.cpp src/nightlight_core.cpp src/vdesk.cpp src/jsonlite.cpp src/configtool.cpp src/lockimage.cpp src/top.cpp ${MCU_SOURCES})
target_include_directories(ii-shim PRIVATE ${MCU_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/compat)
# M_PI, and the C99 compound literals it uses (build with clang-cl, as Quickshell).
target_compile_definitions(ii-shim PRIVATE _USE_MATH_DEFINES)
set_source_files_properties(${MCU_SOURCES} PROPERTIES COMPILE_OPTIONS "-Wno-everything;/FIoptional")
target_compile_definitions(ii-shim PRIVATE UNICODE _UNICODE)
# capture.cpp uses C++/WinRT for Windows' OCR.
target_compile_options(ii-shim PRIVATE /EHsc)
target_link_libraries(ii-shim PRIVATE user32 gdi32 shell32 ole32 oleaut32 wbemuuid dxva2 powrprof windowscodecs uuid windowsapp winhttp advapi32 crypt32)

# Console-only safety tests with fake displays. Never calls a display or power setter.
add_executable(ii-sidebar-test src/nightlight_test.cpp src/nightlight_core.cpp)

# Test-only stand-in for quickshell.exe (tools/sandbox/tests/test-host-launch.ps1). Not packaged.
add_executable(ii-fake-shell WIN32 ../tools/sandbox/fixtures/fake-shell/fake-shell.cpp src/rollout.cpp)
target_include_directories(ii-fake-shell PRIVATE src)
target_compile_definitions(ii-fake-shell PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
target_link_libraries(ii-fake-shell PRIVATE user32 shell32)

# R03: the lock contract of quickshell-windows (WlSessionLock) as a plain state machine.
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/../quickshell/src/win32/compat/lockstate.hpp)
	add_executable(ii-lockstate-test src/lockstate_test.cpp)
	target_compile_options(ii-lockstate-test PRIVATE /EHsc)
endif()

# R07: the stable entry point of a versioned installation (see src/rollout.h).
add_executable(ii-launcher WIN32 src/launcher.cpp src/rollout.cpp)
target_compile_definitions(ii-launcher PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(ii-launcher PRIVATE user32 shell32)

# U02: the keyboard hook's decisions, tested without a keyboard.
add_executable(ii-keyrouter-test src/keyboard_test.cpp src/keyrouter.cpp)
target_compile_options(ii-keyrouter-test PRIVATE /EHsc)
target_link_libraries(ii-keyrouter-test PRIVATE user32)

# R09: the rule for removing an empty virtual desktop, tested without Explorer.
add_executable(ii-vdesk-test src/vdesk_test.cpp)
target_compile_options(ii-vdesk-test PRIVATE /EHsc)

# D01: the config tools (JSON reader, schema validation, guard, last-good, export/import) in a throwaway folder.
add_executable(ii-config-test src/config_test.cpp src/configtool.cpp src/jsonlite.cpp)
target_compile_options(ii-config-test PRIVATE /EHsc)
target_link_libraries(ii-config-test PRIVATE user32)

# Development only: the welcome cover on its own (tools\dev\splash-preview.ps1). Not packaged.
add_executable(ii-splash-preview WIN32 src/splash_preview.cpp src/splash.cpp src/common.cpp)
target_compile_definitions(ii-splash-preview PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(ii-splash-preview PRIVATE user32 shell32 ole32 advapi32 gdi32 windowscodecs gdiplus)

# Version resource (name, description, author) on every executable that ships. The version comes from the one place
# the release sets it, tools/package/make-package.ps1 ($baseVersion).
file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/../tools/package/make-package.ps1 II_VERSION_LINE REGEX "^\\\$baseVersion = '[0-9.]+'")
string(REGEX MATCH "[0-9]+\\.[0-9]+\\.[0-9]+" II_VERSION "${II_VERSION_LINE}")
if(NOT II_VERSION)
	set(II_VERSION 0.0.0)
endif()
string(REPLACE "." ";" II_VERSION_PARTS ${II_VERSION})
list(GET II_VERSION_PARTS 0 II_VERSION_MAJOR)
list(GET II_VERSION_PARTS 1 II_VERSION_MINOR)
list(GET II_VERSION_PARTS 2 II_VERSION_PATCH)
function(ii_version_info target description)
	set(II_FILE_DESCRIPTION "${description}")
	set(II_FILE_NAME "${target}")
	configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/version.rc.in ${CMAKE_CURRENT_BINARY_DIR}/${target}-version.rc @ONLY)
	target_sources(${target} PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/${target}-version.rc)
endfunction()
ii_version_info(ii-host "ii-windows host: hides and restores the Windows taskbar, runs the ii shell")
ii_version_info(ii-shim "ii-windows helper commands for the ii shell")
ii_version_info(ii-launcher "ii-windows launcher: starts the installed version of ii")
