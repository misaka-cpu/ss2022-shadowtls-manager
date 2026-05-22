# ss2022-shadowtls-manager

SS2022 + ShadowTLS v3 一体化管理脚本，适用于 Debian / Ubuntu / CentOS 9 系列。

## 当前状态

- 当前版本：**v1.0.6**
- 状态：**稳定版**
- 已在 Debian / Ubuntu / CentOS 9 上经过实测；仍建议先在干净 Debian / Ubuntu / CentOS 测试后再用于长期环境

## 功能特点

1. **一键安装 / 管理 Shadowsocks 2022**：基于 `shadowsocks-rust`，systemd 托管
2. **可选启用 ShadowTLS v3**：基于 `ihciah/shadow-tls`，TCP 流伪装为 TLS 1.3 握手
3. **自动创建 `ss2022` 快捷命令**：安装成功后自动写入 `/usr/local/bin/ss2022`，并通过项目标记保护，绝不覆盖他人同名文件
4. **安装/启用完成直接显示完整文字链接**：只在终端输出推荐 ss:// / SS+ShadowTLS 合并链接，无需再去其它菜单，亦不渲染图像、不保存任何文件
5. **支持 IPv4 / IPv6 / 双栈**：URI 自动加 `[ ]`、`[::]:port` 监听拼接精确
6. **支持 sing-box / mihomo / Clash Meta / Shadowrocket / Surge 客户端配置输出**
7. **支持时间同步检查和校准**：`systemd-timesyncd` 优先；缺失 NTP 服务时提示手动安装命令，chrony 默认不自动安装（避免被慢速软件源阻塞）
8. **统一一键检查更新**：管理脚本本体 + `shadowsocks-rust` + `shadow-tls` + 快捷命令 wrapper 一表呈现，下载后 `bash -n` 校验通过才覆盖
9. **一键完整卸载**：严格停服 + 残留进程 TERM/KILL + 端口释放检测 + 备份到 `/root/ss2022-shadowtls-backup-<日期>/`，完成后显示详细总结
10. **安全边界**：
    - **不执行** `nft flush ruleset` / `nft -f` / `nft delete`
    - **不修改** `/etc/nftables.conf`
    - **不自动修改**现有 nftables 规则（检测到 nftables 时只打印建议命令）
    - **不修改** `nftables-nat-rust-enhanced` 项目
    - **不删除** `/usr/local/sbin/` 下任何非本项目文件
    - 删除任何项目内文件前均显示路径，整盘删除需用户输入 `YES` 二次确认

## 支持系统

- Debian 11 / 12
- Ubuntu 20.04 / 22.04 / 24.04
- CentOS / RHEL / Rocky / AlmaLinux 9 系列
- 架构：amd64 / arm64

> v1.0.x 已在 Debian 12、Ubuntu 24.04、CentOS 9 上实测；其它发行版/版本组合可能仍有差异，遇到问题请提 Issue 并附带 `lsb_release -a` 或 `cat /etc/os-release`，以及 `journalctl -u ss2022 -n 80 --no-pager`。

## 一行安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/install.sh)
```

`install.sh` 只做最小 bootstrap：
1. 检查 root + `curl` / `ca-certificates`
2. 下载主脚本到 `/tmp` 临时文件并执行 `bash -n` 校验
3. 备份旧版本并安装主脚本
4. 创建或更新本项目的 `ss2022` 快捷命令
5. `exec /root/ss2022-shadowtls-manager.sh` 直接进入交互菜单

> 仓库 Private 时 `raw.githubusercontent.com` 无法直接访问，请改用 `scp` 或 `git pull` 把 `ss2022-shadowtls-manager.sh` 同步到 `/root/`，然后 `chmod +x && /root/ss2022-shadowtls-manager.sh`。

## 备用安装命令（Public 仓库长格式）

```bash
curl -fsSL https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/ss2022-shadowtls-manager.sh \
    -o /root/ss2022-shadowtls-manager.sh \
  && chmod +x /root/ss2022-shadowtls-manager.sh \
  && /root/ss2022-shadowtls-manager.sh
```

## 快捷命令

SS2022 安装成功后，主脚本会自动创建：

```
/usr/local/bin/ss2022
```

包含以下标记，便于本项目识别归属（绝不覆盖同名非本项目文件）：

```
# managed by ss2022-shadowtls-manager
```

以后直接：

```bash
ss2022
```

即可进入管理菜单。

## 主菜单

```
SS2022 + ShadowTLS 管理脚本 v1.0.6
版本：v1.0.6   监听模式：dual   IPv4：x.x.x.x   IPv6：xxxx::xxxx
SS2022    ：已安装 / 运行中   端口：18388   模式：tcp_only
ShadowTLS ：已启用 / 运行中   端口：8443    伪装：www.bing.com
时间同步：已同步   快捷命令：ss2022
----------------------------------------------------------------
主菜单：
  1) 一键安装 / 重装
  2) 启用 / 配置 ShadowTLS
  3) 查看节点信息
  4) 服务管理
  5) 网络与时间
  6) 高级设置
  7) 一键检查更新
  8) 一键完整卸载
  0) 退出
```

## 一键检查更新

主菜单 → `7) 一键检查更新`：

- 同时检查 4 个组件：管理脚本本体、`shadowsocks-rust`、`shadow-tls`、`/usr/local/bin/ss2022` 快捷命令
- 仅列状态表，**用户确认 `y` 后才应用更新**
- 管理脚本更新前会备份当前版本，下载后 `bash -n` 校验通过才覆盖
- 二进制更新失败会自动从备份回滚到旧版本并校验服务恢复运行
- 仓库 Private 导致 raw 下载失败时，提示用 `scp` 或 `git pull` 手动更新，不报硬错

## 一键完整卸载

主菜单 → `8) 一键完整卸载`，输入 `YES` 二次确认。

**会做**：
- 自动备份当前配置到 `/root/ss2022-shadowtls-backup-<日期>/`
- 严格停服：`disable --now` 两个 unit → `daemon-reload` → `reset-failed` → 残留进程 TERM 2s 后 KILL
- 删除项目自有文件（含 `/usr/local/bin/ss2022` wrapper，前提是包含 `managed by ss2022-shadowtls-manager` 标记）
- 报告每个端口的释放状态；仍占用时区分"本项目残留"与"非本项目进程"，并附占用进程明细

**不会做**：
- 不动 nftables 规则与 `/etc/nftables.conf`
- 不动 `nftables-nat-rust-enhanced` 项目
- 不卸载 apt 包（curl / jq / chrony / wget 全部保留）
- 不删 ufw / firewalld 端口规则（提示用户自行检查）
- 不删 `${SYSCTL_CONF}`（BBR 配置）—— 提示用户自行清理
- 不删任何非本项目创建的文件

## 安全约束

本脚本与 `nftables-nat-rust-enhanced` 等其它 nftables 管理项目**完全隔离**：

| 类别 | 行为 |
|---|---|
| `nft flush ruleset` / `nft -f` / `nft delete` | **禁止**（静态扫描 0 处真实调用） |
| 修改 `/etc/nftables.conf` | **禁止** |
| 覆盖 `/usr/local/sbin/` 下非本项目文件 | **禁止** |
| 宽泛 `rm -rf` | **禁止**；所有 `rm` 走路径白名单 / 标记校验 / 项目常量比对 |

防火墙检测：识别到 `nftables` 时仅打印参考命令，绝不修改规则。`ufw` / `firewalld` 也**不会自动放行**——v1.0.3 起 `open_firewall_port` 会先输出手动命令并询问 `[y/N]` 默认 No；只有在用户明确输入 `y` 时才执行对应 `ufw allow` / `firewall-cmd --add-port`。安装流程默认零防火墙改动。

## 常见问题

| 现象 | 排查路径 |
|---|---|
| 一键完整卸载后端口仍被占用 | 卸载总结会区分"本项目残留"与"非本项目进程"，本项目残留会自动 TERM/KILL；非本项目进程请按列出的 `pid` / 进程名自行处理 |
| 重新安装同端口提示被占用 | 安装时若占用者是本项目残留进程，菜单会提示并询问是否清理；若是其它进程，请输入其它端口 |
| `ssserver` 启动失败 | `journalctl -u ss2022 -n 80 --no-pager`；多为端口占用或 PSK 长度与方法不匹配 |
| `shadow-tls` 启动失败 | 检查 `/etc/shadowtls/config.env` 中 `SERVER_ADDR` 是否指向 SS2022 本机端口；`shadow-tls --help` 验证二进制 |
| IPv6 不通 | 确认 VPS 是否分配 IPv6；`cat /proc/sys/net/ipv6/bindv6only`；客户端网络是否双栈 |
| 合并链接导入失败 | 主菜单「查看节点信息」中确认后查看 sing-box / mihomo 配置模板 |
| 时间同步异常 | 「网络与时间 → 自动校准时间」；systemd-timesyncd 不可用时可改用 chrony |
| GitHub API 限流导致无法检测最新版本 | 一键检查更新会自动回退到 `releases/latest` 302 跳转抓 tag；都失败时友好提示，旧版本不受影响 |

## 版本规划

- **v0.1.x-alpha**：内部测试 + 公开测试
- **v0.2.x-beta**：第一个 beta release，配套 `install.sh` 一行安装
- **v1.0.0**：稳定版，已在 Debian / Ubuntu / CentOS 9 上实测；一行安装自动建快捷命令、依赖安装多发行版超时、时间显示明确解释 UTC 偏移、一键完整卸载默认不备份、BBR 状态友好化
- **v1.0.1**：修复依赖安装在网络源慢时长时间卡住的体验问题——必需依赖批量安装并收紧超时（索引 60s / 安装 120s）、`qrencode` / `chrony` 改为可选不再默认阻塞、超时/失败给出软件源诊断与手动命令
- **v1.0.2**：修复 v1.0.1 残留逻辑漏洞——必需依赖安装失败 / 超时后脚本必定停止并返回菜单（绝不再输出"依赖检查完成"）、错误提示与软件源诊断改为短行分块、缺失命令以 `jq / xz/xzcat / dig/nslookup / ip / ss` 等用户可读形式列出；时间同步路径不再自动安装 chrony
- **v1.0.3**：彻底移除终端二维码渲染功能与对 `qrencode` 的依赖；安装 / 启用完成与「查看节点信息」均只输出完整文字链接 + 客户端配置模板。安装流程进一步轻量化：防火墙改为打印手动命令 + `[y/N]` 默认 No；BBR / 客户端模板大段输出 / 一键检查更新 / chrony 等可选功能全部不在安装路径中触发，仅在对应高级菜单按需调用
- **v1.0.4**：主脚本取消自动安装系统依赖，避免软件源慢导致主流程长时间卡住。缺少必需依赖时打印按发行版分组的手动安装命令并停止当前安装流程返回菜单，不再进入加密方式选择；`install.sh` 仍保留 curl / ca-certificates 的最小 bootstrap
- **v1.0.6**（当前）：优化缺依赖时的新手引导。缺少必需依赖时先询问是否自动安装，默认 No；只有输入 `y` 才按当前系统批量安装必需依赖，并在安装后二次检查。手动修复命令只显示当前系统对应的一行命令，自动安装失败或依赖仍缺失时不会继续进入 SS2022 安装流程
- **v1.0.x**：仅修复缺陷，不引入 breaking change

## 贡献 / 反馈

- Issue：欢迎提 bug 与改进建议，请附 OS / 版本号 / 复现步骤
- 测试清单见 [`TESTING.md`](./TESTING.md)
- 变更记录见 [`CHANGELOG.md`](./CHANGELOG.md)

## 许可

本仓库源代码遵循当前 LICENSE 文件（如无则视为暂未声明）。脚本所安装的上游组件遵循各自 LICENSE：

- [shadowsocks/shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust)
- [ihciah/shadow-tls](https://github.com/ihciah/shadow-tls)
