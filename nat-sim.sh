#!/bin/bash
# NAT 模拟器 —— Linux network namespaces + iptables
# 用途：可视化 NAT/SNAT/MASQUERADE 的数据包"变脸"过程
# 拓扑：client(10.1.1.2) --[内网]--> router(10.1.1.1|10.2.2.1) --[外网/SNAT]--> server(10.2.2.2)
# 用法：sudo ./nat-sim.sh [start|stop|test|watch]
# 需 root 权限；macOS 无法直接运行（无 ip netns），用 WSL2/Colima/虚拟机

set -euo pipefail

CLIENT_NS="client"
ROUTER_NS="router"
SERVER_NS="server"

CLIENT_IP="10.1.1.2"
ROUTER_IN_IP="10.1.1.1"
ROUTER_OUT_IP="10.2.2.1"
SERVER_IP="10.2.2.2"

log() { printf "[*] %s\n" "$*"; }

cleanup() {
  log "清理旧命名空间..."
  for ns in "$CLIENT_NS" "$ROUTER_NS" "$SERVER_NS"; do
    ip netns del "$ns" 2>/dev/null || true
  done
}

setup() {
  cleanup

  log "创建 3 个 network namespace..."
  ip netns add "$CLIENT_NS"
  ip netns add "$ROUTER_NS"
  ip netns add "$SERVER_NS"

  log "veth pair #1: client<->router..."
  ip link add veth_cr type veth peer name veth_rc
  ip link set veth_cr netns "$CLIENT_NS"
  ip link set veth_rc netns "$ROUTER_NS"

  log "veth pair #2: router<->server..."
  ip link add veth_rs type veth peer name veth_sr
  ip link set veth_rs netns "$ROUTER_NS"
  ip link set veth_sr netns "$SERVER_NS"

  log "配置 client (${CLIENT_IP}/24)..."
  ip netns exec "$CLIENT_NS" ip addr add "${CLIENT_IP}/24" dev veth_cr
  ip netns exec "$CLIENT_NS" ip link set veth_cr up
  ip netns exec "$CLIENT_NS" ip link set lo up
  ip netns exec "$CLIENT_NS" ip route add default via "$ROUTER_IN_IP"

  log "配置 router (${ROUTER_IN_IP}/24 内网 | ${ROUTER_OUT_IP}/24 外网)..."
  ip netns exec "$ROUTER_NS" ip addr add "${ROUTER_IN_IP}/24" dev veth_rc
  ip netns exec "$ROUTER_NS" ip link set veth_rc up
  ip netns exec "$ROUTER_NS" ip addr add "${ROUTER_OUT_IP}/24" dev veth_rs
  ip netns exec "$ROUTER_NS" ip link set veth_rs up
  ip netns exec "$ROUTER_NS" ip link set lo up

  log "配置 server (${SERVER_IP}/24)..."
  ip netns exec "$SERVER_NS" ip addr add "${SERVER_IP}/24" dev veth_sr
  ip netns exec "$SERVER_NS" ip link set veth_sr up
  ip netns exec "$SERVER_NS" ip link set lo up
  ip netns exec "$SERVER_NS" ip route add default via "$ROUTER_OUT_IP"

  log "开启 IP forwarding..."
  ip netns exec "$ROUTER_NS" sysctl -w net.ipv4.ip_forward=1

  log "配置 SNAT (MASQUERADE) 在 router 外网口 veth_rs..."
  ip netns exec "$ROUTER_NS" iptables -t nat -A POSTROUTING \
    -o veth_rs -s 10.1.1.0/24 -j MASQUERADE

  log "配置 FORWARD 链允许双向转发..."
  ip netns exec "$ROUTER_NS" iptables -A FORWARD \
    -i veth_rc -o veth_rs -j ACCEPT
  ip netns exec "$ROUTER_NS" iptables -A FORWARD \
    -i veth_rs -o veth_rc -m state --state ESTABLISHED,RELATED -j ACCEPT

  cat <<EOF
========================================
NAT 拓扑已搭建完成
========================================

  [client]              [router]                    [server]
  10.1.1.2    <-----==>  10.1.1.1  |  10.2.2.1  <-----==>  10.2.2.2
                内网              NAT/SNAT               外网

关键观察点：
  · server 看到的 src 应为 10.2.2.1（router 外网口），
    而非真实的 10.1.1.2（client）
  · 回程包通过 NAT 表反向映射回 client
  · router 上 MASQUERADE 会为每个五元组分配临时外网端口
========================================
EOF
}

test_conn() {
  echo "========== 测试 1: client ping server =========="
  ip netns exec "$CLIENT_NS" ping -c 3 "$SERVER_IP" || echo "[!] ping 失败"

  echo ""
  echo "========== 测试 2: 查看 NAT 表项 =========="
  ip netns exec "$ROUTER_NS" iptables -t nat -L POSTROUTING -n -v --line-numbers

  echo ""
  echo "========== 测试 3: 在 server 侧抓包，观察变脸后 src =========="
  echo "[*] 预期：源 IP 是 ${ROUTER_OUT_IP} 而非 ${CLIENT_IP}"
  echo "[*] 命令: sudo ip netns exec ${SERVER_NS} tcpdump -ni veth_sr 'icmp or tcp or udp'"
}

watch_packets() {
  log "在 router 外网口抓包，看 NAT 前后变化（Ctrl+C 退出）"
  log "同时会在 client 里 ping 制造流量"
  ip netns exec "$ROUTER_NS" tcpdump -ni veth_rs 'icmp or tcp or udp' &
  TCPDUMP_PID=$!
  sleep 1
  ip netns exec "$CLIENT_NS" ping -c 3 "$SERVER_IP" >/dev/null 2>&1 || true
  wait $TCPDUMP_PID 2>/dev/null || true
}

stop() {
  cleanup
  log "清理完成"
}

case "${1:-start}" in
  start)  setup ;;
  stop|clean) stop ;;
  test)   test_conn ;;
  watch)  watch_packets ;;
  status) ip netns list; echo; ip netns exec "$ROUTER_NS" iptables -t nat -L -n -v 2>/dev/null || true ;;
  *)
    echo "用法: sudo $0 [start|stop|test|watch|status]"
    exit 1
    ;;
esac
