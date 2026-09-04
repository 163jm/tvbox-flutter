#!/usr/bin/env bash
# 独立构建 quickjs 引擎动态库（quickjs-ng + bridge shim）。
#
# 设计：quickjs 源码**不进** tvbox-flutter 仓库——本脚本在构建目录里
# 临时 clone 上游源码，编译完成后只输出产物。
#
# 用法：
#   QUICKJS_REF=<tag-or-branch> ./native/scripts/build_engine.sh <output-dir>
#
# 环境变量：
#   QUICKJS_REPO  上游源码仓库（默认 quickjs-ng 官方）
#   QUICKJS_REF   tag / branch（默认 main）
#
# 硬校验：clone 下来的 VERSION 必须是 2026-06-04。
# bytecode（//bb 与 //DRPY）与引擎版本强绑定，版本漂移会直接导致
# 生态里所有预编译爬虫模块加载失败，宁可不编也不出错的产物。
set -euo pipefail

OUT_DIR="${1:?usage: build_engine.sh <output-dir>}"
QUICKJS_REPO="${QUICKJS_REPO:-https://github.com/quickjs-ng/quickjs.git}"
QUICKJS_REF="${QUICKJS_REF:-main}"
EXPECTED_VERSION="2026-06-04"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== [1/4] clone quickjs 上游（repo=$QUICKJS_REPO ref=$QUICKJS_REF）=="
git clone --depth 1 --branch "$QUICKJS_REF" "$QUICKJS_REPO" "$WORK/quickjs"

ACTUAL_VERSION="$(tr -d '[:space:]' < "$WORK/quickjs/VERSION")"
if [ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]; then
  echo "错误：quickjs 版本不匹配。实际=$ACTUAL_VERSION 期望=$EXPECTED_VERSION" >&2
  echo "bytecode 与引擎版本强绑定，请切换到与参考实现同源的 ref。" >&2
  exit 1
fi
echo "    VERSION 校验通过: $ACTUAL_VERSION"

echo "== [2/4] 编译 quickjs 静态库 =="
make -C "$WORK/quickjs" libquickjs.a -j "$(nproc 2>/dev/null || echo 4)"

echo "== [3/4] 编译 bridge shim =="
mkdir -p "$OUT_DIR"
SO_NAME="libquickjs_bridge.so"
"$CC" -O2 -fPIC -shared \
  -I "$WORK/quickjs" \
  -D_GNU_SOURCE \
  -DCONFIG_VERSION="\"$ACTUAL_VERSION\"" \
  -o "$OUT_DIR/$SO_NAME" \
  "$HERE/../bridge/quickjs_bridge.c" \
  "$WORK/quickjs/quickjs-libc.c" \
  "$WORK/quickjs/libquickjs.a" \
  -lm -lpthread -ldl

echo "== [4/4] 校验产物 =="
"$CC" --version | head -1
ls -la "$OUT_DIR/$SO_NAME"

cat <<EOF

构建完成: $OUT_DIR/$SO_NAME
本机验证:
  TVBOX_QJS_LIB=$OUT_DIR/$SO_NAME dart test --directory packages/tvbox_native
EOF
