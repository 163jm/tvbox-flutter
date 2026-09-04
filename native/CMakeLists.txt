# native/quickjs_bridge 的 CMake 构建。
# 通过 QJS_DIR 指向 quickjs-ng 源码目录（CI 里临时 clone，不进仓库）。
cmake_minimum_required(VERSION 3.15)
project(quickjs_bridge C)

set(QJS_DIR "" CACHE PATH "path to quickjs-ng source tree")
if(NOT QJS_DIR)
  message(FATAL_ERROR "请用 -DQJS_DIR=<quickjs-ng 源码目录> 指定源码位置")
endif()

# quickjs-ng：qjs（核心静态库）与 qjs-libc（bridge 依赖 js_module_set_import_meta）
add_subdirectory(${QJS_DIR} qjs-build EXCLUDE_FROM_ALL)

add_library(quickjs_bridge SHARED bridge/quickjs_bridge.c)
target_include_directories(quickjs_bridge PRIVATE ${QJS_DIR})
# MSVC 需要 C11；quickjs-ng 头文件按 C99+ 设计
target_compile_definitions(quickjs_bridge PRIVATE _GNU_SOURCE)
target_link_libraries(quickjs_bridge PRIVATE qjs qjs-libc)
