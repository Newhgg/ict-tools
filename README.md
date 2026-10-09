# ICT Tools · 网络技术工具集

华为 ICT 大赛网络赛道学习工具 + 操作手册 + 知识笔记。

## 📦 内容

| 文件 | 说明 |
|---|---|
| nat-sim.sh | NAT/SNAT/MASQUERADE 模拟器（Linux network namespaces + iptables，3 节点拓扑） |
| nat_sim.py | NAT 模拟器 Python 版（可视化数据包流转） |
| NAT课程笔记.md | NAT 原理 + 配置 + 调试笔记 |
| 华为ICT大赛_数通方向_仿真到真机操作手册.md | 华为 ICT 大赛数通方向完整操作手册 |

## 🔌 NAT 模拟器

```bash
sudo ./nat-sim.sh start    # 启动拓扑
sudo ./nat-sim.sh watch    # 查看数据包
sudo ./nat-sim.sh stop     # 清理
```

**拓扑**：client(10.1.1.2) → router(10.1.1.1|10.2.2.1) → server(10.2.2.2)

**要求**：Linux（WSL2 / Colima / 虚拟机），macOS 需 WSL2。

## 📚 知识图谱

完整 ICT 知识图谱在线访问：
https://1234mac-studio.tail830780.ts.net/ict/

## 相关作品

- [AI Campus 三栋楼智能平台](https://newhgg.github.io/ai-campus/)
- [作品集主页](https://newhgg.github.io/)

---

MIT License · 2026 Newhgg
