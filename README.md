# platina-droidspace-ksu

为 **Xiaomi Mi 8 Lite (platina)** 编译的自定义内核与可刷入 boot 镜像,内置以下能力:

- **Droidspace 容器支持**(完整内核配置)
- **UFW / Fail2ban 防火墙支持**(内核模块全部内置)
- **KernelSU**(内核级 root)

---

## 适用设备与 ROM

| 项目 | 说明 |
|---|---|
| 设备 | Xiaomi Mi 8 Lite(代号 platina,SDM660 平台) |
| ROM | Project Infinity X(Android 16 / 内核 4.19),官方发布帖见[链接](https://xdaforums.com/t/rom-unofficial-project-infinity-x-android-16-4-19-mi-8-lite-platina.4761644/) |
| 内核基线 | [sabarop/kernel_xiaomi_sdm660](https://github.com/sabarop/kernel_xiaomi_sdm660) 分支 `lineage-23.2-ksu`(Linux 4.19.325-cip133-st17),基线提交 `6ad212dfc` |
| 版本号 | `4.19.325-cip133-st17-perf`(与 ROM 官方内核一致的版本串,保证系统模块兼容) |

> 内核已实测:正常开机、日常使用稳定、Droidspace 需求检查全部通过。
> 本 boot 镜像未包含 Magisk 等第三方 root 补丁,root 统一由 **KernelSU** 提供。

---

## 文件清单

| 文件 | 用途 |
|---|---|
| `platina-droidspace-ksu-boot.img` | **刷入用 boot 镜像**(内核 + ROM 原版 ramdisk),绝大多数用户只需要这个 |
| `platina-droidspace-Image.gz-dtb` | 纯内核镜像(含 platina 设备树),供 AnyKernel3 或自行打包使用 |
| `kernel-package/` | 开发者用:重新编译所需的全部补丁、配置片段与脚本 |

---

## 刷入方法

**准备**:手机解锁 Bootloader,进入 fastboot 模式(关机后长按「电源 + 音量下」),
用数据线连接电脑,电脑需安装 [platform-tools](https://developer.android.com/tools/releases/platform-tools)。

```bash
# 1. 临时启动测试(推荐先用这个,不写入、可安全验证)
fastboot boot platina-droidspace-ksu-boot.img

# 2. 确认正常后,再决定是否永久刷入
fastboot flash boot platina-droidspace-ksu-boot.img
fastboot reboot
```

**回退**:将你的 ROM 原版 boot.img 重新刷回即可:

```bash
fastboot flash boot 原版boot.img
```

---

## 刷入后验证

1. **确认内核已生效**

   ```bash
   adb shell uname -r
   # 期望输出: 4.19.325-cip133-st17-perf
   ```

2. **配置 KernelSU 获取 root**

   - 安装 [KernelSU Manager](https://github.com/tiann/KernelSU/releases)。
   - 注意:本内核内置的 KernelSU 驱动版本为 **32334**,请使用与其匹配的 Manager 版本
     (v3.1.0 已验证可用;更高版本可能提示内核版本过低)。
   - 打开 Manager 完成初始化后:

   ```bash
   adb shell su -c id     # 期望输出含 uid=0(root)
   ```

3. **Droidspace 需求检查**

   打开 Droidspace App →「需求检查」,核心项目应全部为绿色通过。

4. **防火墙验证(容器内)**

   在容器(NAT 模式)内运行 `ufw status` 与 fail2ban,确认防火墙规则正常生效。

---

## 注意事项

- 本 ROM 原厂固件将 **Magisk** 集成在 boot ramdisk 与 `/product` 分区中。
  KernelSU 检测到 Magisk 存在时会自动禁用自身以避免冲突,因此:
  - 本镜像已改用 ROM **原版(未打补丁)ramdisk**,开机不再启动 Magisk 守护进程;
  - 请卸载 Magisk App(设置 → 应用 → 卸载,或 `adb uninstall com.topjohnwu.magisk`)。
- 刷机有风险,请自行备份数据;建议先 `fastboot boot` 临时验证再永久刷入。

---

## 更新记录

- **v1.0.1(推荐)** — 修复锁屏/灭屏后屏幕残留微弱亮光的问题
  (启用内核 WLED 背光驱动 `CONFIG_BACKLIGHT_QCOM_SPMI_WLED`,
  对应 ROM 内核中的 `CONFIG_LEDS_QPNP_WLED`),并同步更新了构建配置 `buildfix.config`。
- **v1.0.0** — 初版:完整 Droidspace + UFW/Fail2ban + KernelSU 支持。

---

## 开发者:重新编译

`kernel-package/` 内含编译所需的全部补丁、配置片段与脚本,在 sabarop 内核树上即可复现。

### 依赖

| 依赖 | 说明 |
|---|---|
| 内核源码 | `sabarop/kernel_xiaomi_sdm660` 分支 `lineage-23.2-ksu`,检出基线提交 `6ad212dfc` |
| 编译器 | AOSP 预编译 clang-r416183b(clang 12.0.5),[下载地址](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-release/clang-r416183b.tar.gz) |
| 其它 | GNU aarch64 binutils(汇编 / 链接) |

### 步骤

```bash
# 0) 准备内核树
git clone -b lineage-23.2-ksu https://github.com/sabarop/kernel_xiaomi_sdm660 ~/kernel_xiaomi_sdm660
cd ~/kernel_xiaomi_sdm660 && git checkout 6ad212dfc

# 1) 应用补丁、安装配置片段并合并(.config 基座默认使用 vendor/sdm660_defconfig;
#    如需 1:1 复现本镜像的版本串与模块兼容,请改用 kernel-package/rom-base.config 作基座)
bash <本仓库>/kernel-package/apply-droidspace.sh ~/kernel_xiaomi_sdm660 <本仓库>

# 2) 编译(clang 必须以命令行参数传入)
export ARCH=arm64
TC=~/toolchains/clang-r416183b/bin/clang
make -j16 O=out CC=$TC CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-

# 产物: out/arch/arm64/boot/Image.gz-dtb
```

`kernel-package/` 文件说明:

| 文件 | 说明 |
|---|---|
| `droidspace.config` | Droidspace + UFW/Fail2ban 配置片段 |
| `buildfix.config` | 编译与开机必需修正(如 RD_LZ4、PSI、MODULES、CONFIG_BUG 等) |
| `rom-base.config` | ROM 官方内核的完整 .config(取自设备 `/proc/config.gz`) |
| `0001-cgroup-noprefix-compat-links-4.19.patch` | Droidspaces 官方 cgroup 补丁(适配 4.19) |
| `0002-extract-cert-openssl3-compat.patch` | 兼容 host OpenSSL ≥ 3.5(无 `openssl/engine.h`) |
| `0003-mmap-lock-writeonce-buildfix.patch` | 修正内核源码中的 mmap_lock / WRITE_ONCE 兼容问题 |
| `apply-droidspace.sh` | 一键完成打补丁、安装片段、合并配置与校验 |
| `check-droidspace-config.sh` | 校验合并后的 `.config` 是否满足 Droidspace 要求 |
| `build-droidspace-kernel.sh` | 独立编译脚本 |

### 说明:对内核源码的适配改动

为使该内核能在现代编译环境(Fedora 等,OpenSSL ≥ 3.5、clang)下独立编译,
并在本项目 ROM 上稳定开机,对源码与配置做了少量必要适配,全部以补丁 / 配置片段
形式提供,内容与理由见各文件内注释。

---

## 致谢与来源

- 内核: [sabarop/kernel_xiaomi_sdm660](https://github.com/sabarop/kernel_xiaomi_sdm660)(`lineage-23.2-ksu`)
- ROM: [Project Infinity X (Android 16 / 4.19)](https://xdaforums.com/t/rom-unofficial-project-infinity-x-android-16-4-19-mi-8-lite-platina.4761644/)
- Droidspace: [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)
- KernelSU: [tiann/KernelSU](https://github.com/tiann/KernelSU)
- 本内核排障由 **DeepSeek** 协助完成

---

*仅供个人学习与测试使用,刷机风险自负。*
