# Changelog

本项目变更记录，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

`alpha` 标识表示仍可能有 breaking 修改。

## [Unreleased]

（暂无）

## [v1.0.5] — 缺依赖提示体验优化

### Changed
- 优化缺依赖时的新手引导：缺少必需依赖时先列出缺失项，再询问 `是否现在尝试自动安装缺失依赖？[y/N]:`，默认回车不执行安装。
- 缺依赖时只显示当前系统对应的手动修复命令：Debian/Ubuntu 显示 `apt-get update && apt-get install ...`，CentOS/RHEL 显示 `dnf makecache && dnf install ...`；系统未知时才显示两套命令。
- 增加用户确认后自动安装必需依赖选项：只有输入 `y` / `Y` 才执行，且仅批量安装 `ca-certificates curl jq xz-utils/xz iproute2/iproute dnsutils/bind-utils`，不安装 `qrencode` / `chrony`。
- 自动安装使用短超时：索引更新最多 60 秒，包安装最多 120 秒；系统没有 `timeout` 时会提示安装过程可能受软件源速度影响。
- 自动安装后重新执行 `_required_cmds_missing` 二次检查；依赖齐全才继续，依赖仍缺失或自动安装失败 / 超时时直接停止当前 SS2022 安装流程，不会进入加密方式选择。
- `install.sh` 继续保持最小 bootstrap：只处理 `curl` / `ca-certificates`、下载主脚本、`bash -n` 校验、创建 `ss2022` 快捷命令并打开主菜单，不安装 jq / xz / iproute2 / dnsutils。

### Docs
- 版本号 `v1.0.4` → `v1.0.5`；README / 状态栏 / 主菜单标题同步。
- TESTING.md 增加缺依赖时回车默认不自动安装、输入 `y` 才尝试安装、安装失败不会进入加密方式选择的测试项。

### Safety
- 默认策略仍是不自动安装系统依赖；只有用户明确输入 `y` 才会调用包管理器。
- 自动安装路径不触碰 `systemctl`、防火墙、nftables、`/etc/nftables.conf` 或 `nftables-nat-rust-enhanced`。

## [v1.0.4] — 主脚本取消自动安装系统依赖

### Changed — 安装流程不再调用 apt / dnf / yum
- **主脚本不再自动安装任何系统依赖**。v1.0.3 在软件源 / DNS / IPv6 异常时仍会卡在 `apt-get install -y ca-certificates curl jq xz-utils iproute2 dnsutils`（即使 120s 超时，体验仍然差）。v1.0.4 起 `install_dependencies()` 只做必需命令存在性检查：
  - 全部存在 → `[成功] 必需依赖已满足` 并 `return 0`，继续后续安装流程
  - 任一缺失 → `[错误] 缺少必需依赖，无法继续安装 SS2022。` + 列出缺失项 + 按发行版给出手动安装命令 + 常见原因 + 重新运行提示，然后 `return 1`
  - 调用方 `install_ss2022` / `enable_shadowtls` 通过 `if ! install_dependencies; then return 1; fi` 立即中止当前安装流程，回到主菜单（**不会**进入加密方式选择 / 端口输入等后续交互）
- **主脚本删除以下自动安装代码路径**（仅保留文案 / 提示中的命令字符串）：
  - `_install_required_pkgs_batch`（apt/dnf/yum 批量安装 + 120s 超时）
  - `pkg_update_index_once`（`apt-get update` / `dnf makecache` + 60s 超时）
  - `_print_source_diagnostic_hint`（被新的 `_print_manual_install_hint` 取代）
  - `_pkg_mgr_detect` / `_PKG_MGR` / `_PKG_INDEX_UPDATED` 全局状态
  - `_run_with_timeout` 包装（主脚本不再有任何需要包超时调用 apt/dnf/yum 的位置）
- `install.sh` 保留 curl / ca-certificates 的 bootstrap 安装（含 60s 索引 + 120s 安装超时），因为它本就是 bootstrap 角色；但**不再**安装 jq / xz / iproute / dnsutils / bind-utils，那些交由主脚本检查并提示用户手动安装

### Changed — 依赖检查输出
- 输出改为短行块状，避免窄终端折行错位：
  ```
  >>> 检查基础依赖
  [错误] 缺少必需依赖，无法继续安装 SS2022。
  [错误] 缺失项：
  [错误]   - jq
  [错误]   - xz/xzcat
  [错误]   - dig/nslookup

  [警告] 请先手动安装依赖：
  [警告]
  [警告] Debian/Ubuntu:
  [警告]   apt-get update
  [警告]   apt-get install -y ca-certificates curl jq xz-utils iproute2 dnsutils
  [警告]
  [警告] CentOS/RHEL:
  [警告]   dnf makecache
  [警告]   dnf install -y ca-certificates curl jq xz iproute bind-utils
  [警告]
  [警告] 常见原因：
  [警告]   1) 软件源网络慢
  [警告]   2) DNS 解析异常
  [警告]   3) IPv6 路由异常
  [警告]   4) 镜像源不可用
  [警告]   5) 系统软件源配置异常
  [警告]
  [警告] 修复后重新运行：
  [警告]   ss2022
  ```
- 依赖齐全时不再输出冗长的"包管理器：apt-get …"、"必需依赖：…"、"将一次性批量安装：…" 等行，只保留一行 `[成功] 必需依赖已满足`

### Changed
- 版本号 `v1.0.3` → `v1.0.4`；README / 状态栏 / 主菜单标题同步
- README 版本规划新增 v1.0.4 段，原 v1.0.3 去掉"（当前）"标记
- TESTING.md 第 2.x 节相关测试条目改为校验：缺依赖时立即停止、不进入加密方式选择、主脚本不再执行 apt/dnf/yum

### Safety
- 仍不修改 nftables / `/etc/nftables.conf` / `nftables-nat-rust-enhanced`
- 仍不自动 `ufw allow` / `firewall-cmd --add-port`
- 主脚本不再自动调用 `apt/dnf/yum`；唯一仍可能触发系统包管理器的位置是 `install.sh` 的 bootstrap 阶段（仅 curl + ca-certificates）
- 修改范围仅限 `ss2022-shadowtls-manager.sh` 的 `install_dependencies` 及其私有 helper、`README.md`、`CHANGELOG.md`、`TESTING.md`；`install.sh` 行为保持不变

## [v1.0.3] — 彻底移除二维码功能 + 防火墙改为按需手动确认

### Changed — 安装流程进一步轻量化
- **防火墙不再自动 `ufw allow` / `firewall-cmd --add-port`**。`open_firewall_port` 改为先打印手动命令，再询问 `[y/N]` 默认 **No**：
  - 直接回车 / 任意非 `y` 输入 → 保持原状，只在日志中给出建议
  - 仅在用户明确输入 `y` 时才执行 `ufw allow ${port}/${proto}` 或 `firewall-cmd --permanent --add-port=${port}/${proto} && firewall-cmd --reload`
  - `nftables` / `nftables-present` 仍只打印参考命令，绝不修改规则（保持原有安全边界）
  - 该函数被 `install_ss2022` / `enable_shadowtls` / 修改端口 / UDP 模式切换等所有入口共享，一处修改全局生效
- 一键安装 SS2022 流程明确收敛为以下步骤（不做任何不需要的额外操作）：
  1) root + 系统/架构检测
  2) 必需依赖检查（缺失即终止）
  3) 端口 / 加密方式 / 密码 / UDP 模式 / 监听模式输入
  4) 下载 `ssserver`
  5) 写配置 + 写 systemd
  6) 防火墙：**只打印手动命令并询问，默认不修改**
  7) `restart_service ss2022.service`
  8) 自动创建 `/usr/local/bin/ss2022` wrapper（仅在不存在或为本项目标记时）
  9) 显示完整 SS2022 文字链接
- 安装流程**不再**自动执行：qrencode 检测、chrony 安装、BBR 设置、自动改防火墙、nftables 修改、客户端模板大段输出、ShadowTLS 自动启用、一键检查更新等任何可选行为
- BBR / sysctl、客户端配置模板、UDP / 防火墙手动放行确认、一键检查更新、ShadowTLS 启用等仍可在「高级设置」/「网络与时间」/「查看节点信息」/「启用 ShadowTLS」/「一键检查更新」对应菜单中显式触发；不在安装路径中预热

### Removed
- **终端二维码渲染功能完全下线**：删除 `generate_terminal_qrcode()`、`show_recommended_uri_and_qrcode()`、`show_recommended_full_uri_and_qrcode_no_confirm()`、`show_node_info_with_qrcode()` 这一整组函数与所有 `qrencode -t ANSIUTF8` 调用路径
- 同步删除：
  - `PROJECT_QRCODE_DIR` 常量与对应 `mkdir -p` / `chmod 700` 调用（项目目录不再创建 `qrcode/` 子目录；卸载流程通过 `PROJECT_ETC` 整目录删除，已存在的旧子目录仍会被清理）
  - `install_dependencies` 中检测 `qrencode` 并提示手动安装命令的整段逻辑（依赖检查完成后不再出现 qrencode 提示）
  - 「查看节点信息」遮蔽视图末尾的 "(将显示推荐链接 / 客户端配置 / 二维码)" 措辞改为 "(将显示推荐完整链接 / 客户端配置)"

### Changed
- 函数重命名（无行为变化，仅去掉 `_qrcode` 词缀，便于阅读与 grep）：
  - `show_recommended_uri_and_qrcode` → `show_recommended_uri`
  - `show_recommended_full_uri_and_qrcode_no_confirm` → `show_recommended_full_uri_no_confirm`
  - `show_node_info_with_qrcode` → `show_node_info_with_confirm`（主菜单 3 入口绑定同步更新）
- `confirm_show_secret` 询问文案改为："是否显示完整链接？完整链接包含密码，请勿公开分享。[y/N]"
- 安装 / 启用完成结果区只输出推荐文字链接 + 客户端配置示例提示；不再有"以下内容包含完整密码和二维码"等措辞
- README 功能特点第 4 条改为 "安装/启用完成直接显示完整文字链接"；常见问题表删除 "二维码扫码失败" 一行；卸载摘要中 `apt 包` 示例去掉 `qrencode`；版本规划新增 v1.0.3 段
- TESTING.md 第 3 / 4 / 5 节相关测试条目改为只校验"完整链接 + 客户端配置"展示，不再要求测试终端二维码
- 版本号 `v1.0.2` → `v1.0.3`

### Safety
- 仍不修改 nftables / `/etc/nftables.conf` / `nftables-nat-rust-enhanced`
- 主流程仍不会自动 `apt/dnf/yum install`；本版本无新增的高风险路径

## [v1.0.2] — 修复 v1.0.1 残留逻辑漏洞

### Fixed
- **必需依赖安装失败后脚本继续进入"请选择 SS2022 加密方式"** —— 严重逻辑错误：v1.0.1 实测在 Debian/Ubuntu 上 `apt-get install` 120s 超时后仍可能输出 "[成功] 依赖检查完成"。`install_dependencies()` 现在显式分两阶段：
  - 先记录 `install_rc`（apt/dnf 退出码）
  - 再以 `_required_cmds_missing` 的**实际命令存在性**作为最终判定，不论 install_rc 是 0 / 124 / 其他
  - 任一必需命令仍缺失 → `log_error` 并 `return 1`，调用方 `install_ss2022` / `enable_shadowtls` 通过 `if ! install_dependencies; then return 1; fi` 中止安装
  - "依赖检查完成（必需依赖全部就绪）" 文案仅在所有必需命令都存在时才会输出
- **错误提示与软件源诊断输出格式杂乱、易被终端折行错位** —— 改为短行分块：可能原因 5 条逐行列出，手动命令按 Debian/Ubuntu 与 CentOS/RHEL 分别两段输出，单行不超过软件包列表本身长度

### Changed
- `_required_cmds_missing` 改为输出用户可读的标签集合：`curl / jq / xz/xzcat / ip / ss / dig/nslookup`；不再让用户混淆"包名 vs 命令名"
- `_print_source_diagnostic_hint` 与 `install.sh` 的 `print_source_hint` 统一短行分块格式
- 必需依赖失败错误信息明确指引用户："请手动修复软件源后执行 apt-get install / dnf install ...，然后重新运行 ss2022"
- **`sync_time_auto` 进一步轻量化**：未检测到 `systemd-timesyncd` / `chronyd` / `chrony` 时**只**打印分块的手动安装命令（含 `systemctl enable --now`），**删除**原有的 "是否安装 chrony? [y/N]" + 二次确认 + `install_pkg chrony` 120s 安装路径。本脚本任何场景都不再自动安装 chrony，避免菜单被网络源慢阻塞；时间同步永远不影响 SS2022 主安装流程
- 删除随之失去调用方的死代码：`install_pkg()`（单包安装） 与 `_pkg_name_for_distro()`（包名映射）；批量安装路径在 `install_dependencies` 内显式按发行版组装包列表，逻辑更直白
- 版本号从 `v1.0.1` 升级到 `v1.0.2`；README / 状态栏 / 主菜单标题同步

### Safety
- 仍不修改 nftables / `/etc/nftables.conf` / `nftables-nat-rust-enhanced`
- 主流程与时间同步、二维码三条路径都**不会**自动调用 `apt/dnf/yum install`；只在用户主动进入"一键安装 / 重装"且必需依赖确实缺失时才批量安装
- 仅修改 `install_dependencies` / `_required_cmds_missing` / `_print_source_diagnostic_hint` / `sync_time_auto` 与 `install.sh` 的 `print_source_hint`；其它流程未触碰

## [v1.0.1] — 安装体验修复

### Fixed
- **必需依赖安装不再逐包卡 180 秒**：`install_dependencies` 改为按发行版组装 `ca-certificates curl jq xz(-utils) iproute(2) bind-utils/dnsutils` 一次性批量传给 `apt-get install` / `dnf install` / `yum install`，整体 120 秒超时；索引更新（`apt-get update` / `dnf makecache`）也从 120s 收紧到 60s。在 Debian/Ubuntu 实测下，xz-utils 等单包等 180s 的体验问题不再出现
- **qrencode 不再阻塞 SS2022 安装**：从必备依赖中剔除，主流程默认不再尝试 `apt install qrencode`；缺失时只显示"未检测到 qrencode，无法显示终端二维码"并给出手动命令，同时正常输出完整文字链接，不中断安装/启用流程
- **chrony 默认不再自动安装**：`sync_time_auto` 在未检测到 `systemd-timesyncd` / `chronyd` / `chrony` 时打印明确的手动安装命令（含 `systemctl enable --now`），询问"是否现在尝试安装 chrony? [y/N]" 默认 No，并加一道二次确认 `[y/N]`；用户明确 Yes 时调用 `install_pkg chrony` 走 120s 超时，超时/失败只警告并返回菜单，绝不再无限等待
- **`install.sh` 同步收紧超时**：`apt-get update` / `dnf makecache` / `yum makecache` 60 秒；`apt-get install curl ca-certificates` / `dnf install` / `yum install` 120 秒；超时或失败统一输出软件源诊断提示与手动命令

### Changed
- 必需依赖集合明确缩小为：`ca-certificates curl jq xz iproute dig`（来自 `bind-utils` / `dnsutils`）；可选依赖：`qrencode`（仅二维码）、`chrony`（仅时间同步备选）
- 批量安装结束后会再次校验必需命令是否齐全：仍缺失则直接终止当前 SS2022 / ShadowTLS 启用流程，提示"缺少必需依赖，无法继续安装 SS2022"；只缺可选依赖时主流程继续
- `apt-get update` / `dnf makecache` / 安装超时统一打印软件源诊断建议：网络、DNS、IPv6、镜像源、软件源配置五项排查方向，并附手动命令
- 版本号从 `v1.0.0` 升级到 `v1.0.1`；README / 主菜单标题 / 状态栏同步

### Safety
- 不修改 nftables 规则与 `/etc/nftables.conf`；不动 `nftables-nat-rust-enhanced` 项目
- 不在二维码渲染路径中悄悄调用 `apt-get install`；不在时间同步路径中悄悄安装 chrony
- 所有新增安装路径都带 `timeout`，并在 124（超时）/ 非 0（失败）下打印手动命令，不静默吞错

## [v1.0.0] — 第一个稳定版

### Added
- **一行安装后自动创建 `ss2022` 快捷命令**：`install.sh` 在主脚本就位后写入 `/usr/local/bin/ss2022` wrapper（带 `managed by ss2022-shadowtls-manager` 标记）；已存在但非本项目的同名文件**绝不覆盖**，明确提示用户手动处理
- **CentOS / RHEL / Rocky / AlmaLinux 9** 支持：`detect_os` 增加 `OS_FAMILY=rhel` 分支；`install_dependencies` / `install_pkg` 支持 `apt-get` / `dnf` / `yum` 自动切换；包名按发行版差异自动映射（`xz-utils ↔ xz`、`dnsutils ↔ bind-utils`、`iproute2 ↔ iproute`）
- 依赖安装全程**带超时**：索引更新 `timeout 120s`，包安装 `timeout 180s`；超时与失败都给清晰提示，不再无限卡住
- 时间状态显示新增「时区偏移」（`UTC+8` / `UTC+5:30` 等可读格式）与「时间同步状态」（正常 / 未同步 / 未检测），并明确解释 "本地时间与 UTC 时间按时区换算，存在时区偏移是正常现象"
- `sync_time_auto` 改为按发行版自动选择 NTP 守护：Debian/Ubuntu 优先 `systemd-timesyncd`，RHEL/CentOS 9 优先 `chronyd`；chrony 安装走统一 `install_pkg`，支持 apt/dnf/yum

### Fixed
- **一键完整卸载默认不再备份**：按设计直接删除本项目配置，YES 确认前明确警示 "此操作不可逆"；总结改为 "未备份：一键完整卸载按设计直接删除本项目配置。如需保留配置，请使用单独停用/卸载功能"。`uninstall_ss2022` / `uninstall_shadowtls` 单独卸载流程仍自动备份
- **BBR / sysctl 状态友好化**：不再显示 "（不存在）" 误导文案；按 "已启用 / 持久化配置：本项目 / 系统已有 / 未创建" 三态区分；系统已是 bbr+fq 但本项目 sysctl 文件不存在时明确说明 "当前系统已经启用 BBR，不需要重复写入本项目 sysctl 文件"
- 主菜单"一键安装 / 重装"卡在"更新软件包索引"：增加 120 秒超时和"软件源响应过慢"明确提示，并继续尝试用已有索引安装

### Changed
- 版本号从 `v0.2.0-beta` 升级到 `v1.0.0`；README / CHANGELOG / TESTING / 状态栏 / 主菜单标题全部同步
- 支持系统列表新增 CentOS / RHEL / Rocky / AlmaLinux 9 系列
- 保持 nftables 安全边界不变：不 `flush ruleset`、不 `nft -f`、不覆盖现有规则、不动 `/etc/nftables.conf`、不修改 `nftables-nat-rust-enhanced` 项目

## [v0.2.0-beta] — 第一个公开 beta

### Fixed
- **Shadowrocket / Surge 手动配置地址占位符**：新增 `resolve_preferred_server`（域名 → IPv4 → IPv6 → 空），输出时自动填入真实可用地址；未检测到任何可用地址时显示明确提示 "未检测，请先在「网络与时间 → 检测公网 IP」或「设置服务器域名」中配置"，不再输出 `<服务器 IP 或域名>` / `<server>` 占位符
- **UDP 模式菜单缺少返回选项**：`set_udp_mode` 增加 `0) 返回`，使用 `MENU_RC_SKIP_PAUSE=10` 返回上一级；`submenu_udp_bbr` 案 1 加 `[[ $? -eq ... ]] && continue` 守卫，输入 0 时不再多按一次回车

### Added
- 普通 SS2022 模式（ShadowTLS 未启用）下也输出 Shadowrocket / Surge 手动配置模板，方便不使用 ShadowTLS 的用户
- 已完成一行安装、快捷命令、统一更新、完整卸载、终端二维码、时间同步等核心场景的多轮实测

### Changed
- 版本常量升级到 `v0.2.0-beta`；README / CHANGELOG / 状态栏同步
- 状态从 "alpha 内部测试 + 公开测试" 转为 "公开 beta"

### 之前 alpha 阶段合入（v0.1.x-alpha 累计）
本段汇总 v0.1.0 → v0.1.7-alpha 期间的关键变更：

- `install.sh` 一行安装 bootstrap；`CHANGELOG.md` / `TESTING.md` / `.github/workflows/syntax.yml`
- 版本常量统一为 `MANAGER_VERSION`，保留 `SCRIPT_VERSION` **字面量** 别名（旧客户端的 `grep + sed` 提取兼容性）
- `get_manager_script_path` / `sync_wrapper_to_target` / `_extract_manager_version_from_file` / `_extract_wrapper_target`：精确解析真实主脚本路径和 wrapper 目标
- 一键检查更新：管理脚本远程探测优先 `MANAGER_VERSION` 回退 `SCRIPT_VERSION`；覆盖后自动 `bash -n` + 版本核对；不一致自动回滚到备份并打印路径诊断
- 更新成功后**不再继续停留在旧进程**：所有更新跑完统一在 `check_and_update_all` 末尾询问；Y → `exec target`，N → `exit 0`
- 一键检查更新状态表新增调试字段：当前运行路径、快捷命令路径、快捷命令指向、状态

## [v0.1.7-alpha] — 实测 bug 修复

### Fixed
- **一键完整卸载后状态残留**：状态栏改用「info + 配置 + service + 二进制」综合判定，任何一项缺失即显示"未安装"，端口/模式归 N/A
- **一键完整卸载后端口残留**：新增 `stop_project_services_strict`（`disable --now` + `daemon-reload` + `reset-failed` + 残留进程 TERM 2s 后 KILL），仅杀本项目二进制路径起的进程
- **重新安装同端口误报占用**：端口循环增加"占用者是本项目残留 → 提示清理"分支；非本项目占用 → 改为提示用户输入其它端口（不再"仍使用 [y/N]"危险选项）
- **端口判定精度**：`_port_in_use` / `_port_occupiers` / `_port_occupier_is_project` 用 `ss -ltnp | awk '$4 ~ ":port$"'` 末尾锚定，避免 `:18388` 误匹配 `:183889`

### Added
- `is_ss2022_installed` / `is_shadowtls_installed` / `is_shadowtls_enabled_real`：综合安装态判定
- `wait_port_free <port> <proto> [wait_sec]`：等待端口释放
- `show_install_result_full` / `show_shadowtls_enable_result_full` / `show_recommended_full_uri_and_qrcode_no_confirm`：安装 / 启用动作完成后**直接展示完整链接 + 终端二维码**，无需二次确认
- 卸载完成总结新增端口释放状态明细，区分"本项目残留"与"非本项目进程"占用

## [v0.1.7-alpha] — 菜单返回 UX

### Fixed
- **设置时区菜单输入 0 返回仍要按一次回车**：引入 `MENU_RC_SKIP_PAUSE=10` 约定；`set_timezone_interactive` 0/留空 → `return 10`，`submenu_network_time` 案 6 守卫 `[[ $? -eq ... ]] && continue` 跳过父 `press_any_key`
- 修复 6 处过时"菜单 N / 选项 N"用户文案（菜单重构后留下的死链引用）

### Changed
- 顺手统一注释与菜单文案，避免再次误指向已不存在的菜单数字

## [v0.1.4-alpha] — H2/H3 收尾

### Added
- `github_latest_tag` 双路径：先 API，失败回退到 `releases/latest` 302 跳转
- `_restore_binary_and_check`：更新失败时从备份恢复旧二进制并 `is-active` 校验，失败时打印 `systemctl status` + `journalctl -n 80`
- 客户端配置注释加入版本兼容提示（sing-box ≥ 1.8、mihomo ≥ 1.18、Surge 实验性）
- BBR 状态详尽提示；`show_sys_opt` 增加 "BBR 状态" 行与 `SYSCTL_CONF` 路径
- 抽取 helper：`resolve_recommended_port` / `resolve_recommended_mode_label` / `get_available_servers`

### Fixed
- `modify_stls_port` 旧端口清理增加 `old != 0 && old != new` 守卫
- 监听模式选 ipv6/dual 但未检测到公网 IPv6 时给非阻塞警告
- mihomo YAML `cipher` 字段加双引号
- 时区菜单加 `0) 返回`

## [v0.1.3-alpha] — 节点信息去重

### Fixed
- 节点信息中删除重复"普通 SS2022 ss:// 链接"段；ShadowTLS 启用时仅显示"推荐 SS2022 + ShadowTLS 合并链接"
- 状态栏"快捷命令"3 态：`ss2022` / `未安装` / `冲突`（路径存在但缺少 `${SHORTCUT_MARKER}` 标记）
- 时间反馈优化：`show_time_status` 分行；`sync_time_auto` 前后快照 + "本来已经同步" 明示；`set_timezone_interactive` 显示 before/after，相同时区直接提示无需修改
- 日志菜单 `journal_follow_safe` 用父进程 `trap '' INT` + 子 shell 隔离 SIGINT，Ctrl+C 不再退出整个脚本

### Removed
- 高级设置删除"修复快捷命令 / 删除快捷命令"两项（普通用户不需要直接看到；函数仍保留供 install/uninstall 内部调用）

## [v0.1.2-alpha] — 工程化

### Added
- 自动安装 `/usr/local/bin/ss2022` 快捷命令（含 `managed by ss2022-shadowtls-manager` 归属标记）
- 主菜单状态栏增加"快捷命令"行
- 统一一键检查更新 `check_and_update_all`：管理脚本 + shadowsocks-rust + shadow-tls + 快捷命令一表呈现
- `update_manager_script` 远程更新主脚本（备份 + 下载 + `bash -n` 校验 + 覆盖）
- 主菜单从 9 项精简到 8 项；二维码不再单独入口；安装/查看节点信息时自动展示
- README 增加"一行命令安装"章节

### Changed
- 二维码默认**只在终端显示**，不再保存 PNG 文件；`PROJECT_QRCODE_DIR` 常量保留为未来扩展预留
- 系统时间管理：`show_time_status` / `sync_time_auto` / `set_timezone_interactive` / `set_time_manual` / `hint_time_before_install`
- 状态栏增加"时间同步"行

## [v0.1.1-alpha] — 安全加固

### Added
- `safe_remove_tmpdir` / `safe_remove_tmpfile`：路径前缀校验后再 `rm -rf -- ` / `rm -f -- `
- `validate_ss2022_psk_by_method`：base64 解码后字节数与 method 要求匹配
- `confirm_save_qr_png` / `confirm_show_secret`：敏感内容显示前显式同意
- `uninstall_all`：备份到 `/root/ss2022-shadowtls-backup-<日期>/` + YES 二次确认 + 详细删除/跳过明细
- `disable_shadowtls` / `uninstall_shadowtls`：仅在 SS2022 已安装时才恢复其公网监听并重启
- `uninstall_ss2022`：ShadowTLS 仍在用时给出依赖检查，可级联卸载或中止

### Fixed
- `info_set` 临时文件改用 `mktemp --tmpdir="$(dirname PROJECT_INFO)"`，`mv -f --` 同 FS 内尽量原子
- ShadowTLS 启用时 SS2022 后端固定 `127.0.0.1`（不再因 listen_mode 走 `::1`）；`server_target` 直接 `127.0.0.1:${local_port}`
- ShadowTLS IPv6 监听拼接 `[::]:port`，永远不会出现 `:::port`
- `show_node_info_impl` ShadowTLS 启用时不再生成"端口指向 ShadowTLS 但密码是 SS2022"的误导性 ss:// 链接

## [v0.1.0] — 初版

### Added
- SS2022 (shadowsocks-rust) 安装 / 卸载 / 启停 / 修改端口/密码/方法
- ShadowTLS v3 (ihciah/shadow-tls) 启用 / 停用 / 卸载 / 修改端口/密码/伪装域名
- 系统检测：Debian 11/12 + Ubuntu 20.04/22.04/24.04，amd64 + aarch64
- IPv4 / IPv6 / 双栈监听
- 公网 IP 自动探测（api.ipify.org / api6.ipify.org）
- SS2022 ss:// 链接、SS + ShadowTLS 合并链接（SIP002 plugin URI）
- sing-box / mihomo / Clash Meta / Shadowrocket / Surge 客户端配置输出
- 二维码（终端 ANSI + 可选 PNG）
- UDP 模式选择（tcp_only / tcp_and_udp / udp_only）
- BBR 一键启用
- 防火墙：ufw / firewalld 自动放行；**nftables 仅检测与提示，绝不修改**
- systemd 单元（`Restart=always`、`LimitNOFILE=1048576`）
- `/etc/ss2022-shadowtls-manager/info.json` 项目状态文件
- 配置自动备份到 `/etc/ss2022-shadowtls-manager/backup/`
