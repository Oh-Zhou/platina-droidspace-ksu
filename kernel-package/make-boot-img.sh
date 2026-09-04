#!/usr/bin/env bash
# ============================================================
# make-boot-img.sh — 用「ROM 原版 boot.img 的 ramdisk」+「新编内核 Image.gz-dtb」
#                    重打一个可直接 fastboot 刷入的 boot.img
#
# 用法:
#   bash make-boot-img.sh <ROM原版boot.img> <Image.gz-dtb> [输出boot.img]
#   例: bash make-boot-img.sh ~/pix_original_boot.img \
#          ~/kernel_out/arch/arm64/boot/Image.gz-dtb  platina-droidspace-ksu-boot.img
#
# 说明: boot.img(header v1) = 内核(Image.gz-dtb) + ramdisk。
#   ramdisk 是引导壳(/init 挂系统分区),保留 ROM 原版即可;内核换成我们的。
#   本脚本从「原版 boot.img」取出 ramdisk,替换内核后重打包,不改 ramdisk。
#   (原版 boot.img 可在 Project Infinity X ROM 原包中得到,见仓库 README 的 ROM 链接)
# ============================================================
set -euo pipefail

ORIG="${1:-}"
KERNEL="${2:-}"
OUT="${3:-platina-droidspace-ksu-boot.img}"
[ -f "$ORIG" ]   || { echo "错误: 找不到原版 boot.img: $ORIG" >&2; exit 1; }
[ -f "$KERNEL" ] || { echo "错误: 找不到内核 Image.gz-dtb: $KERNEL" >&2; exit 1; }

python3 - "$ORIG" "$KERNEL" "$OUT" <<'PY'
import struct, sys
orig = open(sys.argv[1], 'rb').read()
kernel = open(sys.argv[2], 'rb').read()
out_path = sys.argv[3]
if orig[:8] != b'ANDROID!':
    sys.exit(f"错误: {sys.argv[1]} 不是有效的 Android boot.img (magic 不符)")
hdr = orig[:4096]
page = struct.unpack_from('<I', hdr, 36)[0]
koff = page
roff = koff + ((struct.unpack_from('<I', hdr, 8)[0] + page - 1) // page) * page
rsize = struct.unpack_from('<I', hdr, 16)[0]
ramdisk = orig[roff:roff + rsize]
pad = lambda n: (4096 - n % 4096) % 4096
out = bytearray(hdr + kernel + b'\x00' * pad(len(kernel)) + ramdisk + b'\x00' * pad(len(ramdisk)))
struct.pack_into('<I', out, 8, len(kernel))
struct.pack_into('<I', out, 16, len(ramdisk))
open(out_path, 'wb').write(out)
print(f"-> {out_path}  ({len(out)/1048576:.1f} MiB)  kernel={len(kernel)} ramdisk={len(ramdisk)}")
PY
