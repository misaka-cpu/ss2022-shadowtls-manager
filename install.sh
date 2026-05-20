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
# 2. 检查并安装基础依赖（curl / ca-certificates）—— 支持 apt-get / dnf / yum
# -----------------------------------------------------------------------------
ensure_dep_curl() {
    if have_cmd curl; then
        return 0
    fi
    log_warn "未检测到 curl，尝试自动安装..."

    local mgr=""
    if   have_cmd apt-get; then mgr=apt-get
    elif have_cmd dnf;     then mgr=dnf
    elif have_cmd yum;     then mgr=yum
    fi
    if [[ -z "${mgr}" ]]; then
        log_error "未找到 apt-get / dnf / yum；请手动安装 curl 与 ca-certificates 后重试"
        exit 1
    fi

    log_info "包管理器：${mgr}（更新索引最多等待 120 秒）..."
    case "${mgr}" in
        apt-get)
            DEBIAN_FRONTEND=noninteractive run_with_timeout 120 apt-get update -y >/dev/null 2>&1 \
                || log_warn "apt-get update 失败或超时，继续尝试安装"
            DEBIAN_FRONTEND=noninteractive run_with_timeout 180 apt-get install -y curl ca-certificates >/dev/null 2>&1
            ;;
        dnf)
            run_with_timeout 120 dnf makecache -y >/dev/null 2>&1 || log_warn "dnf makecache 失败或超时"
            run_with_timeout 180 dnf install -y curl ca-certificates >/dev/null 2>&1
            ;;
        yum)
            run_with_timeout 120 yum makecache >/dev/null 2>&1 || log_warn "yum makecache 失败或超时"
            run_with_timeout 180 yum install -y curl ca-certificates >/dev/null 2>&1
            ;;
    esac

    if ! have_cmd curl; then
        log_error "curl 安装失败；请手动安装 curl 与 ca-certificates 后重试"
        exit 1
    fi
    log_ok "curl / ca-certificates 已安装"
}
ensure_dep_curl

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
