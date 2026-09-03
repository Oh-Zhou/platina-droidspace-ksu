#!/usr/bin/env bash
# ============================================================
# apply-droidspace.sh — 把 Droidspace 改动套到内核树上
# 用法:
#   bash apply-droidspace.sh <内核源码目录> [本交付目录]
#   例: bash apply-droidspace.sh ~/kernel_xiaomi_sdm660
#   (本交付目录缺省为脚本所在目录)
#
# 做什么:
#   1) 给 kernel/cgroup/cgroup.c 打上 "noprefix 前缀符号链接" 兼容补丁
#      (官方 02 补丁按本 4.19 行号重制; 打不上会自动用 python 兜底,
#       仍失败则跳过 —— 仅影响 cgroup noprefix 挂载兼容, 不致命)
#   2) 给 scripts/extract-cert.c 打 openssl3 兼容补丁 0002
#      (host openssl>=3.5 无 openssl/engine.h 时, 编译掉未使用的 ENGINE 路径;
#       CONFIG_SYSTEM_TRUSTED_KEYRING 被 CFG80211 select 链强制=y, 无法用片段关闭)
#   3) 把 droidspace.config / buildfix.config 安装到
#      arch/arm64/configs/vendor/ 下
#   4) 用 merge_config.sh 合并(基座必须是设备 SoC defconfig —— 不能用 lineage
#      通用 arm64 defconfig: 后者默认开 THP/KVM/MMU_NOTIFIER, 而本 CAF 4.19 树
#      代码形态不支持(报 mmap_sem / mmu_notifier_event), 见 README §2D):
#        vendor/sdm660_defconfig + sdm660-common + platina
#        + droidspace + buildfix(树编译必需修正, 见 README §2E)
#      并对最终 .config 做 Droidspace 配置校验
# ============================================================
set -u

KDIR="${1:-}"
REL="${2:-$(cd "$(dirname "$0")" && pwd)}"
if [ -z "$KDIR" ]; then
  echo "用法: bash apply-droidspace.sh <内核源码目录> [本交付目录]"
  exit 1
fi
if [ ! -d "$KDIR/kernel/cgroup" ]; then
  echo "错误: $KDIR 不是内核源码树(kernel/cgroup 不存在)"
  exit 1
fi
cd "$KDIR" || exit 1

PATCH="$REL/0001-cgroup-noprefix-compat-links-4.19.patch"
FRAG="$REL/droidspace.config"

echo "=== [1/4] cgroup 前缀兼容补丁 ==="
if grep -q "kernfs_create_link(cgrp->kn, name, kn)" kernel/cgroup/cgroup.c; then
  echo "  已应用过, 跳过。"
else
  if patch -p1 -l --forward < "$PATCH" > /tmp/ds_patch.log 2>&1; then
    echo "  patch -p1 应用成功。"
  elif python3 - <<'PYEOF' >> /tmp/ds_patch.log 2>&1
import re
p = 'kernel/cgroup/cgroup.c'
s = open(p, encoding='utf-8').read()
pat = re.compile(r'(spin_unlock_irq\(&cgroup_file_kn_lock\);\n\s*\}\n)(\n\s*return 0;\n\})')
ins = r'''\1
	if (cft->ss && (cgrp->root->flags & CGRP_ROOT_NOPREFIX) && !(cft->flags & CFTYPE_NO_PREFIX)) {
		snprintf(name, CGROUP_FILE_NAME_MAX, "%s.%s", cft->ss->name, cft->name);
		kernfs_create_link(cgrp->kn, name, kn);
	}
\2'''
new = pat.sub(ins, s, count=1)
if new == s:
    raise SystemExit('未找到插入锚点(cgroup_add_file 尾部)')
open(p, 'w', encoding='utf-8', newline='').write(new)
print('python 兜底插入成功')
PYEOF
  then
    echo "  python 兜底插入成功。"
  else
    echo "  [警告] 补丁未应用成功, 见 /tmp/ds_patch.log。"
    echo "         非致命: 仅影响 cgroup noprefix 挂载下的兼容文件, Droidspaces 仍可运行。"
  fi
fi

echo "=== [2/4] extract-cert openssl3 兼容补丁 ==="
if grep -q "OPENSSL_VERSION_NUMBER >= 0x30000000L" scripts/extract-cert.c; then
  echo "  已应用过, 跳过。"
else
  if patch -p1 -l --forward < "$REL/0002-extract-cert-openssl3-compat.patch" > /tmp/ds_patch2.log 2>&1; then
    echo "  patch -p1 应用成功。"
    echo "  (openssl>=3 时编译掉未使用的 ENGINE 路径; host openssl 3.5 无 engine.h 必需)"
  else
    echo "  [警告] 0002 补丁未应用, 见 /tmp/ds_patch2.log"
    echo "         若 host openssl>=3.5 将报 scripts/extract-cert.c: openssl/engine.h 缺失。"
  fi
fi

echo "=== [3/4] 安装 droidspace/buildfix 配置片段 ==="
mkdir -p arch/arm64/configs/vendor
cp -f "$FRAG" arch/arm64/configs/vendor/droidspace.config
cp -f "$REL/buildfix.config" arch/arm64/configs/vendor/buildfix.config
echo "  -> arch/arm64/configs/vendor/droidspace.config"
echo "  -> arch/arm64/configs/vendor/buildfix.config"

echo "=== [4/4] 合并配置并校验 ==="
OUT="${KERNEL_OUT:-$KDIR/out}"
mkdir -p "$OUT"

# 让 olddefconfig 能识别 CFI_CLANG 等依赖 clang 的符号(找不到 clang 时仅告警)
if command -v clang >/dev/null 2>&1; then
  export CC="$(command -v clang)"
elif [ -n "${CLANG_DIR:-}" ] && [ -x "$CLANG_DIR/bin/clang" ]; then
  export PATH="$CLANG_DIR/bin:$PATH"
  export CC="$CLANG_DIR/bin/clang"
else
  echo "  [警告] 未找到 clang: CFI_CLANG/部分符号可能被 olddefconfig 丢弃。"
  echo "         建议 export CLANG_DIR=... 后重跑, 或直接用 build-droidspace-kernel.sh。"
fi
export ARCH=arm64

scripts/kconfig/merge_config.sh -m -O "$OUT" \
  arch/arm64/configs/vendor/sdm660_defconfig \
  arch/arm64/configs/vendor/xiaomi/sdm660-common.config \
  arch/arm64/configs/vendor/xiaomi/platina.config \
  arch/arm64/configs/vendor/droidspace.config \
  arch/arm64/configs/vendor/buildfix.config 2>&1 | tail -n 25

echo
echo "--- 运行 olddefconfig 让 Kconfig 落定符号(合并输出提示 needs make) ---"
if make -s O="$OUT" ARCH=arm64 olddefconfig > /tmp/ds_olddef.log 2>&1; then
  echo "  olddefconfig OK (见 /tmp/ds_olddef.log 尾部:)"
  tail -n 8 /tmp/ds_olddef.log
else
  echo "  [警告] olddefconfig 失败, 见 /tmp/ds_olddef.log:"
  tail -n 15 /tmp/ds_olddef.log
  echo "  (常见原因: 未安装 clang/gcc 编译器。Fedora: sudo dnf install -y clang)"
fi

echo
echo "=== Droidspace 配置校验 ==="
bash "$REL/check-droidspace-config.sh" "$OUT/.config" || true

echo
echo "完成。合并结果: $OUT/.config"
echo "说明: 若只需配置+补丁(在 ROM 环境里编译), 到这里即可;"
echo "      若要独立编译内核, 接着运行: bash $REL/build-droidspace-kernel.sh $KDIR"
