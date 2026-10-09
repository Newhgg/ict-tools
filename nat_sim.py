#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NAT 数据包"变脸"模拟器 —— 纯用户态，macOS/Linux 通用，无需 root
对应 9.22 晚课 4 个知识点：
  ① 翻译逻辑：五元组 → 转换表 → 改写
  ② 变脸全过程：出向 SNAT 改源 + 重算校验和；回向查表还原
  ③ 人为干预：静态端口映射(DNAT)、外网主动访问被拒
  ④ 模拟组网：3 台主机 + 1 台 NAT 网关的迷你互联网
运行：python3 nat_sim.py
"""


class Packet:
    """模拟一个 IP 报文（只保留课程关心的字段）"""

    def __init__(self, src, sport, dst, dport, proto="TCP", payload=""):
        self.src, self.sport = src, sport
        self.dst, self.dport = dst, dport
        self.proto = proto
        self.payload = payload

    def __str__(self):
        return f'{self.src}:{self.sport} -> {self.dst}:{self.dport} [{self.proto}] "{self.payload}"'


class NatGateway:
    """
    PAT（端口复用型 NAT，家用路由器同款）：
      出向：私网源 -> 公网源，端口改写并记表
      回向：按 (公网端口, 协议, 对端) 反查还原
      表项有老化时间（真实世界 UDP≈30s / TCP≈3600s）
    """

    def __init__(self, lan_ip, pub_ip):
        self.lan_ip = lan_ip            # 内网口 192.168.1.1
        self.pub_ip = pub_ip            # 公网口 203.0.113.1
        self.table = []                 # [内IP, 内端口, 公端口, 协议, 对端(ip,port), TTL]
        self.next_port = 40000
        self.port_map = {}              # 静态映射：(公IP,公端口,协议) -> (内IP,内端口)
        self.log = []

    # ---------- ① 出向：SNAT 变脸 ----------
    def outbound(self, p):
        if not p.src.startswith("192.168."):
            return p                     # 本来就在公网侧，不动
        self.next_port += 1
        pub_port = self.next_port
        self.table.append([p.src, p.sport, pub_port, p.proto, (p.dst, p.dport), 60])
        old = str(p)
        p.src, p.sport = self.pub_ip, pub_port
        self.log.append(f"[SNAT 改源]  {old}\n            =>  {p}")
        self.log.append("            （真实网关此处重算 IP/TCP 校验和，TTL-1 后发出）")
        return p

    # ---------- ② 回向：查表还原 / ③ 命中映射 / 丢弃 ----------
    def inbound(self, p):
        for e in self.table:
            if e[2] == p.dport and e[3] == p.proto and e[4] == (p.src, p.sport):
                old = str(p)
                p.dst, p.dport = e[0], e[1]
                e[5] = 60                # 有流量就续命
                self.log.append(f"[查表还原]  {old}\n            =>  {p}")
                return p
        key = (self.pub_ip, p.dport, p.proto)
        if key in self.port_map:         # 人为干预：网关上开的"洞"
            lan_ip, lan_port = self.port_map[key]
            old = str(p)
            p.dst, p.dport = lan_ip, lan_port
            self.log.append(f"[DNAT 映射]  {old}\n            =>  {p}   # 命中静态端口映射")
            return p
        self.log.append(f"[丢  弃]    {p}\n            # 表里没这项、又没开映射：外网进不来")
        return None

    # ---------- 表老化 ----------
    def tick(self):
        self.table = [e for e in self.table if e[5] > 1]
        for e in self.table:
            e[5] -= 1

    def dump_table(self, title="转换表"):
        print(f"  {title}（内IP       内端口  公端口  协议  对端              TTL）")
        if not self.table:
            print("  （空——所有表项已老化）")
        for e in self.table:
            print(f"  {e[0]:<11} {e[1]:<7} {e[2]:<7} {e[3]:<5} {str(e[4]):<17} {e[5]}")


def banner(t):
    print(f"\n{'=' * 64}\n{t}\n{'=' * 64}")


def demo():
    gw = NatGateway("192.168.1.1", "203.0.113.1")
    site = ("203.0.113.2", 80)
    pc1 = ("192.168.1.10", 50000)
    pc2 = ("192.168.1.11", 50000)
    nas = ("192.168.1.20", 22)

    banner("① PAT 端口复用：两台内网机共用一个公网 IP")
    out1 = gw.outbound(Packet(pc1[0], pc1[1], site[0], site[1], payload="GET / HTTP/1.1"))
    out2 = gw.outbound(Packet(pc2[0], pc2[1], site[0], site[1], payload="GET / HTTP/1.1"))
    gw.dump_table()
    print("  -> 私网源端口同为 50000，靠公网侧不同端口(40001/40002)区分会话")

    banner("② 回向变脸：外网回包，网关查表还原")
    for out in (out1, out2):
        gw.inbound(Packet(out.dst, out.dport, out.src, out.sport, payload="200 OK"))
    print("  -> 回包目的地址被还原成内网机，NAT 对通信双方透明")

    banner("③ 外网主动敲门：无表项 -> 丢弃（NAT 天然防火墙）")
    gw.inbound(Packet(site[0], site[1], gw.pub_ip, 50000, payload="端口扫描"))

    banner("④ 人为干预：在网关上开洞（静态端口映射 DNAT）")
    gw.port_map[(gw.pub_ip, 2222, "TCP")] = nas
    gw.inbound(Packet("1.2.3.4", 55555, gw.pub_ip, 2222, payload="SSH 握手"))
    print("  -> 外网打 203.0.113.1:2222，被转进内网 192.168.1.20:22")

    banner("⑤ 表项老化：没有流量续命 -> 超时删除 -> 连接失效")
    for _ in range(61):
        gw.tick()
    gw.dump_table()

    banner("网关处理日志（复看每一步变脸）")
    for line in gw.log:
        print("  " + line)


if __name__ == "__main__":
    demo()
