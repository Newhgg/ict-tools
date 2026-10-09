# 华为 ICT 网络构建大赛·数通方向：仿真→真机操作手册

> 依据：Sir 提问"华为 ICT 数通方向 思科模拟器后真机操作"。
> 前置阅读：`网络技术竞赛_赛前入门导读.md`（本目录，讲原理）。
> 本文专注**"从仿真到真机"的实操过渡**，覆盖工具切换、命令对照、真机接线、机试流程、常见坑。

---

## 一、先确认三件事（决定你走哪条路）

| 事项 | 答案 | 含义 |
|---|---|---|
| 比赛用哪家设备 | 华为 ICT 大赛 = **华为 VRP** | 必须切 eNSP，不能继续用思科 PT |
| 你现在练的是哪家 | 思科 Packet Tracer？还是已经切 eNSP？ | 决定过渡成本（见下） |
| 有没有真机 | 学校实验室 / 家里 / 无 | 无真机也可，eNSP 与真机命令 100% 一致 |

**结论**：无论你现在用哪家的模拟器，**最后一步一定是 eNSP**。因为华为真机 = VRP 命令行，eNSP 就是 VRP 的模拟器，两者一致；思科 PT 与华为差异很大，不能直接迁移。

---

## 二、思科 PT → 华为 eNSP 命令对照（必背表）

| 功能 | 思科 Packet Tracer | 华为 eNSP（VRP） |
|---|---|---|
| 进系统视图 | `enable` → `configure terminal` | `system-view` |
| 改设备名 | `hostname R1` | `sysname R1` |
| 建 VLAN | `vlan 10` | `vlan batch 10`（批量）或 `vlan 10` |
| 配端口为 access | `switchport mode access` | `port link-type access` |
| 端口归 VLAN | `switchport access vlan 10` | `port default vlan 10` |
| 配 trunk | `switchport mode trunk` | `port link-type trunk` |
| trunk 允许 VLAN | `switchport trunk allowed vlan 10,20` | `port trunk allow-pass vlan 10 20` |
| 配 IP | `ip address 10.0.0.1 255.255.255.0` | `ip address 10.0.0.1 24`（**华为用 /24，思科用点分**） |
| 单臂路由子接口 | `interface f0/0.10` + `encapsulation dot1Q 10` | `interface g0/0/0.10` + `dot1q termination vid 10` + `ip address ...` + `arp broadcast enable` |
| 启接口 | `no shutdown`（默认 shutdown） | **默认就是 up**，无需操作（华为特性，思科要手动开） |
| 保存配置 | `write` / `copy running-config startup-config` | `save force` / `save` |
| 看接口 IP | `show ip interface brief` | `display ip interface brief` |
| 看路由表 | `show ip route` | `display ip routing-table` |
| 看 VLAN | `show vlan brief` | `display vlan brief` |
| 看 MAC 表 | `show mac-address-table` | `display mac-address` |
| NAT 地址池 | `ip nat pool ...` | `ip pool-name ...` |
| 静态路由 | `ip route 0.0.0.0 0.0.0.0 10.0.0.1` | `ip route-static 0.0.0.0 0 10.0.0.1`（**多了 -static 和掩码写 0**） |
| 单臂路由关键差异 | 子接口 `encapsulation dot1Q 10` | **必须加 `arp broadcast enable`**（漏了跨 VLAN 不通，经典坑） |

**过渡心法**：把思科"动词式"（switchport mode access）改记成华为"属性式"（port link-type access）；思科"shutdown"概念在华为默认 up，不用管。

---

## 三、eNSP 安装与首次搭建（10 分钟）

### 1. 下载地址
- 华为开发者联盟官网 → 下载中心 → 工具软件 → **eNSP V100R005C20SPC500+**（最新稳定版）
- 备用源：华为支持页 https://support.huawei.com/enterprise/zh/download ，或让学长发安装包
- **依赖**：VirtualBox 6.1.x（**必须**这个版本，不能装 7.x，会不兼容）+ Wireshark 3.x

### 2. 安装顺序（顺序错了会启动失败）
1. 先装 VirtualBox 6.1（**不要用系统自带新版**）
2. 再装 eNSP
3. 启动 eNSP，第一次会自动拉起 VRPv8/v7 镜像下载（约 400MB，走华为 CDN，国内快）

### 3. 启动失败的三个常见原因
- **Hyper-V 冲突**：Win 10/11 默认开 Hyper-V，会抢 VT 虚拟化。关法：控制面板 → 程序 → 启用或关闭 Windows 功能 → 取消"Hyper-V"、"Windows 沙盒"、"虚拟机平台"，重启。
- **VirtualBox 版本不对**：装了 7.x → 卸干净换 6.1.x。
- **端口冲突**：eNSP 用 8080/9001-9004 端口，若被防火墙挡住会连接失败；改 eNSP 安装目录 `config` 下 `node_config.txt` 端口。

### 4. 第一张拓扑（验证环境 OK）
拖出：1 台 PC × 2 + 1 台 Access 交换机（S5700）→ 连线 → 双击 PC 配 IP（192.168.1.10/24 和 192.168.1.11/24）→ `ping` 测试 → 全通即环境 OK。

---

## 四、从仿真到真机：差异点清单（重点）

eNSP 与真机命令一致，但**操作体验**有 5 个差异：

| 差异点 | eNSP | 真机 | 应对 |
|---|---|---|---|
| **连接方式** | 双击设备图标弹终端 | SSH/Telnet/console 线 | 真机提前准备好 SSH 客户端（SecureCRT/PuTTY） |
| **console 波特率** | 无（直接弹） | 9600, 8N1（默认） | console 线接电脑串口，用 SecureCRT 配 9600 |
| **设备名/接口名** | 完全一致 | 完全一致 | 直接迁移配置脚本 |
| **保存配置** | `save force` 立即持久化 | `save` 会问 y/n | 真机记得 `save` 后按 y |
| **重启** | 右键设备 → 重启 | `reboot` 命令 | 真机 reboot 前**一定先 save** |
| **物理接口状态** | 拖线自动 link up | 需物理连好 + `undo shutdown` | 真机若接口 down，先查 `display interface` 看是否 shutdown |
| **时钟** | eNSP 用系统时钟 | 真机要手动设 `clock timezone` | 真机先设时间，否则日志/认证乱 |

**迁移流程**：
1. eNSP 里跑通整套拓扑，导出配置脚本（`display current-configuration` 复制出来）
2. 真机上逐行粘贴（或走 TFTP 批量导入，见第六节）
3. 逐台 `display current-configuration` 与 eNSP 脚本 diff，确认一致

---

## 五、华为数通必考技术栈（机试重点）

按大赛评分维度排优先级（**前 3 项占分 60%+**）：

### ① VLAN + Trunk（基础，必考）
`vlan batch` / `port link-type` / `port default vlan` / `port trunk allow-pass vlan` / `display vlan brief`

### ② 静态路由 + 单臂路由（核心）
`ip route-static` / `interface g0/0/0.10` + `dot1q termination vid 10` + `ip address` + `arp broadcast enable`
**坑**：漏 `arp broadcast enable` 是历届大赛最高频失分点。

### ③ OSPF 单区域/多区域（进阶，拉分）
`ospf 1 area 0` / `network 10.0.0.0 0.0.0.255` / `display ospf peer brief`
多区域要点：骨干区域 0、边界路由器配 `import-route`。

### ④ NAT（Easy IP / 地址池）
`ip pool-name pool1` / `section 0 202.1.1.10 202.1.1.50` / `interface g0/0/0` + `nat outbound` / `display nat session`

### ⑤ STP 生成树（防环路）
`stp mode rstp` / `stp root primary` / `stp edge-port` / `display stp brief`

### ⑥ 安全加固（易失分但分高）
- 端口安全：`port-security max-mac-num 2` + `port-security enable`
- AAA 认证：`aaa` + `local-user admin password ...` + `user privilege level 15`
- SSH 替代 Telnet：`public-key local import` + `user-interface vty 0 4` + `protocol inbound ssh`
- DHCP Snooping：`dhcp snooping enable` + `dhcp snooping trust`（防止私接 DHCP 服务器）

### ⑦ 路由聚合/等值路由（加分项）
`ip route-static 10.0.0.0 22 ...`（聚合三个 /24）/ `cost` 参数配等值。

---

## 六、真机现场操作流程（机试 60-90 分钟）

### 0. 进考场前 15 分钟（准备）
- 带：console 线（真机必备，学校若不提供自己备一条）+ 笔记本（预装 SecureCRT/PuTTY）
- 检查：笔记本能连教室 WiFi；eNSP 拓扑脚本存本地一份
- 心态：华为真机第一次接，别慌，命令和 eNSP 一样

### 1. 物理接线（3-5 分钟）
- PC ↔ 交换机：直通线（Cat5e/6）
- 交换机 ↔ 交换机：trunk 口（G0/0/24 或 G0/0/1）
- 交换机 ↔ 路由器：单臂路由（一根线，子接口切 VLAN）
- 路由器 ↔ 出口（模拟公网）：另一根线
- 拓扑照题，**先画草图再连线**，别边连边想

### 2. 上电初始化（2-3 分钟）
- 设备重启进 console → `<Huawei>`
- `system-view` → `sysname` → `display ip interface brief` 看接口
- 若接口 down：`interface g0/0/0` → `undo shutdown` → `quit`

### 3. 配置阶段（30-45 分钟，按下面顺序）
**顺序铁律**：先管理（sysname/接口IP）→ 再 VLAN → 再路由 → 最后安全。
**每配完一台**：`display current-configuration` 自检一遍，再 save。
**跨设备配置**：用 TFTP 批量导（若有 TFTP 服务器），否则逐台手敲。

### 4. 验证阶段（15 分钟）
按评分表逐项验证：
- `display ip interface brief` — 所有接口 up/up
- `display vlan brief` — VLAN 成员对
- `display mac-address` — MAC 表有
- `display ip routing-table` — 路由表有静态/OSPF
- `ping -c 4 <跨VLAN对端>` — 通了
- `ping -c 4 <公网模拟地址>` — NAT 通了
- `display nat session` — NAT 会话在

### 5. 收尾（3 分钟）
- `save` 保存（**必做**，不 save 重启白干）
- `display current-configuration` 存一份到本地（截图/复制）
- 提交答案：若要求提交配置脚本，把 `display current-configuration` 内容粘到答题模板

---

## 七、常见翻车点 TOP 10（历届大赛高频）

1. **漏 `arp broadcast enable`** — 单臂路由跨 VLAN 不通，100% 是它。
2. **掩码写成点分** — 华为写 `/24` 不是 `255.255.255.0`（配 IP 时）。
3. **静态路由忘写 0 作通配** — `ip route-static 0.0.0.0 0 ...` 不是 `0.0.0.0 0.0.0.0`。
4. **VLAN 口配成 trunk 接 PC** — 电脑端不识别 802.1Q 标签，ping 不通。
5. **access 口配 `port trunk allow-pass`** — 命令错，access 口用 `port default vlan`。
6. **没 `save`** — 重启白配。
7. **OSPF 区域写错** — 两台设备 area 号不一致导致邻居建立失败。
8. **NAT ACL 未 `apply acl`** — 定义了 ACL 没应用到接口，NAT 不生效。
9. **接口 shutdown** — 真机接口默认可能是 shutdown，忘 `undo shutdown`。
10. **VLAN ID 冲突** — 两台交换机 VLAN 号不统一，跨设备不通。

---

## 八、无真机也能练的三条路

如果你没条件接触真机，这三条路能把实操练到位：

1. **eNSP 全真模拟**：华为数通大赛 90% 考点 eNSP 都能复现，真机差异仅在"物理接线+console 波特率"。
2. **VRP Web UI（华为云实验平台）**：华为官方在线实验 https://huaweicloud.com/experiment/ ，免安装，浏览器直接练，部分付费。
3. **GNS3 + 华为 VRP 镜像**：进阶玩家用，性能比 eNSP 好，可跑 20+ 台设备不卡（需 Docker + 网络知识）。

**推荐路径**：D1-14 用 eNSP 跑完整 8 讲拓扑 → D15 找学长/老师要真机练 1-2 次（重点练接线+console+SSH）→ 大赛前一周纯 eNSP 复盘。

---

## 九、两周冲刺计划（每天 1-2h，衔接已有导读）

| 天 | 主题 | eNSP 任务 | 验收 |
|---|---|---|---|
| D1-2 | 环境 + 基础 | 装 eNSP，配 sysname、接口 IP，两台 PC 互通 | 环境 OK，命令手感建立 |
| D3-4 | VLAN 基础 | 3 台 PC 划 2 个 VLAN，验证隔离 | 同 VLAN 通、跨 VLAN 不通 |
| D5-6 | Trunk + 级联 | 2 台交换机 trunk 级联，跨交换机同 VLAN 互通 | `display vlan` 显示成员对 |
| D7-8 | 单臂路由 | 1 路由 + 1 交换机 + 2 VLAN 打通 | 跨 VLAN ping 通；故意漏 arp broadcast 复现坑 |
| D9-10 | 静态路由 + NAT | 内网 + 出口 + 公网模拟，NAT Easy IP | 内网 ping 通"公网"，`display nat session` 有会话 |
| D11-12 | OSPF 单区域 | 3 台路由器组网，收敛 | `display ospf peer brief` 全 Full |
| D13-14 | 综合 + 安全 | 校园网大题 + 端口安全 + SSH | 全部验收通过，能讲清每一步原理 |

---

## 十、待 Sir 确认

1. **比赛全称与主办方** — 是华为 ICT 大赛全国总决赛？还是学校选拔赛？（影响难度）
2. **真机型号** — S5700 / AR1220 / NE40 等，模型越新命令越新（V200R009+ 支持 IPv6 新特性）
3. **是否要补 IPv6** — 数通方向近年新增 IPv6 考点（`ipv6 address` / `ipv6 route`），如确认有，需加一节
4. **是否要补无线（WLAN）** — 若赛项含 AC+AP 组网，另开一个专题

---

*生成时间：2026-09-13*
*版本：v1.0 · 待确认信息见第十节*
