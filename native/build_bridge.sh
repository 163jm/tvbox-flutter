#!/usr/bin/env bash
# 编译 quickjs_bridge 动态库（quickjs-ng + C shim）。
#
# 用法：
#   ./native/build_bridge.sh <quickjs-src-dir> <output-dir>
#
# 产物：
#   Linux  : libquickjs_bridge.so
#   macOS  : libquickjs_bridge.dylib
#   Windows: quickjs_bridge.dll（需 MSVC 或 MinGW 工具链）
#
# 注意：quickjs-ng 版本必须与参考实现（quickjs-master，2026-06-04）同源，
# 否则 //bb 与 //DRPY 预编译 bytecode 会因 BC_VERSION / 内置 atom 表
# 差异而无法加载。
set -euo pipefail

QJS_DIR="${1:?usage: build_bridge.sh <quickjs-src-dir> <output-dir>}"
OUT_DIR="${2:?usage: build_bridge.sh <quickjs-src-dir> <output-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$OUT_DIR/build"
mkdir -p "$BUILD_DIR"

CC="${CC:-cc}"
echo "== [1/3] 编译 quickjs-ng 静态库 =="
if [ ! -f "$QJS_DIR/build/libquickjs.a" ]; then
  cmake -S "$QJS_DIR" -B "$QJS_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_QJS_EXE=OFF \
    -DBUILD_QJS_LIBC=ON
  cmake --build "$QJS_DIR/build" -j "$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

echo "== [2/3] 编译 quickjs-libc（bridge 依赖 js_module_set_import_meta）=="
"$CC" -c -O2 -fPIC \
  -I "$QJS_DIR" \
  -o "$BUILD_DIR/quickjs_libc.o" \
  "$QJS_DIR/quickjs-libc.c"

echo "== [3/3] 编译并链接 bridge =="
case "$(uname -s)" in
  Darwin)
    SO="libquickjs_bridge.dylib"
    "$CC" -O2 -fPIC -shared -I "$QJS_DIR" \
      -o "$BUILD_DIR/$SO" \
      "$HERE/quickjs_bridge.c" \
      "$BUILD_DIR/quickjs_libc.o" \
      "$QJS_DIR/build/libquickjs.a" -lm -lpthread
    ;;
  Linux)
    SO="libquickjs_bridge.so"
    "$CC" -O2 -fPIC -shared -I "$QJS_DIR" \
      -o "$BUILD_DIR/$SO" \
      "$HERE/quickjs_bridge.c" \
      "$BUILD_DIR/quickjs_libc.o" \
      "$QJS_DIR/build/libquickjs.a" -lm -lpthread -ldl
    ;;
  MINGW*|MSYS*|CYGWIN*)
    SO="quickjs_bridge.dll"
    "$CC" -O2 -shared -I "$QJS_DIR" \
      -o "$BUILD_DIR/$SO" \
      "$HERE/quickjs_bridge.c" \
      "$BUILD_DIR/quickjs_libc.o" \
      "$QJS_DIR/build/libquickjs.a" -lm -lpthread -lws2_32
    ;;
  *)
    echo "不支持的平台: $(uname -s)" >&2
    exit 1
    ;;
esac

echo "产物: $BUILD_DIR/$SO"
echo "测试: TVBOX_QJS_LIB=$BUILD_DIR/$SO dart test --directory packages/tvbox_native"
