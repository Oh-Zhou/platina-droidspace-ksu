#!/usr/bin/env bash
# ============================================================
# build-droidspace-kernel.sh — 在 WSL/Linux 中独立编译 platina Droidspace 内核
#
# 前置:
#   - 已克隆内核 (git clone --depth=1 -b lineage-23.2-ksu \
#       https://github.com/sabarop/kernel_xiaomi_sdm660 ~/kernel_xiaomi_sdm660)
#   - 工具链(clang 必备), 二选一:
#       A) GNU aarch64 binutils + clang (传统安卓方式, 推荐):
#            Fedora: sudo dnf install clang binutils-aarch64-linux-gnu
#            AOSP 预编译 clang: CLANG_DIR=$HOME/.../clang-rXXXXXX
#       B) 全套 LLVM (clang+lld+llvm-ar/objcopy...): 脚本自动走 LLVM=1
#
# 用法:
#   bash build-droidspace-kernel.sh [KDIR]
#   环境变量: KDIR OUT CLANG_DIR JOBS EXTRA_MAKE_ARGS
#
# 产物: $OUT/arch/arm64/boot/ 下的 Image.gz-dtb / Image (boot 打包用)
#       模块: $OUT/droidspace-modules/
# ============================================================
set -euo pipefail

KDIR="${KDIR:-${1:-$HOME/kernel_xiaomi_sdm660}}"
OUT="${OUT:-$KDIR/out}"
REL="$(cd "$(dirname "$0")" && pwd)"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

[ -d "$KDIR" ] || { echo "错误: 内核目录不存在: $KDIR"; exit 1; }

echo "=== 工具链检测 ==="
export ARCH=arm64

# 1) clang
if [ -n "${CLANG_DIR:-}" ]; then
  [ -x "$CLANG_DIR/bin/clang" ] || { echo "错误: $CLANG_DIR/bin/clang 不存在"; exit 1; }
  export PATH="$CLANG_DIR/bin:$PATH"
  CLANG_BIN="$CLANG_DIR/bin/clang"
elif command -v clang >/dev/null 2>&1; then
  CLANG_BIN="$(command -v clang)"
else
  echo "错误: 未找到 clang。"
  echo "  Fedora: sudo dnf install clang"
  echo "  或用 AOSP 预编译: CLANG_DIR=/path/to/clang-rXXXXXX bash $0"
  exit 1
fi
echo "  clang: $($CLANG_BIN --version | head -1)"

# 2) 链接/汇编/二进制工具: GNU aarch64 binutils 优先, 否则全套 LLVM
TOOLS_ARGS=()
if command -v aarch64-linux-gnu-objcopy >/dev/null 2>&1; then
  echo "  使用 GNU aarch64 binutils + clang (CROSS_COMPILE=aarch64-linux-gnu-)"
  TOOLS_ARGS=(CC="$CLANG_BIN" CLANG_TRIPLE=aarch64-linux-gnu- \
              CROSS_COMPILE=aarch64-linux-gnu-)
  if command -v ld.lld >/dev/null 2>&1; then
    TOOLS_ARGS+=(LD=ld.lld)
    echo "  + LD=ld.lld"
  fi
elif command -v ld.lld >/dev/null 2>&1 && command -v llvm-ar >/dev/null 2>&1 \
     && command -v llvm-objcopy >/dev/null 2>&1; then
  echo "  使用全套 LLVM (LLVM=1)"
  TOOLS_ARGS=(LLVM=1 CC="$CLANG_BIN")
else
  echo "错误: 既没有 aarch64-linux-gnu-* binutils, 也没有全套 LLVM 工具。"
  echo "  Fedora: sudo dnf install binutils-aarch64-linux-gnu  (推荐)"
  echo "  或:     sudo dnf install clang lld llvm"
  exit 1
fi

# 允许用户追加自定义 make 变量(例如 CFI 相关或 dtbo 选项)
read -r -a EXTRA <<< "${EXTRA_MAKE_ARGS:-}"

# ---------- 套用 Droidspace 改动(补丁+片段+合并配置) ----------
echo
echo "=== 套用补丁与配置片段 ==="
bash "$REL/apply-droidspace.sh" "$KDIR" "$REL"

# ---------- 编译 ----------
echo
echo "=== 编译 (jobs=$JOBS) ==="
cd "$KDIR"
mkdir -p "$OUT"
make -j"$JOBS" O="$OUT" "${TOOLS_ARGS[@]}" "${EXTRA[@]}" 2>&1 | tail -n 50

# ---------- 产物 ----------
echo
echo "=== 产物 ==="
BOOT="$OUT/arch/arm64/boot"
for f in Image.gz-dtb Image-dtb Image.gz Image; do
  if [ -f "$BOOT/$f" ]; then echo "  $BOOT/$f ($(du -h "$BOOT/$f" | cut -f1))"; fi
done

MODDIR="$OUT/droidspace-modules"
rm -rf "$MODDIR"
if make -j"$JOBS" O="$OUT" "${TOOLS_ARGS[@]}" "${EXTRA[@]}" \
     INSTALL_MOD_PATH="$MODDIR" modules_install >/dev/null 2>&1; then
  echo "  模块: $MODDIR"
else
  echo "  (modules_install 跳过/失败)"
fi

echo
echo "刷机提示:"
echo "  1) AnyKernel3: 把 Image.gz-dtb 放入 zip 的 Image.gz-dtb 位置后刷入;"
echo "  2) 或 fastboot boot <Image.gz-dtb> 临时启动测试;"
echo "  3) 或直接在 Project Infinity X 的 ROM 源码环境里用自带 build 流程编译"
echo "     (本目录改动已在树上, 正常 m/bootimage 即可)。"
