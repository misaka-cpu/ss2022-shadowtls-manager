#!/usr/bin/env bash
# =============================================================================
# ss2022-shadowtls-manager — 一行安装 bootstrap
#
# 用法：
#   bash <(curl -fsSL https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/install.sh)
#
# 本脚本只负责：
#   1) 检查 root、按发行版准备主脚本运行必需依赖
#   2) 下载主脚本到 /tmp 临时文件，bash -n 校验通过后覆盖到 /root/ss2022-shadowtls-manager.sh
#   3) 自动创建 /usr/local/bin/ss2022 快捷命令 wrapper（仅当不存在或已是本项目 wrapper）
#   4) exec 主脚本进入交互菜单
#
# 不做：
#   - 不安装 SS2022 / ShadowTLS / systemd 服务
#   - 不修改 nftables / /etc/nftables.conf / nftables-nat-rust-enhanced
#   - 不修改防火墙（ufw / firewalld）
#   - 已存在但非本项目创建的 /usr/local/bin/ss2022 → 绝不覆盖
# =============================================================================

set -o pipefail
umask 077

readonly INSTALLER_VERSION="v1.0.20"
readonly SCRIPT_URL="https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/ss2022-shadowtls-manager.sh"
readonly INSTALL_PATH="/root/ss2022-shadowtls-manager.sh"
readonly SHORTCUT_PATH="/usr/local/bin/ss2022"
readonly SHORTCUT_MARKER="managed by ss2022-shadowtls-manager"

# -----------------------------------------------------------------------------
# 屏幕输出：短行、块状，不把长路径和说明放在同一行
# -----------------------------------------------------------------------------
print_title() {
    cat <<'EOF'

== SS2022 + ShadowTLS Installer ==
EOF
}

print_stage() {
    printf '\n[%s] %s\n\n' "$1" "$2"
}

print_log_path() {
    printf '日志：\n'
    printf '  %s\n' "$1"
}

print_tail_block() {
    local log_path="$1"
    printf '\n日志最后 30 行：\n'
    if [[ -f "${log_path}" ]]; then
        tail -30 "${log_path}"
    else
        printf '日志文件不存在。\n'
        printf '  %s\n' "${log_path}"
    fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
run_with_timeout() {
    local secs="$1"; shift
    if have_cmd timeout; then timeout "${secs}" "$@"; else "$@"; fi
}

# 部分包管理器或其子进程可能改动控制终端的输出模式。
# 保存安装前状态，并在依赖安装后恢复，避免后续输出逐行向右错位。
BOOTSTRAP_TTY_STATE=""
capture_terminal_state() {
    have_cmd stty || return 0
    BOOTSTRAP_TTY_STATE="$(stty -g 2>/dev/null </dev/tty)" || BOOTSTRAP_TTY_STATE=""
}

restore_terminal_state() {
    [[ -n "${BOOTSTRAP_TTY_STATE}" ]] || return 0
    stty "${BOOTSTRAP_TTY_STATE}" 2>/dev/null </dev/tty || true
}

# -----------------------------------------------------------------------------
# 1. root 检查
# -----------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    cat <<'EOF' >&2
需要 root 用户运行。

请先执行：
  sudo -i

然后重新运行一行安装。
EOF
    exit 1
fi

capture_terminal_state
print_title

# -----------------------------------------------------------------------------
# 2. bootstrap 依赖：安装主脚本运行所需的全部必需依赖（apt-get / dnf / yum）
#    依赖自动安装集中在此 bootstrap 阶段完成，主脚本菜单内不再执行包管理器，
#    避免 apt/dpkg 输出与交互菜单提示混在一起导致终端错乱。
#    仅安装主脚本运行必需依赖；不安装 qrencode / chrony / BBR / 防火墙 / nftables。
# -----------------------------------------------------------------------------
print_dep_log_tail() {
    local dep_log="$1"
    print_tail_block "${dep_log}"
}

# 必需命令是否齐全（与主脚本 _required_cmds_missing 保持一致）。
# 以空格分隔返回用户可读缺失项标签：curl jq xz/xzcat ip ss dig/nslookup
required_cmds_missing() {
    local miss=()
    have_cmd curl                           || miss+=(curl)
    have_cmd jq                             || miss+=(jq)
    { have_cmd xz   || have_cmd xzcat;   }  || miss+=(xz/xzcat)
    have_cmd ip                             || miss+=(ip)
    have_cmd ss                             || miss+=(ss)
    { have_cmd dig  || have_cmd nslookup; } || miss+=(dig/nslookup)
    printf '%s' "${miss[*]}"
}

print_missing_items() {
    local item
    for item in $1; do
        printf '  - %s\n' "${item}"
    done
}

# 按包管理器打印手动安装命令（缺依赖时给用户兜底）
print_manual_dep_command() {
    local mgr="$1"
    case "${mgr}" in
        dnf|yum)
            printf '  %s makecache && \\\n' "${mgr}"
            printf '  %s install -y ca-certificates curl jq xz iproute bind-utils\n' "${mgr}"
            ;;
        *)
            cat <<'EOF'
  apt-get update && \
  apt-get install -y ca-certificates curl jq xz-utils iproute2 dnsutils
EOF
            ;;
    esac
}

# 安装主脚本必需依赖并做二次检查；屏幕输出保持简洁，包管理器详细输出写日志。
ensure_bootstrap_deps() {
    print_stage "1/4" "检查依赖"

    local mgr=""
    if   have_cmd apt-get; then mgr=apt-get
    elif have_cmd dnf;     then mgr=dnf
    elif have_cmd yum;     then mgr=yum
    fi

    local missing
    missing="$(required_cmds_missing)"
    if [[ -z "${missing}" ]]; then
        printf '依赖已满足。\n\n'
        return 0
    fi

    if [[ -z "${mgr}" ]]; then
        printf '未找到 apt-get / dnf / yum。\n' >&2
        printf '无法自动安装依赖。\n\n' >&2
        printf '请手动执行：\n' >&2
        print_manual_dep_command apt-get >&2
        exit 1
    fi

    local dep_log="/tmp/ss2022-bootstrap-deps-install.$$.log"
    if ! : > "${dep_log}"; then
        printf '无法创建依赖安装日志。\n' >&2
        printf '  %s\n' "${dep_log}" >&2
        exit 1
    fi
    printf '正在安装缺失依赖...\n'
    print_log_path "${dep_log}"
    printf '\n'

    local rc=0 update_rc=0
    case "${mgr}" in
        apt-get)
            DEBIAN_FRONTEND=noninteractive run_with_timeout 60  apt-get update >> "${dep_log}" 2>&1 || update_rc=$?
            DEBIAN_FRONTEND=noninteractive run_with_timeout 120 apt-get install -y ca-certificates curl jq xz-utils iproute2 dnsutils >> "${dep_log}" 2>&1 || rc=$?
            ;;
        dnf)
            run_with_timeout 60  dnf makecache -y >> "${dep_log}" 2>&1 || update_rc=$?
            run_with_timeout 120 dnf install -y ca-certificates curl jq xz iproute bind-utils >> "${dep_log}" 2>&1 || rc=$?
            ;;
        yum)
            run_with_timeout 60  yum makecache    >> "${dep_log}" 2>&1 || update_rc=$?
            run_with_timeout 120 yum install -y ca-certificates curl jq xz iproute bind-utils >> "${dep_log}" 2>&1 || rc=$?
            ;;
    esac
    restore_terminal_state

    # 二次检查：以命令是否真的存在作为最终判定（覆盖 install 报 0 但部分包未装等情况）
    missing="$(required_cmds_missing)"
    if [[ -z "${missing}" ]]; then
        if [[ ${update_rc} -ne 0 || ${rc} -ne 0 ]]; then
            cat <<EOF
依赖已满足。
包管理器返回过异常，但必需命令已经可用。
继续。

日志：
  ${dep_log}

EOF
        else
            printf '依赖检查完成。\n\n'
        fi
        return 0
    fi

    printf '依赖安装失败，仍缺少：\n' >&2
    {
        print_missing_items "${missing}"
    } >&2
    print_dep_log_tail "${dep_log}"
    printf '\n请手动执行：\n' >&2
    print_manual_dep_command "${mgr}" >&2
    exit 1
}
ensure_bootstrap_deps

# -----------------------------------------------------------------------------
# 2.5 可选：NTP 服务检查
#     SS2022 对系统时间较敏感，时间偏差过大可能导致 invalid timestamp。
#     chrony 不是主脚本运行必需依赖，install.sh 只提示手动命令。
#     不询问 y/N，不安装 chrony，不安装 qrencode，不设置 BBR，不修改防火墙 / nftables。
# -----------------------------------------------------------------------------
# 检测系统已有的 NTP 守护服务，命中则输出 unit 名。
detect_ntp_unit() {
    local unit
    have_cmd systemctl || return 0
    for unit in systemd-timesyncd.service chrony.service chronyd.service; do
        if systemctl list-unit-files "${unit}" 2>/dev/null | grep -q "^${unit}"; then
            printf '%s' "${unit}"
            return 0
        fi
    done
    return 0
}

print_chrony_manual_commands() {
    cat <<'EOF'
建议稍后手动安装 chrony:

Debian/Ubuntu:
  apt-get update
  apt-get install -y chrony
  systemctl enable --now chrony

CentOS/RHEL:
  dnf install -y chrony
  systemctl enable --now chronyd

进入菜单后也可以在:
  网络与时间 -> 自动校准时间

查看时间状态和手动提示。
EOF
}

# 缺少 NTP 服务时只显示手动安装提示，不阻塞进入菜单。
ensure_ntp_service() {
    print_stage "2/4" "检查时间同步"

    local unit
    unit="$(detect_ntp_unit)"
    if [[ -n "${unit}" ]]; then
        printf '已检测到 NTP 服务:\n'
        printf '  %s\n\n' "${unit}"
        return 0
    fi

    cat <<'EOF'
未检测到 NTP 服务。

SS2022 对系统时间较敏感。
时间偏差过大可能导致 invalid timestamp。

EOF
    print_chrony_manual_commands
    printf '\n'
    return 0
}
ensure_ntp_service

# -----------------------------------------------------------------------------
# 3. 下载到临时文件并校验
# -----------------------------------------------------------------------------
tmp_path="/tmp/ss2022-shadowtls-manager.sh.tmp.$$"
trap '[[ -n "${tmp_path:-}" && -f "${tmp_path}" ]] && rm -f -- "${tmp_path}"' EXIT

print_stage "3/4" "下载主脚本"
printf '正在下载主脚本...\n'
printf '来源：\n'
printf '  %s\n\n' "${SCRIPT_URL}"
if ! curl -fsSL --max-time 60 -o "${tmp_path}" "${SCRIPT_URL}"; then
    cat <<EOF >&2
下载失败。

可能原因：
  Private 仓库无法直接访问 raw.githubusercontent.com。

请手动同步主脚本到：
  ${INSTALL_PATH}
EOF
    exit 1
fi
if [[ ! -s "${tmp_path}" ]]; then
    printf '下载内容为空，已中止。\n' >&2
    exit 1
fi
printf '正在校验语法...\n'
if ! bash -n "${tmp_path}" 2>/dev/null; then
    cat <<EOF >&2
语法校验失败。
拒绝覆盖旧版本。

旧版本保留在：
  ${INSTALL_PATH}
EOF
    exit 1
fi
printf '语法校验通过。\n\n'

# -----------------------------------------------------------------------------
# 4. 备份旧版本（如有），覆盖安装
# -----------------------------------------------------------------------------
print_stage "4/4" "安装主脚本"
if [[ -f "${INSTALL_PATH}" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    backup_path="${INSTALL_PATH}.bak.${ts}"
    if cp -a -- "${INSTALL_PATH}" "${backup_path}" 2>/dev/null; then
        printf '已备份旧版本：\n'
        printf '  %s\n\n' "${backup_path}"
    else
        printf '备份旧版本失败。\n' >&2
        printf '继续覆盖。\n' >&2
        printf '  %s\n\n' "${backup_path}" >&2
    fi
fi

if ! install -m 0755 "${tmp_path}" "${INSTALL_PATH}"; then
    printf '安装失败。\n' >&2
    printf '  %s\n' "${INSTALL_PATH}" >&2
    exit 1
fi
printf '主脚本已安装：\n'
printf '  %s\n\n' "${INSTALL_PATH}"

# -----------------------------------------------------------------------------
# 5. 自动创建快捷命令 wrapper /usr/local/bin/ss2022
#    - 不存在 → 创建
#    - 已存在带本项目标记 → 覆盖更新
#    - 已存在但缺少标记 → 绝不覆盖，明确提示
# -----------------------------------------------------------------------------
create_shortcut() {
    if [[ -e "${SHORTCUT_PATH}" ]]; then
        if grep -q "${SHORTCUT_MARKER}" "${SHORTCUT_PATH}" 2>/dev/null; then
            printf '已存在本项目快捷命令。\n'
            printf '将覆盖更新：\n'
            printf '  %s\n\n' "${SHORTCUT_PATH}"
        else
            cat <<EOF >&2
快捷命令已存在，但不是本项目创建。
不覆盖。

请手动检查：
  ${SHORTCUT_PATH}
EOF
            return 0
        fi
    fi
    local wrap_tmp="/tmp/ss2022-wrap.tmp.$$"
    cat > "${wrap_tmp}" <<EOF
#!/usr/bin/env bash
# ${SHORTCUT_MARKER}
exec "${INSTALL_PATH}" "\$@"
EOF
    if ! install -m 0755 "${wrap_tmp}" "${SHORTCUT_PATH}"; then
        rm -f -- "${wrap_tmp}"
        printf '快捷命令安装失败。\n' >&2
        printf '  %s\n' "${SHORTCUT_PATH}" >&2
        return 1
    fi
    rm -f -- "${wrap_tmp}"
    printf '快捷命令已创建：\n'
    printf '  ss2022\n\n'
}
create_shortcut

# -----------------------------------------------------------------------------
# 6. 启动主菜单
# -----------------------------------------------------------------------------
cat <<'EOF'
------------------------------------------------------------
准备完成，正在打开 ss2022 菜单...
------------------------------------------------------------

EOF
sleep 1
# tmp_path 由 EXIT trap 清理；exec 后本脚本结束
restore_terminal_state
exec "${INSTALL_PATH}"
