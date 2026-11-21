cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "spp_channel.cc"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# 源码里的注释是 UTF-8。MSVC 默认按本地代码页(GBK)读, 中文的尾字节常被当成
# 续行反斜杠, 一整个头文件的结构就散了(报错是莫名其妙的 "语法错误: public")。
target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")

# Flutter 的 flutter_view_controller.h 会先把 windows.h 拉进来, 而 windows.h 默认
# 顺带引入 winsock.h(1.1)。之后再 include winsock2.h 就是两套 socket 头撞在一起,
# 报一连串 sockaddr 重定义。定义这个宏让 windows.h 别管 winsock。
target_compile_definitions(${BINARY_NAME} PRIVATE "WIN32_LEAN_AND_MEAN")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# 经典蓝牙 SPP: bthprops 提供枚举无线电/已配对设备, ws2_32 提供 AF_BTH 的 socket。
target_link_libraries(${BINARY_NAME} PRIVATE "bthprops.lib" "ws2_32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
