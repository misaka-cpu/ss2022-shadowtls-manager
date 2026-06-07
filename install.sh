#!/usr/bin/env bash
# =============================================================================
# ss2022-shadowtls-manager — 一行安装 bootstrap
#
# 用法：
#   bash <(curl -fsSL https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/install.sh)
#
# 本脚本只负责：
#   1) 检查 root、按发行版准备 curl / ca-certificates
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

readonly INSTALLER_VERSION="v1.0.17"
readonly SCRIPT_URL="https://raw.githubusercontent.com/misaka-cpu/ss2022-shadowtls-manager/main/ss2022-shadowtls-manager.sh"
readonly INSTALL_PATH="/root/ss2022-shadowtls-manager.sh"
readonly SHORTCUT_PATH="/usr/local/bin/ss2022"
readonly SHORTCUT_MARKER="managed by ss2022-shadowtls-manager"

# -----------------------------------------------------------------------------
# 中文彩色日志
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'
    C_CYAN=$'\033[0;36m'
    C_RESET=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_RESET=""
fi
log_info()  { printf '%s[信息]%s %s\n' "${C_CYAN}"   "${C_RESET}" "$*"; }
log_ok()    { printf '%s[成功]%s %s\n' "${C_GREEN}"  "${C_RESET}" "$*"; }
log_warn()  { printf '%s[警告]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
log_error() { printf '%s[错误]%s %s\n' "${C_RED}"    "${C_RESET}" "$*" >&2; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }
run_with_timeout() {
    local secs="$1"; shift
    if have_cmd timeout; then timeout "${secs}" "$@"; else "$@"; fi
}

# -----------------------------------------------------------------------------
# 1. root 检查
# -----------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    log_error "本脚本需以 root 用户运行"
    log_info  "请使用 root 用户运行：sudo -i"
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. bootstrap 依赖：安装主脚本运行所需的全部必需依赖（apt-get / dnf / yum）
#    依赖自动安装集中在此 bootstrap 阶段完成，主脚本菜单内不再执行包管理器，
#    避免 apt/dpkg 输出与交互菜单提示混在一起导致终端错乱。
#    仅安装主脚本运行必需依赖；不安装 qrencode / chrony / BBR / 防火墙 / nftables。
# -----------------------------------------------------------------------------
print_dep_log_tail() {
    local dep_log="$1"
    log_info "详细日志：${dep_log}"
    log_info "安装日志最后 30 行："
    if [[ -f "${dep_log}" ]]; then
        tail -30 "${dep_log}"
    else
        log_warn "日志文件不存在：${dep_log}"
    fi
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
    log_info "正在检查 bootstrap 依赖..."

    local mgr=""
    if   have_cmd apt-get; then mgr=apt-get
    elif have_cmd dnf;     then mgr=dnf
    elif have_cmd yum;     then mgr=yum
    fi

    local missing
    missing="$(required_cmds_missing)"
    if [[ -z "${missing}" ]]; then
        log_ok "bootstrap 依赖已满足"
        return 0
    fi

    if [[ -z "${mgr}" ]]; then
        log_error "未找到 apt-get / dnf / yum，无法自动安装依赖。"
        log_warn "请手动安装以下依赖后重试："
        print_manual_dep_command apt-get >&2
        exit 1
    fi

    local dep_log="/tmp/ss2022-bootstrap-deps-install.$$.log"
    : > "${dep_log}" || { log_error "无法创建依赖安装日志：${dep_log}"; exit 1; }
    log_info "正在安装缺失依赖，详细日志：${dep_log}"

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

    # 二次检查：以命令是否真的存在作为最终判定（覆盖 install 报 0 但部分包未装等情况）
    missing="$(required_cmds_missing)"
    if [[ -z "${missing}" ]]; then
        if [[ ${update_rc} -ne 0 || ${rc} -ne 0 ]]; then
            log_warn "包管理器返回异常，但必需命令已可用，继续。"
            log_info "如需排查，查看日志：${dep_log}"
        fi
        log_ok "bootstrap 依赖已满足"
        return 0
    fi

    log_error "bootstrap 依赖仍然缺失，无法进入菜单。"
    {
        printf '缺失项：\n'
        print_missing_items "${missing}"
        printf '\n'
    } >&2
    print_dep_log_tail "${dep_log}"
    log_warn "请手动安装以下依赖后重试（修复软件源后再执行）："
    print_manual_dep_command "${mgr}" >&2
    exit 1
}
ensure_bootstrap_deps

# -----------------------------------------------------------------------------
# 2.5 可选：NTP 服务（chrony）准备
#     SS2022 对系统时间较敏感，时间偏差过大可能导致 invalid timestamp。
#     仅在缺少 NTP 服务时询问是否安装 chrony（默认 Yes）；
#     chrony 不是主脚本运行必需依赖，安装失败不阻塞进入主菜单。
#     不安装 qrencode，不设置 BBR，不修改防火墙 / nftables。
# -----------------------------------------------------------------------------
# 检测系统已有的 NTP 守护服务，命中则输出 unit 名（chrony / chronyd / systemd-timesyncd）
detect_ntp_unit() {
    local unit
    have_cmd systemctl || return 0
    for unit in chrony.service chronyd.service systemd-timesyncd.service; do
        if systemctl list-unit-files "${unit}" 2>/dev/null | grep -q "^${unit}"; then
            printf '%s' "${unit%.service}"
            return 0
        fi
    done
    return 0
}

print_chrony_manual_commands() {
    cat <<'EOF'

请手动安装 chrony：

Debian/Ubuntu:
  apt-get update
  apt-get install -y chrony
  systemctl enable --now chrony

CentOS/RHEL:
  dnf install -y chrony
  systemctl enable --now chronyd
EOF
}

# 缺少 NTP 服务时询问安装 chrony（默认 Yes）；安装失败仅警告并继续。
ensure_ntp_service() {
    local unit
    unit="$(detect_ntp_unit)"
    if [[ -n "${unit}" ]]; then
        log_info "已检测到 NTP 服务：${unit}，跳过 chrony 安装提示。"
        return 0
    fi

    local mgr=""
    if   have_cmd apt-get; then mgr=apt-get
    elif have_cmd dnf;     then mgr=dnf
    elif have_cmd yum;     then mgr=yum
    fi

    log_warn "当前系统没有可用 NTP 服务。"
    log_warn "SS2022 对系统时间较敏感，时间偏差过大可能导致 invalid timestamp。"
    log_info "建议安装 chrony 作为时间同步服务。"

    if [[ -z "${mgr}" ]]; then
        log_warn "未找到 apt-get / dnf / yum，无法自动安装 chrony。"
        print_chrony_manual_commands >&2
        log_info "继续进入菜单（chrony 不是主脚本运行必需依赖）。"
        return 0
    fi

    local ans
    read -r -p "是否现在安装 chrony？[Y/n]: " ans
    if [[ "${ans}" =~ ^[Nn]$ ]]; then
        log_info "已跳过 chrony 安装。稍后可在 ss2022 菜单的「网络与时间」查看手动命令。"
        return 0
    fi

    local chrony_log="/tmp/ss2022-bootstrap-chrony-install.$$.log"
    : > "${chrony_log}" || { log_warn "无法创建 chrony 安装日志：${chrony_log}，已跳过 chrony 安装。"; return 0; }
    log_info "正在安装 chrony，详细日志：${chrony_log}"

    case "${mgr}" in
        apt-get)
            DEBIAN_FRONTEND=noninteractive run_with_timeout 60  apt-get update >> "${chrony_log}" 2>&1 || true
            DEBIAN_FRONTEND=noninteractive run_with_timeout 120 apt-get install -y chrony >> "${chrony_log}" 2>&1 || true
            run_with_timeout 30 systemctl enable --now chrony >> "${chrony_log}" 2>&1 || true
            ;;
        dnf)
            run_with_timeout 120 dnf install -y chrony >> "${chrony_log}" 2>&1 || true
            run_with_timeout 30 systemctl enable --now chronyd >> "${chrony_log}" 2>&1 || true
            ;;
        yum)
            run_with_timeout 120 yum install -y chrony >> "${chrony_log}" 2>&1 || true
            run_with_timeout 30 systemctl enable --now chronyd >> "${chrony_log}" 2>&1 || true
            ;;
    esac

    # 二次检测：以 NTP 服务是否存在为准，不因 apt/dnf/systemctl 返回码异常就报失败
    unit="$(detect_ntp_unit)"
    if [[ -n "${unit}" ]]; then
        log_ok "已检测到 NTP 服务：${unit}"
        return 0
    fi

    log_warn "未检测到可用 NTP 服务。"
    log_info "日志最后 30 行："
    tail -30 "${chrony_log}" 2>/dev/null || true
    log_info "继续进入菜单（chrony 不是主脚本运行必需依赖）。"
    return 0
}
ensure_ntp_service

# -----------------------------------------------------------------------------
# 3. 下载到临时文件并校验
# -----------------------------------------------------------------------------
tmp_path="/tmp/ss2022-shadowtls-manager.sh.tmp.$$"
trap '[[ -n "${tmp_path:-}" && -f "${tmp_path}" ]] && rm -f -- "${tmp_path}"' EXIT

log_info "下载主脚本：${SCRIPT_URL}"
if ! curl -fSL --max-time 60 -o "${tmp_path}" "${SCRIPT_URL}"; then
    log_error "下载失败；如果仓库为 Private，raw.githubusercontent.com 无法直接访问"
    log_info  "请使用 scp 或 git pull 手动同步主脚本到 ${INSTALL_PATH}"
    exit 1
fi
if [[ ! -s "${tmp_path}" ]]; then
    log_error "下载内容为空，已中止"
    exit 1
fi
log_info "进行 bash -n 语法校验..."
if ! bash -n "${tmp_path}" 2>/dev/null; then
    log_error "下载到的脚本 bash -n 校验失败；拒绝覆盖旧版本"
    log_info  "旧版本（若存在）保留在：${INSTALL_PATH}"
    exit 1
fi
log_ok "语法校验通过"

# -----------------------------------------------------------------------------
# 4. 备份旧版本（如有），覆盖安装
# -----------------------------------------------------------------------------
if [[ -f "${INSTALL_PATH}" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    backup_path="${INSTALL_PATH}.bak.${ts}"
    if cp -a -- "${INSTALL_PATH}" "${backup_path}" 2>/dev/null; then
        log_ok "已备份旧版本：${backup_path}"
    else
        log_warn "备份旧版本失败（继续覆盖）：${backup_path}"
    fi
fi

if ! install -m 0755 "${tmp_path}" "${INSTALL_PATH}"; then
    log_error "安装到 ${INSTALL_PATH} 失败"
    exit 1
fi
log_ok "已安装：${INSTALL_PATH}"

# -----------------------------------------------------------------------------
# 5. 自动创建快捷命令 wrapper /usr/local/bin/ss2022
#    - 不存在 → 创建
#    - 已存在带本项目标记 → 覆盖更新
#    - 已存在但缺少标记 → 绝不覆盖，明确提示
# -----------------------------------------------------------------------------
create_shortcut() {
    if [[ -e "${SHORTCUT_PATH}" ]]; then
        if grep -q "${SHORTCUT_MARKER}" "${SHORTCUT_PATH}" 2>/dev/null; then
            log_info "已存在本项目快捷命令，将覆盖更新：${SHORTCUT_PATH}"
        else
            log_warn "${SHORTCUT_PATH} 已存在但不是本项目创建（缺少标记），不覆盖。"
            log_warn "请手动检查后再决定是否安装快捷命令。"
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
        log_warn "快捷命令安装失败：${SHORTCUT_PATH}"
        return 1
    fi
    rm -f -- "${wrap_tmp}"
    log_ok "快捷命令已创建：ss2022  →  ${INSTALL_PATH}"
}
create_shortcut

# -----------------------------------------------------------------------------
# 6. 启动主菜单
# -----------------------------------------------------------------------------
log_info "启动管理菜单..."
echo
# tmp_path 由 EXIT trap 清理；exec 后本脚本结束
exec "${INSTALL_PATH}"
