# TESTING.md — 发布前手工测试清单

本清单覆盖 `ss2022-shadowtls-manager` 的安装、配置、卸载、菜单 UX、安全约束等关键路径。

**测试环境：** 干净的 Debian 11 / 12 或 Ubuntu 20.04 / 22.04 / 24.04 VPS，root 用户。
**不要在共享或生产环境直接跑这份清单**，建议用 KVM / LXC 临时机。

每项测试格式：
- ☐ 步骤描述
- 预期：……
- 不预期：……

---

## 0. 准备

- ☐ 系统语言不影响菜单（菜单和提示均中文，不会因 locale 异常出乱码）
- ☐ `bash -n ss2022-shadowtls-manager.sh` 通过
- ☐ `bash -n install.sh` 通过
- ☐ 仓库根目录存在：`ss2022-shadowtls-manager.sh`、`install.sh`、`README.md`、`CHANGELOG.md`、`TESTING.md`、`.github/workflows/syntax.yml`

---

## 1. 一行安装 install.sh

- ☐ 非 root 直接跑 `install.sh` → 提示 "请使用 root 用户运行：sudo -i" 并退出
- ☐ root 跑 `install.sh`，缺少 `curl` → 自动 `apt-get install -y curl ca-certificates`
- ☐ `install.sh` 下载主脚本到 `/tmp/ss2022-shadowtls-manager.sh.tmp.$$` → 跑 `bash -n` 通过 → 备份旧版本 → 安装到 `/root/ss2022-shadowtls-manager.sh` → `exec` 进入主菜单
- ☐ 故意制造下载失败（网络阻断 / 私有仓库）：旧版本不被覆盖；提示"如果仓库为 Private，请使用 scp 或 git pull 手动同步"
- ☐ `install.sh` 不写 `/usr/local/bin/ss2022`（快捷命令由主脚本 SS2022 安装成功后才创建）
- ☐ `install.sh` 不安装 systemd 服务、不动 nftables、不动防火墙

---

## 2. 主菜单与状态栏

- ☐ 首次进入主菜单显示 8 项 + 0 退出
- ☐ 状态栏 5 行：版本/监听模式/IPv4/IPv6 → SS2022 → ShadowTLS → 时间同步 + 快捷命令
- ☐ **未安装态**：SS2022 端口/模式显示 N/A；ShadowTLS 端口显示 N/A
- ☐ 快捷命令未安装时显示 "未安装"；本项目 wrapper 已安装显示 "ss2022"；存在同名非本项目文件显示 "冲突"
- ☐ 时间同步未配置时显示 "未检测"；已同步显示 "已同步"

---

## 3. 一键安装 SS2022

- ☐ 主菜单 1 → 选默认加密方式 → 输入端口 18388 → 自动生成密码 → mode `tcp_and_udp` → 监听模式 dual
- ☐ 安装完成后自动创建 `/usr/local/bin/ss2022` wrapper（包含 `managed by ss2022-shadowtls-manager` 标记）
- ☐ 安装完成后**直接显示**：`=== SS2022 安装完成 ===` + 完整加密方式/密码 + 推荐 SS2022 ss:// 链接 + **终端二维码**
- ☐ 显示前有醒目 `[警告]` "以下内容包含完整密码和二维码，请勿截图外传"
- ☐ 退出 ss2022 命令后再次输入 `ss2022` 能进入菜单
- ☐ 状态栏：SS2022 已安装 / 运行中 / 端口 18388 / 模式 tcp_and_udp
- ☐ `systemctl is-active ss2022.service` = active
- ☐ `ss -ltnp | grep ':18388 '` 看到 ssserver 占用

### 边界
- ☐ 自定义 PSK 留空 → 自动生成 24/44 字符 base64
- ☐ 自定义 PSK 输入"短字符串" → 校验失败 → 提示重输或留空
- ☐ 端口非法（如 0 / 70000）→ 提示重输
- ☐ 端口被**其它**进程占用 → 提示 "请输入其它端口"，不再"仍使用 [y/N]"
- ☐ 端口被**本项目 ssserver/shadow-tls 残留**占用 → 提示并询问 "是否清理本项目残留进程"

---

## 4. 启用 ShadowTLS v3

- ☐ 主菜单 2 → 启用 → 输入端口 8443 → 选伪装域名 1 (www.bing.com) → 自动生成 ShadowTLS 密码 → 自动切换 SS2022 为 tcp_only
- ☐ 启用完成后**直接显示**：`=== ShadowTLS v3 启用完成 ===` + 完整 SS2022/STLS 密码 + 推荐 SS+ShadowTLS 合并链接 + **终端二维码**
- ☐ 状态栏：ShadowTLS 已启用 / 运行中 / 端口 8443 / 伪装 www.bing.com
- ☐ `ss -ltnp | grep ':8443 '` 看到 shadow-tls 占用
- ☐ `ss -ltnp | grep '127.0.0.1:18388'` 看到 ssserver 仅本机监听
- ☐ `cat /etc/shadowtls/config.env` 显示 `SERVER_ADDR=127.0.0.1:18388`、`LISTEN_ADDR=[::]:8443`（dual 模式下）
- ☐ SS2022 密码 ≠ ShadowTLS 密码（脚本强制不变式）

### 边界
- ☐ 自定义伪装域名格式错误 → 提示重输
- ☐ TLS 1.3 检测失败 → 仅警告，不阻止安装
- ☐ SS2022 未安装时启用 ShadowTLS → 提示 "请先安装 SS2022"

---

## 5. 查看节点信息

- ☐ 主菜单 3 → 默认显示遮蔽信息：方法显示、密码 `abc***xyz`，ShadowTLS 启用时显示 "SS2022 本地后端：127.0.0.1:18388 (仅供排障)"
- ☐ 提示 "是否显示完整链接和二维码？...[y/N]"
- ☐ 用户 N → log_info 已取消，**不**显示完整信息
- ☐ 用户 Y → 显示推荐 URI + 终端二维码 + 客户端配置模板（sing-box / mihomo / Shadowrocket / Surge）
- ☐ ShadowTLS 启用时**只显示** "=== 推荐：SS2022 + ShadowTLS 合并链接 ===" 一段，不再有"普通 SS2022 ss:// 链接"
- ☐ ShadowTLS 未启用时**只显示** "=== 推荐：SS2022 ss:// 链接 ==="

---

## 6. 服务管理子菜单

- ☐ 主菜单 4 → 1) 重启全部服务（SS2022 启用时只重启 ss2022；ShadowTLS 也启用时两个都重启）
- ☐ 2) 查看服务状态：`systemctl status` 头部信息
- ☐ 3) 查看日志：进入 log_menu
  - ☐ 1/2 最近 100 行日志：`journalctl -u <unit> -n 100 --no-pager`，结束后按回车返回 log_menu
  - ☐ 3/4 实时跟踪：进入 `journalctl -f`，Ctrl+C **只**杀 journalctl 不退出脚本，回到 log_menu
  - ☐ 0 返回：直接回到服务管理菜单，**不需要**多按一次回车
- ☐ 4) 启动服务 / 5) 停止服务：相应 unit 状态变化
- ☐ 0 返回主菜单：直接回，**不需要**多按一次回车

---

## 7. 网络与时间子菜单

- ☐ 主菜单 5 → 1) 检测公网 IP：写入 info.json，状态栏立即更新
- ☐ 2) 设置服务器域名：可输入 / 留空清除
- ☐ 3) 设置监听模式：
  - ☐ 选 ipv4：监听 `0.0.0.0`
  - ☐ 选 ipv6 / dual 且未检测到公网 IPv6：**非阻塞**警告
  - ☐ 切换后 SS2022 / ShadowTLS（如启用）自动重启
- ☐ 4) 查看时间状态：显示本地时间 / UTC / 时区 / NTP / synchronized / RTC / 服务状态
- ☐ 5) 自动校准时间：执行前/后快照；若已同步 → log_ok "系统时间本来已经同步，所以时间显示可能不会明显变化"
- ☐ 6) 设置时区：
  - ☐ 选 0 → **直接返回**，不显示错误，不需要多按回车（v0.1.5 重点修复点）
  - ☐ 选 1-5 标准时区 → 显示修改前/后时区
  - ☐ 选 1 时若当前已是 Asia/Shanghai → 显示 "当前已经是该时区，无需修改"
  - ☐ 选 6 自定义留空 → 静默返回
  - ☐ 选 6 自定义非法字符串 → 显示 `timedatectl set-timezone` 的 stderr
- ☐ 0 返回主菜单：直接回，**不需要**多按一次回车

---

## 8. 高级设置子菜单

- ☐ 主菜单 6 → 1) 修改 SS2022 设置 → 4 项（端口/密码/方法/卸载 SS2022）
  - ☐ 修改端口：旧端口建议清理；新端口冲突走端口循环（含本项目残留检测）
  - ☐ 修改密码自动生成：与 ShadowTLS 密码必不同（不变式）
  - ☐ 修改加密方式：自动重新生成密码并保持与 ShadowTLS 不同
  - ☐ 单独卸载 SS2022：若 ShadowTLS 仍启用 → 3 选 1 依赖检查（推荐先卸 STLS / 同时卸 STLS / 取消）
- ☐ 2) 修改 ShadowTLS 设置 → 3 项（端口/密码/伪装域名）
  - ☐ 修改伪装域名：TLS 1.3 检测失败仅警告
  - ☐ 修改端口：旧端口非 0 且不等于新端口才提示清理（H2-G）
- ☐ 3) UDP / BBR 设置 → 3 项
  - ☐ 设置 UDP 模式：tcp_only / tcp_and_udp / udp_only
  - ☐ 启用 BBR：已是 `bbr+fq` → "BBR 已启用，无需重复设置"；首次启用 → 写 `/etc/sysctl.d/99-ss2022-shadowtls.conf` → `sysctl --system` → 校验
  - ☐ 查看系统优化状态：显示 cc/qd/BBR 状态/SYSCTL_CONF 路径
- ☐ 各子菜单 0 返回：直接回，**不需要**多按一次回车

---

## 9. 一键检查更新

- ☐ 主菜单 7：列 4 个组件状态表（管理脚本 / shadowsocks-rust / shadow-tls / 快捷命令）
- ☐ 无可用更新时：`log_ok "全部已是最新"`，直接返回
- ☐ 有可用更新时：`[y/N]` 确认；N → 不应用
- ☐ Y → 按顺序应用：管理脚本 → ssserver → shadow-tls → 快捷命令
- ☐ 管理脚本下载后必须 `bash -n` 校验通过才覆盖；失败 → 旧脚本不动 → 提示
- ☐ ssserver / shadow-tls 更新失败 → 自动回滚到旧二进制 → `is-active` 校验 → 仍失败时打印 `systemctl status` + `journalctl -n 80`
- ☐ Private 仓库时 raw 下载失败 → 提示 "如果仓库是 Private，请使用 scp 或 git pull 手动更新"，不报硬错
- ☐ GitHub API 限流时 → 自动回退到 `releases/latest` 302 跳转抓 tag

---

## 10. 一键完整卸载

执行前先：`ss -ltnp | grep -E ':18388|:8443'`、`systemctl status ss2022 shadowtls --no-pager`。

- ☐ 主菜单 8 → 显示删除清单（含 `/usr/local/bin/ss2022` "仅当包含标记时" 说明）
- ☐ 必须输入 `YES`（其它任何输入 → log_info 已取消）
- ☐ YES 后流程：备份 → `stop_project_services_strict`（disable --now → daemon-reload → reset-failed → 残留进程 TERM 2s → KILL）→ 删项目文件 → 删 `/usr/local/bin/ss2022`（必校验标记）→ 删 `PROJECT_ETC/` → rmdir `SS_DIR` / `STLS_DIR`（仅当空）→ daemon-reload + reset-failed → 端口释放检测
- ☐ 输出 `=== 一键完整卸载完成 ===` 总结表，含每项状态（服务/二进制/快捷命令/状态目录/3 个端口）+ 备份目录路径
- ☐ 仍被占用的端口附占用进程明细
- ☐ 卸载后退出脚本 → 再次进入：
  - 状态栏：SS2022 / ShadowTLS 均显示 "未安装"，端口 N/A，模式 N/A
  - 时间同步：仍可能显示 "已同步"（系统状态，非项目残留，**这是正常的**）
  - 快捷命令：显示 "未安装"
- ☐ `ss -ltnp | grep -E ':18388|:8443'` 应为空（除非有非本项目进程占用）

### 关键回归
- ☐ **卸载后立刻一键安装 SS2022 使用同一个端口 18388** → 不再提示 "端口已被占用"
- ☐ **卸载后立刻启用 ShadowTLS 使用同一个端口 8443** → 不再提示 "端口已被占用"

### 安全
- ☐ `/usr/local/bin/ss2022` 若提前手动创建为不带标记的同名脚本 → 卸载时**保留**该文件，明确提示 "不是本项目创建，保留"
- ☐ `/etc/nftables.conf` 卸载前后 `md5sum` 一致
- ☐ `/usr/local/sbin/` 下其它文件未被触碰
- ☐ apt 包 `curl jq qrencode chrony wget` 全部仍在

---

## 11. nftables / 防火墙隔离

- ☐ 卸载前后 `nft list ruleset | sha256sum` 一致（不动现有规则）
- ☐ 若系统装有 `nftables-nat-rust-enhanced` 之类项目，其 `/etc/nftables.conf` 与 `/usr/local/sbin/update-nft-ddns-forwards.sh` 卸载前后**字节级一致**
- ☐ 静态扫描脚本：`grep -nE 'nft (flush|-f|delete)' ss2022-shadowtls-manager.sh` 应**无任何输出**
- ☐ `grep -nE '/etc/nftables\.conf' ss2022-shadowtls-manager.sh` 仅出现在注释和卸载总结文案中

---

## 12. CI

- ☐ 推送到 main / master / v* 分支后，GitHub Actions `Syntax Check` 工作流通过
- ☐ `bash -n` 步骤通过两个 `.sh` 文件
- ☐ shellcheck 步骤即使有警告也**不会**让工作流失败（`continue-on-error: true`）

---

## 13. 文档完整性

- ☐ README 一行安装命令可被复制粘贴运行
- ☐ README 显示当前版本号与 SCRIPT_VERSION 常量一致
- ☐ CHANGELOG 包含从 v0.1.0 到当前版本的条目
- ☐ TESTING.md（本文件）与实际行为一致

---

## 14. 反馈模板（用户报 bug 时请附）

```
版本：v0.2.0-beta
系统：Debian 12 / Ubuntu 22.04 / ...
架构：x86_64 / aarch64

复现步骤：
1. ...
2. ...

预期行为：
...

实际行为：
...

附加信息：
- systemctl status ss2022 --no-pager
- systemctl status shadowtls --no-pager  
- journalctl -u ss2022 -n 80 --no-pager
- journalctl -u shadowtls -n 80 --no-pager
- ss -ltnp | grep -E ':<your_port>'
- cat /etc/ss2022-shadowtls-manager/info.json（密码字段请打码）
```
