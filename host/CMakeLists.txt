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
)

target_compile_definitions(ii-host PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(ii-host PRIVATE user32 shell32 ole32 dwmapi advapi32)

# Console multi-call binary: Windows stand-ins for small Linux commands ii calls.
add_executable(ii-shim src/shim.cpp)
target_compile_definitions(ii-shim PRIVATE UNICODE _UNICODE)
target_link_libraries(ii-shim PRIVATE user32 shell32 ole32 powrprof)
