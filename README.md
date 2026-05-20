# ss2022-shadowtls-manager

SS2022 + ShadowTLS v3 一键安装管理脚本，适用于 Debian / Ubuntu。

## 状态

当前版本：**v0.1.5-alpha**

仍在测试阶段，请先在干净的 Debian/Ubuntu 上验证后再用于生产。

## 功能特性

- 安装并管理 Shadowsocks 2022（基于 `shadowsocks-rust`）
- 可选启用 ShadowTLS v3（基于 `ihciah/shadow-tls`）
- systemd 服务管理（`ss2022.service` / `shadowtls.service`）
- IPv4 / IPv6 / 双栈监听
- 自动生成 SS2022 ss:// 链接、SS + ShadowTLS 合并链接（SIP002 plugin URI）
- 终端二维码显示（默认不保存 PNG，避免凭据落盘）
- sing-box / mihomo / Clash Meta / Shadowrocket / Surge 客户端配置模板
- BBR 一键启用
- 系统时间同步（systemd-timesyncd / chrony）
- 一键检查更新（管理脚本 / shadowsocks-rust / shadow-tls / 快捷命令）
- 一键完整卸载（仅删除本项目创建的文件，备份到 `/root/ss2022-shadowtls-backup-<日期>/`）
- 安装成功后自动创建 `/usr/local/bin/ss2022` 快捷命令
- **不动 nftables**：检测到 nftables 时只打印建议命令，不执行 `nft -f / flush / delete`

## 支持系统

- Debian 11 / 12
- Ubuntu 20.04 / 22.04 / 24.04
- 架构：amd64 / arm64

## 安装与使用

### 方式一：手动下载

```bash
curl -fSL -o /root/ss2022-shadowtls-manager.sh \
    https://你的分发地址/ss2022-shadowtls-manager.sh
chmod +x /root/ss2022-shadowtls-manager.sh
/root/ss2022-shadowtls-manager.sh
```

安装成功后会自动创建 `/usr/local/bin/ss2022` 快捷命令，以后直接：

```bash
ss2022
```

即可进入管理菜单。

### 方式二：GitHub 一行命令安装（Public 仓库可用）

> **注意：当前仓库如果是 Private，`raw.githubusercontent.com` 无法直接下载。**
> 一行命令安装只适用于 Public 仓库；Private 仓库请使用 `scp` 或 `git pull` 手动同步。

未来仓库 Public 后，推荐命令：

```bash
curl -fsSL https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/ss2022-shadowtls-manager.sh \
    -o /root/ss2022-shadowtls-manager.sh \
  && chmod +x /root/ss2022-shadowtls-manager.sh \
  && /root/ss2022-shadowtls-manager.sh
```

进一步简化（**后续版本计划**，本版本暂未提供 `install.sh`）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/install.sh)
```

### 一键检查更新

进入菜单后选 `7) 一键检查更新`：

- 同时检查管理脚本本体、`shadowsocks-rust`、`shadow-tls`、快捷命令
- 仅列状态表，**用户确认 `y` 后才应用更新**
- 管理脚本更新前会备份当前版本，下载后 `bash -n` 校验通过才会覆盖
- 仓库 Private 导致 raw 下载失败时，提示用 `scp` 或 `git pull` 手动更新，不报硬错

### 一键完整卸载

进入菜单后选 `8) 一键完整卸载`，输入 `YES` 二次确认：

- 自动备份当前配置到 `/root/ss2022-shadowtls-backup-<日期>/`
- 删除范围严格限本项目创建的内容：
  - `/usr/local/bin/ssserver`、`/usr/local/bin/shadow-tls`、`/usr/local/bin/ss2022`（仅含本项目标记的 wrapper）
  - `/etc/shadowsocks-rust/config.json`、`/etc/shadowtls/config.env`
  - `/etc/systemd/system/ss2022.service`、`/etc/systemd/system/shadowtls.service`
  - `/etc/ss2022-shadowtls-manager/`
  - `/etc/shadowsocks-rust/`、`/etc/shadowtls/`（仅当为空时）
- 不删 nftables 规则、`/etc/nftables.conf`、`nftables-nat-rust-enhanced`、`/usr/local/sbin/`、其它代理程序、apt 包

## 安全约束

本脚本与 `nftables-nat-rust-enhanced` 等其它 nftables 管理项目完全隔离：

- **禁止**：`nft flush ruleset` / `nft -f` / `nft delete`
- **禁止**：修改 `/etc/nftables.conf`
- **禁止**：覆盖 `/usr/local/sbin/` 下非本项目文件
- **禁止**：宽泛 `rm -rf /etc/*` 等

防火墙检测到 `nftables` 时仅打印建议命令，由用户自行决定是否执行。

## 常见问题

| 现象 | 排查路径 |
|---|---|
| `ssserver` 启动失败 | `journalctl -u ss2022 -n 80 --no-pager`；多为端口占用或 PSK 长度与方法不匹配 |
| `shadow-tls` 启动失败 | 检查 `/etc/shadowtls/config.env` 中 `SERVER_ADDR` 是否指向 SS2022 本机端口；`shadow-tls --help` 验证二进制 |
| IPv6 不通 | 确认 VPS 是否分配 IPv6；`cat /proc/sys/net/ipv6/bindv6only`；客户端网络是否双栈 |
| 二维码扫码失败 | 链接 > 300 字符时部分客户端无法扫；改用 sing-box / mihomo 手动配置 |
| 合并链接导入失败 | 用「查看节点信息 → 显示完整」中的 sing-box / mihomo 配置 |
| 时间同步异常 | 「网络与时间 → 自动校准时间」；NTP 不可用时可改用 chrony |

## 版本规划

- v0.1.x-alpha：内部测试，仅手动分发
- v0.2.x：第一个公开 release，配套 `install.sh` 一行安装
- v1.0.0：稳定版
