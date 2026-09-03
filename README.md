# platina-droidspace-ksu

**Xiaomi Mi 8 Lite (platina) · Droidspace + UFW/Fail2ban + KernelSU 内核 boot 镜像**

基于 [sabarop/kernel_xiaomi_sdm660](https://github.com/sabarop/kernel_xiaomi_sdm660) 分支
**`lineage-23.2-ksu`**(Linux 4.19.325-cip133-st17),为 ROM **Project Infinity X
(Android 16)** 编译。已实测:正常开机、运行稳定、内核配置校验全绿。

> ⚠️ 刷机有风险,建议先 `fastboot boot` 临时测试。本镜像用 ROM **原版干净 ramdisk**
> (无 Magisk 补丁),root 由 **KernelSU(内核内置)** 提供。

## 文件说明

| 文件 | 说明 |
|---|---|
| `platina-droidspace-ksu-boot.img` | **刷入用 boot 镜像**(我们的内核 + ROM 原版干净 ramdisk,约 20.6MB) |
| `platina-droidspace-Image.gz-dtb` | 纯内核(内核 + 追加 `sdm660-mtp-platina.dtb`),供 AnyKernel3/自打包 |
| `kernel-package/` | 复现编译所需:配置片段(含 buildfix)、3 个补丁、apply/build/check 脚本 |

## 内核特性

- **Droidspace(容器)完整支持**:命名空间、cgroup 系列、OverlayFS、VETH/BRIDGE、
  netfilter/iptables/nftables、NAT/masquerade、多路由表、`USER_NS=y`、
  `ANDROID_PARANOID_NETWORK=n` 等(见 [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) 官方指南,已按 4.19 修正符号)
- **UFW / Fail2ban 防火墙**:xt_comment/state/conntrack/multiport/reject/LOG/recent/
  limit/hashlimit/owner/mark、IP_SET(hash:ip/net)、NFLOG/NETLINK_QUEUE 等全部内置 =y
- **KernelSU**(内置,`CONFIG_KSU=y`):配套 Manager 请用与内核驱动版本匹配的版本
  (本内核 KSU 驱动版本 **32334**,推荐 [KernelSU v3.1.0](https://github.com/tiann/KernelSU/releases) 或更新但版本兼容者)
- ROM 实机 .config 为基座:`CONFIG_LOCALVERSION="-perf"`、RD_LZ4、PSI、BUG、MODULES、
  VENDOR_HOOKS 等均已按"能开机 + 模块可加载 + lmkd 正常"校准(踩坑记录见 README §6)

## 刷入方法

```bash
# 方式 1: 临时启动测试(推荐先试,不写入)
fastboot boot platina-droidspace-ksu-boot.img

# 方式 2: 直接刷入 boot 分区(A-only 设备)
fastboot flash boot platina-droidspace-ksu-boot.img
fastboot reboot
```

刷入后验证:

```bash
adb shell uname -r            # 期望 4.19.325-cip133-st17-perf+
# 打开 KernelSU Manager(与内核 KSU 版本匹配)→ 授权
adb shell su -c id            # 期望 uid=0(root)
# Droidspaces App → 设置 → 需求检查 → 全绿
# 容器内(NAT 模式)跑 ufw status / fail2ban 验证防火墙
```

**回退**:刷回你 ROM 的原版 boot.img(`fastboot flash boot <原版boot.img>`)即可。

## 重新编译(可选)

```bash
# 0) 准备: ~/kernel_xiaomi_sdm660 (sabarop lineage-23.2-ksu) + AOSP clang-r416183b
# 1) 应用补丁+片段+合并(基座 vendor/sdm660_defconfig 或 ROM .config):
bash kernel-package/apply-droidspace.sh ~/kernel_xiaomi_sdm660 <本目录>
# 2) 编译(clang 必须写命令行):
cd ~/kernel_xiaomi_sdm660 && export ARCH=arm64
TC=~/toolchains/clang-r416183b/bin/clang
make -j16 O=out CC=$TC CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-
# 产物: out/arch/arm64/boot/Image.gz-dtb
```

## 为什么会有这些"修正"(踩坑记录)

`kernel-package/buildfix.config` 与三个补丁解决的是"让这棵树能独立编译 + 在
Project Infinity X 上正常开机运行"的实测问题,详见各文件注释:

1. **基座 defconfig**:必须用设备 SoC `vendor/sdm660_defconfig`(或 ROM 实机 .config),
   lineage 通用 arm64 defconfig 默认开 THP/KVM/MMU_NOTIFIER,而这棵 CAF 树代码不支持
   (mmap_sem/mmu_notifier 编译错误)。
2. **extract-cert / openssl3**(0002):Fedora 44 openssl 3.5 已删 `openssl/engine.h`;
   `CONFIG_SYSTEM_TRUSTED_KEYRING` 被 CFG80211 select 链锁死无法关,改为编译掉未用路径。
3. **mmap_lock / WRITE_ONCE**(0003):CAF 树改名不彻底(efi.c 旧成员)与 WRITE_ONCE
   语句/表达式混用,按上游 4.19 语义修正。
4. **RD_LZ4**:ROM ramdisk 为 LZ4,不开则卡开机 logo(实测)。
5. **PSI**:开 memcg(=y,Droidspace 要求)后 ROM 的 lmkd 因无 PSI 回退 v1 失败自杀,
   导致 system_server 连不上 lmkd → 开机慢/无响应(实测),开 `CONFIG_PSI=y` 解决。
6. **Magisk 冲突**:该 ROM 出厂 Magisk(ramdisk+product),会禁用 KernelSU;
   本镜像已改用 ROM **原版干净 ramdisk**,配合卸载 Magisk App 后 KSU 独占可用。

## 致谢

- [sabarop/kernel_xiaomi_sdm660](https://github.com/sabarop/kernel_xiaomi_sdm660)
- [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)
- [tiann/KernelSU](https://github.com/tiann/KernelSU)
