# platina-droidspace-ksu

**Xiaomi Mi 8 Lite (platina) · Droidspace + UFW/Fail2ban + KernelSU 内核 boot 镜像**

- 设备 ROM:**Project Infinity X (Android 16, 4.19)** — [XDA 原帖](https://xdaforums.com/t/rom-unofficial-project-infinity-x-android-16-4-19-mi-8-lite-platina.4761644/)
- 原始内核: **[sabarop/kernel_xiaomi_sdm660](https://github.com/sabarop/kernel_xiaomi_sdm660)** 分支 `lineage-23.2-ksu`
  (Linux 4.19.325-cip133-st17),**源自 sabarop 的内核,由 DeepSeek 协助构建**
- 已实测:正常开机、运行稳定、内核配置校验全绿。

> ⚠️ 刷机有风险,建议先 `fastboot boot` 临时测试。本镜像用 ROM **原版干净 ramdisk**
> (无 Magisk 补丁),root 由 **KernelSU(内核内置)** 提供。

> 📦 本仓库**不含完整内核源码树**(源码在 sabarop 仓库,体量过大);
> 上传的是**可复现全部改动的源**:`kernel-package/` 内的补丁 + 配置片段 + 脚本,
> 在 sabarop 树上执行 `kernel-package/apply-droidspace.sh` 即可一键重放。

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

## 重新编译(可选,构建所需文件都在本仓库)

`kernel-package/` 已包含构建所需全部文件(在 sabarop 内核树上使用):

| 文件 | 用途 |
|---|---|
| `droidspace.config` | Droidspace + UFW/Fail2ban 配置片段 |
| `buildfix.config` | 树编译/开机必需修正(RD_LZ4、PSI、MODULES、BUG、VENDOR_HOOKS、KSU…) |
| `rom-base.config` | **ROM 实机 .config**(自设备 `/proc/config.gz`,含 `-perf` localversion),作基座可 1:1 复现 |
| `0001-cgroup-noprefix-compat-links-4.19.patch` | 官方 cgroup noprefix 补丁(4.19 行号重制) |
| `0002-extract-cert-openssl3-compat.patch` | host openssl≥3.5 兼容 |
| `0003-mmap-lock-writeonce-buildfix.patch` | mmap_lock/WRITE_ONCE 源码修正 |
| `apply-droidspace.sh` | 一键:打补丁+装片段+合并配置+校验 |
| `build-droidspace-kernel.sh` / `check-droidspace-config.sh` | 编译与配置校验 |

**基线与工具链(验证用):**

- 内核基线: `sabarop/kernel_xiaomi_sdm660` 分支 `lineage-23.2-ksu`
  基线 commit `6ad212dfc`(在其上应用本仓库改动后编译)
- 编译器: AOSP 预编译 clang-r416183b (clang 12.0.5)
  https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-release/clang-r416183b.tar.gz
- GNU aarch64 binutils(汇编/链接),主机 Fedora 44 实测

**步骤:**

```bash
# 0) 克隆 sabarop 树并检出基线
git clone -b lineage-23.2-ksu https://github.com/sabarop/kernel_xiaomi_sdm660 ~/kernel_xiaomi_sdm660
# (建议 git checkout 6ad212dfc 保持与验证基线一致)

# 1) 应用补丁+片段+合并配置(默认基座 vendor/sdm660_defconfig;
#    想 1:1 复现本镜像则先 cp kernel-package/rom-base.config 为基座再 merge)
bash kernel-package/apply-droidspace.sh ~/kernel_xiaomi_sdm660 <本仓库目录>

# 2) 编译(clang 必须写命令行):
cd ~/kernel_xiaomi_sdm660 && export ARCH=arm64
TC=~/toolchains/clang-r416183b/bin/clang
make -j16 O=out CC=$TC CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-
# 产物: out/arch/arm64/boot/Image.gz-dtb
```

> 想 1:1 复现本镜像(含 `-perf` 版本串与 ROM 模块兼容),请用 `rom-base.config`
> 作 merge 第一项 + `droidspace.config` + `buildfix.config`,并设
> `CONFIG_LOCALVERSION="-perf"`(已含在 rom-base.config)。

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

- 设备 ROM: **Project Infinity X (Android 16)** — [XDA: Unofficial Project Infinity X Android 16/4.19 Mi 8 Lite (platina)](https://xdaforums.com/t/rom-unofficial-project-infinity-x-android-16-4-19-mi-8-lite-platina.4761644/)
- 原始内核: **[sabarop/kernel_xiaomi_sdm660](https://github.com/sabarop/kernel_xiaomi_sdm660)** (`lineage-23.2-ksu` 分支)
- Droidspace: [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)
- KernelSU: [tiann/KernelSU](https://github.com/tiann/KernelSU)

> 本内核源自 sabarop 的 lineage-23.2-ksu 内核;Droidspace/防火墙配置、编译修正、
> 刷机与排障(openssl3 / RD_LZ4 / PSI-lmkd / Magisk 冲突等)由 **DeepSeek AI 协助完成**。
