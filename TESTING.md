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

- ☐ 非 root 直接跑 `install.sh` → 提示 `需要 root 用户运行。` 与 `sudo -i`，然后退出
- ☐ root 跑 `install.sh` → 打印 `== SS2022 + ShadowTLS Installer ==`，随后以 `[1/4] 检查依赖` 开始 bootstrap；缺依赖时打印短行块：
  - ☐ `正在安装缺失依赖...`
  - ☐ `日志：`
  - ☐ `/tmp/ss2022-bootstrap-deps-install.$$.log` 单独一行显示
- ☐ **(Unreleased)** 干净 Debian/Ubuntu：`install.sh` 自动安装 `ca-certificates curl jq xz-utils iproute2 dnsutils`（索引 30s 超时 / 安装 90s 超时；apt/dpkg 原始输出写入 bootstrap 日志，不刷屏）
- ☐ **(v1.0.16)** CentOS/RHEL：`install.sh` 自动安装 `ca-certificates curl jq xz iproute bind-utils`
- ☐ **(v1.0.19)** 安装后二次检查 `curl` / `jq` / `xz·xzcat` / `ip·ss` / `dig·nslookup` 全部可用 → 打印 `依赖检查完成。`，或在包管理器返回异常但命令可用时打印 `依赖已满足。` + `继续。` + 单独日志路径 → 继续下载主脚本并进入菜单
- ☐ **(v1.0.19)** 二次检查仍缺依赖：打印 `依赖安装失败，仍缺少：` + 缺失项 + `日志最后 30 行：`（`tail -30`）+ 当前系统手动命令 → `exit 1`，不进入菜单
- ☐ `install.sh` 下载主脚本到 `/tmp/ss2022-shadowtls-manager.sh.tmp.$$` → 跑 `bash -n` 通过 → 备份旧版本 → 安装到 `/root/ss2022-shadowtls-manager.sh` → `exec` 进入主菜单
- ☐ 故意制造下载失败（网络阻断 / 私有仓库）：旧版本不被覆盖；提示"如果仓库为 Private，请使用 scp 或 git pull 手动同步"
- ☐ `install.sh` 创建或更新本项目 `/usr/local/bin/ss2022` wrapper；已存在但缺少本项目标记时不覆盖
- ☐ `install.sh` 不安装 systemd 服务、不动 nftables、不动防火墙
- ☐ **(v1.0.16)** `install.sh` 不安装 `qrencode` / BBR / 防火墙 / nftables，不启动 `ss2022.service`，只准备脚本运行环境
- ☐ **(v1.0.20)** bootstrap 依赖完成后、下载主脚本前，`install.sh` 以 `[2/4] 检查时间同步` 检测 NTP 服务；已有 `systemd-timesyncd` / `chrony` / `chronyd` 时块状显示已检测到的 `.service`
- ☐ **(v1.0.20)** 干净新机器无 NTP 服务时运行一行安装：
  - ☐ 不询问是否安装 chrony
  - ☐ 不执行 apt/dnf/yum 安装 chrony
  - ☐ 不执行 `systemctl enable --now chrony` / `systemctl enable --now chronyd`
  - ☐ 不生成 `/tmp/ss2022-bootstrap-chrony-install.$$.log`
  - ☐ 只显示 `未检测到 NTP 服务。`、时间敏感说明、手动安装 chrony 命令和菜单内查看路径
  - ☐ 继续进入菜单，不因缺少 NTP 服务退出或阻塞
- ☐ **(v1.0.20)** 第二次运行一行安装时，NTP 检查显示路径不应与第一次有明显显示差异；不能依赖第二次已有 chrony / 状态变化来绕过首次路径
- ☐ **(v1.0.20)** `install.sh` 首次安装路径输出必须固定左对齐，不使用居中、多列、动态宽度或补空格排版
- ☐ **(v1.0.19)** 新机器一行安装时，依赖安装提示不应横向错位
- ☐ **(Unreleased)** 依赖安装分别显示“刷新软件源”和“安装依赖”的最长等待；运行超过 10 秒时每 10 秒显示一次已等待时间，命令结束后不应被心跳额外延迟
- ☐ **(Unreleased)** 模拟包管理器执行 `stty -onlcr` 后，`install.sh` 必须恢复依赖安装前的终端状态，后续阶段和主菜单仍固定左对齐
- ☐ **(v1.0.20)** chrony 手动提示不应出现长行错乱
- ☐ **(v1.0.19)** apt/dnf/yum 原始输出仍写入日志，不刷屏
- ☐ **(v1.0.19)** 进入菜单前显示：
  - ☐ `------------------------------------------------------------`
  - ☐ `准备完成，正在打开 ss2022 菜单...`
  - ☐ `------------------------------------------------------------`
- ☐ 软件源不可用情景：手动让 apt/dnf 阻塞 → 总等待应 ≤ 30 + 90 + 10 = 130 秒（含两次强制结束宽限）；失败时显示日志路径、最后 30 行和手动修复命令

---

## 2. 主菜单与状态栏

- ☐ 首次进入主菜单显示 8 项 + 0 退出
- ☐ **(v1.0.19)** 80 列 SSH 终端显示主菜单：标题、状态栏、菜单项均固定左对齐，不分散到屏幕各处
- ☐ **(v1.0.19)** 100/120 列 SSH 终端显示主菜单：不居中、不多列、不根据终端宽度改变布局
- ☐ **(v1.0.19)** 主菜单项必须单列左对齐，输入提示单独一行显示 `请输入选项:`
- ☐ **(v1.0.19)** 主菜单分隔线固定为 `------------------------------------------------------------`
- ☐ 状态栏按左对齐短行显示：版本/监听模式、IPv4、IPv6、SS2022、ShadowTLS、时间同步 + 快捷命令
- ☐ **未安装态**：SS2022 端口/模式显示 N/A；ShadowTLS 端口显示 N/A
- ☐ 快捷命令未安装时显示 "未安装"；本项目 wrapper 已安装显示 "ss2022"；存在同名非本项目文件显示 "冲突"
- ☐ 时间同步未配置时显示 "未检测"；已同步显示 "已同步"
- ☐ **(v1.0.19)** 服务管理 / 网络与时间 / 高级设置子菜单显示为固定左对齐文本
- ☐ **(v1.0.19)** 查看日志 / UDP / BBR 设置 / 修改 SS2022 设置 / 修改 ShadowTLS 设置 / 设置时区菜单显示为固定左对齐文本
- ☐ **(v1.0.19)** 查看节点信息确认、一键检查更新确认、一键完整卸载确认界面不使用居中、多列或动态宽度排版
- ☐ **(v1.0.19)** `grep -nE 'tput cols|COLUMNS|center|居中|printf "%\*|printf "%-' ss2022-shadowtls-manager.sh install.sh` 应无输出

---

## 2.5 依赖检查（菜单内仅检查，不执行包管理器）

- ☐ 必需命令齐全时：依赖阶段只打印 `>>> 检查基础依赖` + `[成功] 必需依赖已满足`，零等待，立即进入加密方式选择
- ☐ **(v1.0.16 关键)** 必需依赖缺失（如未安装 `jq` / `xz` / `dig` 任一）时直接运行主脚本：
  - ☐ `[错误] 缺少必需依赖，无法继续安装 SS2022。`
  - ☐ 块状输出 `缺失项：`，逐行列出 `  - jq` / `  - xz/xzcat` / `  - dig/nslookup` 等可读标签，块内不重复 `[错误]`
  - ☐ **绝不**出现 `是否现在尝试自动安装缺失依赖？[y/N]:` 询问，也不触发任何 apt/dnf/yum
  - ☐ 块状输出 `推荐修复方式：`，包含「方式一：重新运行一行安装命令」（带 `install.sh` 一行命令，交由 bootstrap 自动修复）与「方式二：手动安装依赖」
  - ☐ Debian/Ubuntu 只显示 apt 修复命令
  - ☐ CentOS/RHEL 只显示 dnf / yum 修复命令
  - ☐ 系统未知时才同时显示 Debian/Ubuntu 与 CentOS/RHEL 两套命令
  - ☐ 末尾提示 `修复后重新运行：ss2022`
  - ☐ 缺依赖后**绝不**进入 "请选择 SS2022 加密方式"；主流程立即终止并返回菜单
- ☐ **(v1.0.16)** 菜单内不再执行任何包管理器：`grep -nE "apt-get install|apt-get update|dnf install|dnf makecache|yum install|yum makecache" ss2022-shadowtls-manager.sh` 命中项仅出现在提示文案中（含「自动校准时间」缺少 NTP 服务时的手动安装命令）；依赖检查与时间同步路径均零 apt/dnf/yum 执行
- ☐ **(v1.0.16)** `grep -nE "是否现在尝试自动安装缺失依赖|自动安装必需依赖|ss2022-deps-install" ss2022-shadowtls-manager.sh` 应无输出
- ☐ **(v1.0.16)** "请选择 SS2022 加密方式" 前不再出现 apt/dpkg 输出，菜单界面保持干净
- ☐ **(v1.0.16)** 依赖自动安装改由 `install.sh` bootstrap 阶段负责（见「1. 一行安装 install.sh」）；干净 Debian 一行安装进入菜单后选择一键安装 SS2022，不应再触发 apt/dnf/yum
- ☐ `qrencode` / `chrony` 不在 SS2022 安装流程中处理；时间同步未配置时「自动校准时间」只打印手动安装命令并返回菜单，**(v1.0.20)** 不再询问是否安装 chrony、不执行 apt/dnf/yum

## 2.6 网络与时间：自动校准时间（v1.0.20）

- ☐ **(v1.0.20 关键)** `timedatectl status` 显示 `NTP service: n/a`（系统无任何 NTP 服务）时执行「网络与时间 → 自动校准时间」：
  - 预期：先以简洁块状输出显示本地时间、UTC 时间、当前时区、时区偏移、NTP 功能、NTP 服务和同步结果
  - 不预期：默认输出 `--- timedatectl status 原始输出 ---` 或 raw `timedatectl status`
  - 预期：块状提示 `当前系统没有可用 NTP 服务。` 与 `timedatectl 显示 NTP service: n/a 时，仅执行 set-ntp true 通常不会生效。`
  - 预期：显示 `请先手动安装 chrony：`，含 Debian/Ubuntu 与 CentOS/RHEL 两套手动命令，并提示 `安装完成后重新运行：ss2022` 与 `然后进入：网络与时间 → 自动校准时间`
  - 预期：随后直接返回菜单
  - **绝不**出现 `是否现在尝试安装并启用 chrony？[y/N]:` 询问
  - **绝不**执行 `apt-get` / `dnf` / `yum` 或 `systemctl enable --now chrony`
  - **绝不**生成 `/tmp/ss2022-chrony-install.*.log`
  - 不预期：菜单卡住，或 apt/dpkg 输出与提示混在一起
- ☐ **(v1.0.20)** `grep -nE "是否现在尝试安装并启用 chrony|ss2022-chrony-install|apt-get install -y chrony|dnf install -y chrony|yum install -y chrony" ss2022-shadowtls-manager.sh` 命中项仅为手动命令提示文案，无实际执行路径
- ☐ 系统已有 NTP 服务（`chrony` / `chronyd` / `systemd-timesyncd`）时自动校准时间：
  - 预期：`detect_ntp_unit` 命中并显示 `使用 NTP 服务：<unit>`，启用并最多等待 30 秒检查同步
  - 预期：同步完成提示 `系统时间已同步。`；首次未同步且 unit active 时提示 `NTP 服务已运行，但尚未完成同步。` 与 `首次同步可能需要几十秒，请稍后再次查看。`
- ☐ `NTP service: active` 但 `System clock synchronized: no`
  - 预期：不应输出 `启用 chrony 失败` / `启用 chronyd 失败` / `启用 systemd-timesyncd 失败`
  - 预期：提示 NTP 服务已启用但系统尚未完成同步
- ☐ 等待 30 秒后 chrony / chronyd 仍未同步，且 `chronyc` 存在
  - 预期：主状态后单独显示 `>>> chrony 诊断`，输出 `chronyc tracking` 和 `chronyc sources -v` 只读诊断（原始输出每行不加 `[信息]`）
  - 预期：`^*` 时提示 `当前最佳时间源：<源名>`；`^+` 无 `^*` 时提示候选源；无 `^*`/`^+` 或为空时才提示 DNS、UDP/123、IPv6 路由、机房网络限制、NTP 源不可达等可能原因与更换 NTP 源 / 修改 `chrony.conf` 建议
  - 预期：不把 `synchronized=no` 当作失败
- ☐ 等待 30 秒后 systemd-timesyncd 仍未同步
  - 预期：提示 `timedatectl timesync-status` 和 `journalctl -u systemd-timesyncd -n 80 --no-pager`
- ☐ 自动校准时间输出不应错位
  - 预期：时间状态、chrony 诊断、手动命令各自成块显示
  - 不预期：raw `timedatectl` 与主状态混在一起
  - 预期：不影响 SS2022 服务状态，不重启 / 停止 SS2022

## 3. 一键安装 SS2022

- ☐ 主菜单 1 → 选默认加密方式 → 输入端口 18388 → 自动生成密码 → mode `tcp_and_udp` → 监听模式 dual
- ☐ 安装完成后自动创建 `/usr/local/bin/ss2022` wrapper（包含 `managed by ss2022-shadowtls-manager` 标记）
- ☐ 安装完成后**直接显示**：`=== SS2022 安装完成 ===` + 完整加密方式/密码 + 推荐 SS2022 ss:// 文字链接（**v1.0.3：不再渲染终端二维码**）
- ☐ 显示前有醒目 `[警告]` "以下内容包含完整节点密码，请勿公开分享"
- ☐ 退出 ss2022 命令后再次输入 `ss2022` 能进入菜单
- ☐ 状态栏：SS2022 已安装 / 运行中 / 端口 18388 / 模式 tcp_and_udp
- ☐ `systemctl is-active ss2022.service` = active
- ☐ `ss -ltnp | grep ':18388 '` 看到 ssserver 占用
- ☐ **(v1.0.3 安装路径无可选副作用)** 安装过程**不**自动执行：检测 qrencode、安装 chrony、启用 BBR、写 sysctl、改防火墙规则、修改 nftables、输出大段客户端模板、自动启用 ShadowTLS、检查更新
- ☐ **(v1.0.3 防火墙)** 安装末尾对 SS2022 端口的处理：仅打印 `ufw allow ... / firewall-cmd --add-port ...` 手动命令并询问 `[y/N]` 默认 No；直接回车 → 防火墙规则零变化

### 边界
- ☐ 自定义 PSK 留空 → 自动生成 24/44 字符 base64
- ☐ 自定义 PSK 输入"短字符串" → 校验失败 → 提示重输或留空
- ☐ 端口非法（如 0 / 70000）→ 提示重输
- ☐ 端口被**其它**进程占用 → 提示 "请输入其它端口"，不再"仍使用 [y/N]"
- ☐ 端口被**本项目 ssserver/shadow-tls 残留**占用 → 提示并询问 "是否清理本项目残留进程"

---

## 4. 启用 ShadowTLS v3

- ☐ 主菜单 2 → 启用 → 输入端口 8443 → 选伪装域名 1 (www.bing.com) → 自动生成 ShadowTLS 密码 → 自动切换 SS2022 为 tcp_only
- ☐ 启用完成后**直接显示**：`=== ShadowTLS v3 启用完成 ===` + 完整 SS2022/STLS 密码 + 推荐 SS+ShadowTLS 合并文字链接（**v1.0.3：不再渲染终端二维码**）
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
- ☐ 提示 "是否显示完整链接？完整链接包含密码，请勿公开分享。[y/N]"（**v1.0.3：文案不再提及二维码**）
- ☐ 用户 N → log_info 已取消，**不**显示完整信息
- ☐ 用户 Y → 显示推荐 URI + 客户端配置模板（sing-box / mihomo / Shadowrocket / Surge）；**不再**渲染终端二维码
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
- ☐ 4) 查看时间状态：以块状输出显示本地时间 / UTC / 时区 / NTP 功能 / NTP 服务 / 同步结果；默认不显示 raw `timedatectl`
- ☐ 5) 自动校准时间：执行前显示简洁时间状态；若已同步 → log_ok "系统时间本来已经同步，所以时间显示可能不会明显变化"
  - ☐ 系统已有 systemd-timesyncd / chronyd：优先使用已有服务，不安装任何新包
  - ☐ 系统没有任何 NTP 服务（无 timesyncd / chronyd / chrony unit）：打印分段手动安装命令并返回菜单，不询问安装 chrony
  - ☐ 自动校准时间路径不执行 `apt-get` / `dnf` / `yum`
  - ☐ 时间同步路径不影响 SS2022 主安装：即使 NTP 未配置，菜单 1 仍可正常进入
- ☐ 6) 详细时间诊断：显示 raw `timedatectl`、`chronyc tracking`、`chronyc sources -v` 和 journalctl 检查命令提示
- ☐ 7) 设置时区：
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
- ☐ 输出 `=== 一键完整卸载完成 ===` 总结表，含每项状态（服务/二进制/快捷命令/状态目录/3 个端口）
- ☐ 总结显式声明 "未备份：一键完整卸载按设计直接删除本项目配置"（v1.0.0 默认不备份）
- ☐ YES 前的提示包含 "此操作不可逆。" 与 "一键完整卸载将直接删除本项目配置和服务文件，不再备份"
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
- ☐ apt 包 `curl jq chrony wget` 全部仍在（v1.0.3 起不再涉及 qrencode）

---

## 11. nftables / 防火墙隔离

- ☐ 卸载前后 `nft list ruleset | sha256sum` 一致（不动现有规则）
- ☐ 若系统装有 `nftables-nat-rust-enhanced` 之类项目，其 `/etc/nftables.conf` 与 `/usr/local/sbin/update-nft-ddns-forwards.sh` 卸载前后**字节级一致**
- ☐ 静态扫描脚本：`grep -nE 'nft (flush|-f|delete)' ss2022-shadowtls-manager.sh` 应**无任何输出**
- ☐ `grep -nE '/etc/nftables\.conf' ss2022-shadowtls-manager.sh` 仅出现在注释和卸载总结文案中
- ☐ **(v1.0.3) `ufw` / `firewalld` 不再自动放行**：
  - ☐ 安装 SS2022 时 `open_firewall_port` 先打印 `ufw allow ${port}/${proto}` 或 `firewall-cmd --permanent --add-port=...` 手动命令
  - ☐ 紧跟 `是否现在由本脚本执行该命令? [y/N]:`；直接回车 / N → 不执行任何防火墙命令，端口未自动放行
  - ☐ 仅在用户输入 Y 时才执行对应的 `ufw allow` / `firewall-cmd --add-port` + `--reload`
  - ☐ `nftables` / `nftables-present` 情景下永远只打印参考 `nft add rule` 命令，绝不执行 nft 写操作
  - ☐ 启用 ShadowTLS、修改 SS / STLS 端口、UDP 模式切换共享同一询问逻辑

---

## 12. CI

- ☐ 推送到 main / master / v* 分支后，GitHub Actions `Syntax Check` 工作流通过
- ☐ `bash -n` 步骤通过两个 `.sh` 文件
- ☐ shellcheck 步骤即使有警告也**不会**让工作流失败（`continue-on-error: true`）

---

## 13. 文档完整性

- ☐ README 一行安装命令可被复制粘贴运行
- ☐ README 显示当前版本号与 SCRIPT_VERSION 常量一致
- ☐ install.sh 包含 `readonly INSTALLER_VERSION="v1.0.20"`，并与 MANAGER_VERSION / SCRIPT_VERSION 一致
- ☐ CHANGELOG 包含从 v0.1.0 到当前版本的条目
- ☐ TESTING.md（本文件）与实际行为一致

---

## 14. 反馈模板（用户报 bug 时请附）

```
版本：v1.0.20
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
