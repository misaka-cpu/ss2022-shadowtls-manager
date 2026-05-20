# Changelog

本项目变更记录，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

`alpha` 标识表示仍可能有 breaking 修改。

## [Unreleased]

### Added
- `install.sh`：一行安装 bootstrap 脚本（root 检查 + curl/ca-cert 依赖 + 下载到 /tmp + `bash -n` 校验 + 备份旧版本 + `exec` 进入交互菜单）
- `CHANGELOG.md`：本变更记录文件
- `TESTING.md`：发布前的手工测试清单
- `.github/workflows/syntax.yml`：CI 仅做 `bash -n` 语法检查，不触发任何系统级安装

### Changed
- README 重写为发布质量版本：突出 10 项卖点 + 安全边界 + 一行安装命令 + 常见问题表

## [v0.1.6-alpha] — 实测 bug 修复

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

## [v0.1.5-alpha] — 菜单返回 UX

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
