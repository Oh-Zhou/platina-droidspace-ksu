#!/usr/bin/env bash
# ============================================================
# check-droidspace-config.sh — 校验合并后的 .config 是否满足 Droidspace 要求
# 用法: bash check-droidspace-config.sh <path/to/.config>
#
# 说明: 按 4.19 实际 Kconfig 做了符号名映射(文档符号 -> 本树符号)
#   NETFILTER_XT_TARGET_MASQUERADE -> IP_NF_TARGET_MASQUERADE
#   NETFILTER_XT_TARGET_REJECT    -> IP_NF_TARGET_REJECT
#   NF_CONNTRACK_NETLINK          -> NF_CT_NETLINK
#   NF_CONNTRACK_IPV4             -> 已并入 NF_CONNTRACK (放行)
#   NF_NAT_REDIRECT               -> 由 NETFILTER_XT_TARGET_REDIRECT select
#   FW_LOADER_COMPRESS / IP_NF_TARGET_ULOG -> 本树 Kconfig 无此符号(放行)
#
# 返回码: 0 = 核心/网络组全部满足; 1 = 存在缺失
# ============================================================
set -u
CFG="${1:?用法: bash check-droidspace-config.sh <path/to/.config>}"
[ -f "$CFG" ] || { echo "找不到 $CFG"; exit 2; }

get() { grep -E "^CONFIG_$1=" "$CFG" | tail -n1 | cut -d= -f2; }

# 数组条目格式: 符号[,替代符号|,M]   (M = 本树无此符号, 放行)
# 核心/网络组(必须满足)
CORE=(
  SYSCTL SYSVIPC POSIX_MQUEUE NAMESPACES PID_NS UTS_NS IPC_NS NET_NS
  SECCOMP SECCOMP_FILTER CGROUPS CGROUP_DEVICE CGROUP_PIDS MEMCG
  CGROUP_SCHED FAIR_GROUP_SCHED CGROUP_FREEZER CGROUP_NET_PRIO DEVTMPFS
  OVERLAY_FS TMPFS_POSIX_ACL TMPFS_XATTR FW_LOADER FW_LOADER_USER_HELPER
  FW_LOADER_COMPRESS,M
  VETH BRIDGE NETFILTER BRIDGE_NETFILTER NETFILTER_ADVANCED
  NF_CONNTRACK IP_NF_IPTABLES IP_NF_FILTER NF_NAT NF_TABLES
  IP_NF_TARGET_MASQUERADE
  NETFILTER_XT_TARGET_MASQUERADE,IP_NF_TARGET_MASQUERADE
  NETFILTER_XT_TARGET_TCPMSS NETFILTER_XT_MATCH_ADDRTYPE
  NF_CONNTRACK_NETLINK,NF_CT_NETLINK
  NF_NAT_REDIRECT,NETFILTER_XT_TARGET_REDIRECT
  IP_ADVANCED_ROUTER IP_MULTIPLE_TABLES
  NF_CONNTRACK_IPV4,M
  NF_NAT_IPV4 IP_NF_NAT IP6_NF_IPTABLES USER_NS
)

# 防火墙组(UFW/Fail2ban; 缺失仅告警)
FW=(
  NETFILTER_XT_MATCH_COMMENT NETFILTER_XT_MATCH_STATE
  NETFILTER_XT_MATCH_CONNTRACK NETFILTER_XT_MATCH_MULTIPORT
  NETFILTER_XT_MATCH_HL
  NETFILTER_XT_TARGET_REJECT,IP_NF_TARGET_REJECT
  IP_NF_TARGET_REJECT NETFILTER_XT_TARGET_LOG
  NETFILTER_XT_MATCH_RECENT NETFILTER_XT_MATCH_LIMIT
  NETFILTER_XT_MATCH_HASHLIMIT NETFILTER_XT_MATCH_OWNER
  NETFILTER_XT_MATCH_PKTTYPE NETFILTER_XT_MATCH_MARK
  NETFILTER_XT_TARGET_MARK IP_SET IP_SET_HASH_IP IP_SET_HASH_NET
  NETFILTER_XT_SET NETFILTER_NETLINK_QUEUE NETFILTER_NETLINK_LOG
  NETFILTER_XT_TARGET_NFLOG
  IP_NF_TARGET_ULOG,M
)

check_one() { # entry strict(0=必须/1=告警)
  local entry="$1" strict="$2"
  local name rest alt allow v
  name="${entry%%,*}"
  rest="${entry#*,}"
  alt=""; allow=0
  if [ "$rest" != "$entry" ]; then
    if [ "$rest" = "M" ]; then allow=1; else alt="$rest"; fi
  fi
  v="$(get "$name")"
  if [ "$v" = "y" ]; then
    echo "  OK    $name=y"
    return 0
  fi
  if [ -n "$alt" ]; then
    local av; av="$(get "$alt")"
    if [ "$av" = "y" ]; then
      echo "  OK    $name (由 $alt=y 提供)"
      return 0
    fi
  fi
  if [ "$allow" = "1" ]; then
    echo "  -     $name 本树无此符号/无需显式设置(可接受)"
    return 0
  fi
  if [ "$strict" = "0" ]; then
    echo "  FAIL  $name -> '${v:-未设置}' (期望 =y)"
    return 1
  else
    echo "  WARN  $name -> '${v:-未设置}' (期望 =y)"
    return 0
  fi
}

rc=0
echo "--- 核心/网络组(必须满足) ---"
for e in "${CORE[@]}"; do check_one "$e" 0 || rc=1; done

v="$(get ANDROID_PARANOID_NETWORK)"
if [ -z "$v" ] || [ "$v" = "n" ]; then
  echo "  OK    ANDROID_PARANOID_NETWORK 已关闭"
else
  echo "  FAIL  ANDROID_PARANOID_NETWORK=$v (期望 n)"
  rc=1
fi

echo "--- 防火墙组(UFW/Fail2ban; 告警级) ---"
for e in "${FW[@]}"; do check_one "$e" 1 || true; done

echo
if [ "$rc" -eq 0 ]; then
  echo "结果: 核心/网络组全部满足 ✔"
else
  echo "结果: 存在缺失项 ✘ (见上方 FAIL)"
fi
exit "$rc"
