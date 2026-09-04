#!/usr/bin/env bash
# 独立构建 quickjs 引擎动态库（quickjs-ng + bridge shim）。
#
# 设计：quickjs 源码**不进** tvbox-flutter 仓库——本脚本在构建目录里
# 临时 clone 上游源码，编译完成后只输出产物。
#
# 用法：
#   QUICKJS_REF=<tag> ./native/scripts/build_engine.sh <output-dir>
#
# 环境变量：
#   QUICKJS_REPO  上游源码仓库（默认 quickjs-ng 官方）
#   QUICKJS_REF   tag（默认 v0.15.1，发布于 2026-06-04，
#                 与参考实现 quickjs-master 同源）
#
# 版本硬校验：bytecode（//bb 与 //DRPY）与引擎版本强绑定，版本漂移会
# 直接导致生态里所有预编译爬虫模块加载失败，宁可不编也不出错的产物。
#
# 构建：v0.15.1 的 Makefile 只是 CMake wrapper，这里直接走 CMake：
#   - target `qjs`      → libqjs.a（核心：dtoa/libregexp/libunicode/quickjs）
#   - target `qjs-libc` → libqjs-libc.a（bridge 依赖 js_module_set_import_meta）
set -euo pipefail

OUT_DIR="${1:?usage: build_engine.sh <output-dir>}"
QUICKJS_REPO="${QUICKJS_REPO:-https://github.com/quickjs-ng/quickjs.git}"
QUICKJS_REF="${QUICKJS_REF:-v0.15.1}"
EXPECTED_TAG="v0.15.1"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# OUT_DIR 必须先解析成绝对路径：脚本后面会 cd 进临时源码目录，
# 届时相对路径的 OUT_DIR 会落到临时目录里，随 trap 一起被删掉
# （表现为 conformance 报“动态库不存在”）。
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if [ "$QUICKJS_REF" != "$EXPECTED_TAG" ]; then
  echo "警告：ref=$QUICKJS_REF 与参考实现版本（$EXPECTED_TAG）不同，" >&2
  echo "预编译 bytecode（//bb 与 //DRPY）可能无法加载！" >&2
fi

echo "== [1/4] clone quickjs 上游（repo=$QUICKJS_REPO ref=$QUICKJS_REF）=="
git clone --depth 1 --branch "$QUICKJS_REF" "$QUICKJS_REPO" "$WORK/quickjs"
cd "$WORK/quickjs"
echo "    commit: $(git rev-parse --short HEAD)"

echo "== [2/4] CMake 配置与编译（qjs + qjs-libc）=="
# PIC 必开：产物要链进 -shared 的 bridge 动态库，非 PIC 静态库会
# 报 "relocation R_X86_64_PC32 ... recompile with -fPIC"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build build --target qjs qjs-libc -j "$(nproc 2>/dev/null || echo 4)"

echo "== [3/4] 编译并链接 bridge shim =="
CC="${CC:-cc}"
mkdir -p "$OUT_DIR"
SO_NAME="libquickjs_bridge.so"
"$CC" -O2 -fPIC -shared \
  -I . \
  -o "$OUT_DIR/$SO_NAME" \
  "$HERE/../bridge/quickjs_bridge.c" \
  "build/libqjs-libc.a" \
  "build/libqjs.a" \
  -lm -lpthread -ldl

echo "== [4/4] 产物 =="
ls -la "$OUT_DIR/$SO_NAME"

cat <<EOF

构建完成: $OUT_DIR/$SO_NAME
本机验证:
  TVBOX_QJS_LIB=$OUT_DIR/$SO_NAME dart test --directory packages/tvbox_native
EOF
