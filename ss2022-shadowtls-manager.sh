#!/usr/bin/env bash
# =============================================================================
# 项目名称: ss2022-shadowtls-manager
# 脚本功能: SS2022 (shadowsocks-rust) + ShadowTLS v3 一键安装管理脚本
# 适用系统: Debian 11/12, Ubuntu 20.04/22.04/24.04 (x86_64 / aarch64)
# 安全约束:
#   - 仅创建和管理本项目的目录与文件
#   - 不触碰 nftables 现有规则、不执行 nft flush / nft -f
#   - 不修改 /usr/local/sbin/ 中的其它脚本
#   - 不使用宽泛 rm -rf；删除前明确路径并需用户确认
# =============================================================================

# 不使用 set -e，避免菜单中因子命令失败被强制退出
set -o pipefail
umask 077

# -----------------------------------------------------------------------------
# 常量与路径定义（仅允许操作以下路径）
# -----------------------------------------------------------------------------
readonly SCRIPT_VERSION="v0.1.1-alpha"
readonly SCRIPT_NAME="ss2022-shadowtls-manager"

readonly PROJECT_ROOT="/root/ss2022-shadowtls-manager"
readonly PROJECT_ETC="/etc/ss2022-shadowtls-manager"
readonly PROJECT_INFO="${PROJECT_ETC}/info.json"
readonly PROJECT_BACKUP_DIR="${PROJECT_ETC}/backup"
readonly PROJECT_QRCODE_DIR="${PROJECT_ETC}/qrcode"

readonly SS_DIR="/etc/shadowsocks-rust"
readonly SS_CONFIG="${SS_DIR}/config.json"
readonly SS_BINARY="/usr/local/bin/ssserver"
readonly SS_SERVICE="/etc/systemd/system/ss2022.service"
readonly SS_SERVICE_NAME="ss2022.service"

readonly STLS_DIR="/etc/shadowtls"
readonly STLS_ENV="${STLS_DIR}/config.env"
readonly STLS_BINARY="/usr/local/bin/shadow-tls"
readonly STLS_SERVICE="/etc/systemd/system/shadowtls.service"
readonly STLS_SERVICE_NAME="shadowtls.service"

readonly SYSCTL_CONF="/etc/sysctl.d/99-ss2022-shadowtls.conf"

# 快捷命令 wrapper（由本项目创建）：通过标记字符串识别归属，避免误删同名文件
readonly SHORTCUT_PATH="/usr/local/bin/ss2022"
readonly SHORTCUT_MARKER="managed by ss2022-shadowtls-manager"

# 上游仓库
readonly SS_RUST_REPO="shadowsocks/shadowsocks-rust"
readonly STLS_REPO="ihciah/shadow-tls"

# 推荐 ShadowTLS 握手伪装域名示例（仅作建议，不强制）
readonly -a STLS_DEFAULT_DOMAINS=(
    "www.bing.com"
    "publicassets.cdn-apple.com"
    "weather-data.apple.com"
    "s0.awsstatic.com"
    "www.microsoft.com"
)

# -----------------------------------------------------------------------------
# 颜色与日志输出
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly C_RED=$'\033[0;31m'
    readonly C_GREEN=$'\033[0;32m'
    readonly C_YELLOW=$'\033[0;33m'
    readonly C_BLUE=$'\033[0;34m'
    readonly C_CYAN=$'\033[0;36m'
    readonly C_BOLD=$'\033[1m'
    readonly C_RESET=$'\033[0m'
else
    readonly C_RED=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_BLUE=""
    readonly C_CYAN=""
    readonly C_BOLD=""
    readonly C_RESET=""
fi

log_info()  { printf '%s[信息]%s %s\n' "${C_BLUE}"   "${C_RESET}" "$*"; }
log_ok()    { printf '%s[成功]%s %s\n' "${C_GREEN}"  "${C_RESET}" "$*"; }
log_warn()  { printf '%s[警告]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
log_error() { printf '%s[错误]%s %s\n' "${C_RED}"    "${C_RESET}" "$*" >&2; }
log_step()  { printf '\n%s>>> %s%s\n'  "${C_CYAN}"   "$*" "${C_RESET}"; }
hr()        { printf -- '----------------------------------------------------------------\n'; }

# 出错时给出下一步建议
suggest() {
    printf '%s[建议]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"
}

# 按任意键继续
press_any_key() {
    printf '\n%s按回车键继续...%s' "${C_CYAN}" "${C_RESET}"
    # shellcheck disable=SC2034
    read -r _
}

# -----------------------------------------------------------------------------
# 基础检查
# -----------------------------------------------------------------------------
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "本脚本必须以 root 身份运行"
        suggest "请使用：sudo -i 或 sudo bash $0"
        exit 1
    fi
}

# 检测发行版
OS_ID=""
OS_VERSION=""
detect_os() {
    if [[ ! -r /etc/os-release ]]; then
        log_error "无法读取 /etc/os-release，无法识别系统"
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    case "${OS_ID}" in
        debian)
            case "${OS_VERSION}" in
                11|12) : ;;
                *) log_warn "Debian ${OS_VERSION} 不在官方测试列表 (11/12)，仍尝试继续" ;;
            esac
            ;;
        ubuntu)
            case "${OS_VERSION}" in
                20.04|22.04|24.04) : ;;
                *) log_warn "Ubuntu ${OS_VERSION} 不在官方测试列表 (20.04/22.04/24.04)，仍尝试继续" ;;
            esac
            ;;
        *)
            log_error "暂不支持当前系统：${OS_ID} ${OS_VERSION}"
            suggest "本脚本仅适配 Debian 11/12 与 Ubuntu 20.04/22.04/24.04"
            exit 1
            ;;
    esac
}

# 检测 CPU 架构，映射到 shadowsocks-rust / shadow-tls release 命名
ARCH_RUST=""
ARCH_STLS=""
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        x86_64|amd64)
            ARCH_RUST="x86_64-unknown-linux-gnu"
            ARCH_STLS="x86_64-unknown-linux-musl"
            ;;
        aarch64|arm64)
            ARCH_RUST="aarch64-unknown-linux-gnu"
            ARCH_STLS="aarch64-unknown-linux-musl"
            ;;
        *)
            log_error "暂不支持的架构：${arch}"
            suggest "本脚本仅支持 x86_64 与 aarch64"
            exit 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# 依赖安装
# -----------------------------------------------------------------------------
ensure_apt_updated=0
apt_update_once() {
    if [[ "${ensure_apt_updated}" -eq 0 ]]; then
        log_info "更新软件包索引..."
        DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || {
            log_warn "apt-get update 失败，继续尝试安装"
        }
        ensure_apt_updated=1
    fi
}

install_pkg() {
    local pkg="$1"
    if command -v "${pkg}" >/dev/null 2>&1; then
        return 0
    fi
    apt_update_once
    log_info "安装依赖：${pkg}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >/dev/null 2>&1 || {
        log_warn "安装 ${pkg} 失败"
        return 1
    }
}

install_dependencies() {
    log_step "检查并安装基础依赖"
    local pkg
    for pkg in curl wget tar jq openssl ca-certificates xz-utils iproute2 dnsutils; do
        if ! command -v "${pkg%% *}" >/dev/null 2>&1; then
            apt_update_once
            log_info "安装：${pkg}"
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}" >/dev/null 2>&1 || \
                log_warn "依赖 ${pkg} 安装失败，可能影响部分功能"
        fi
    done
    # qrencode 可选
    if ! command -v qrencode >/dev/null 2>&1; then
        apt_update_once
        log_info "尝试安装 qrencode（可选）"
        DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode >/dev/null 2>&1 || \
            log_warn "qrencode 安装失败，二维码生成功能将不可用，主服务不受影响"
    fi
    log_ok "依赖检查完成"
}

# -----------------------------------------------------------------------------
# 项目目录与状态文件
# -----------------------------------------------------------------------------
ensure_project_dirs() {
    mkdir -p "${PROJECT_ROOT}" "${PROJECT_ETC}" "${PROJECT_BACKUP_DIR}" "${PROJECT_QRCODE_DIR}"
    mkdir -p "${SS_DIR}" "${STLS_DIR}"
    chmod 700 "${PROJECT_ETC}" "${PROJECT_BACKUP_DIR}" "${PROJECT_QRCODE_DIR}" "${SS_DIR}" "${STLS_DIR}" 2>/dev/null || true
    if [[ ! -f "${PROJECT_INFO}" ]]; then
        cat > "${PROJECT_INFO}" <<EOF
{
  "version": "${SCRIPT_VERSION}",
  "ss2022": {
    "installed": false,
    "method": "2022-blake3-aes-128-gcm",
    "password": "",
    "public_port": 0,
    "local_port": 0,
    "mode": "tcp_and_udp"
  },
  "shadowtls": {
    "enabled": false,
    "installed": false,
    "port": 0,
    "password": "",
    "tls_domain": "",
    "tls_port": 443
  },
  "network": {
    "listen_mode": "dual",
    "domain": "",
    "ipv4": "",
    "ipv6": ""
  }
}
EOF
        chmod 600 "${PROJECT_INFO}"
    fi
}

# 读取 info.json 中某个字段，失败返回空
info_get() {
    local path="$1"
    if [[ ! -r "${PROJECT_INFO}" ]]; then echo ""; return; fi
    jq -r "${path} // empty" "${PROJECT_INFO}" 2>/dev/null || echo ""
}

# 更新 info.json 中某个字段（值需 JSON 兼容）
info_set() {
    local path="$1" value="$2"
    local tmp info_dir
    info_dir="$(dirname "${PROJECT_INFO}")"
    # 临时文件放在 info.json 同目录，使 mv 同文件系统内尽量原子
    if ! tmp="$(mktemp --tmpdir="${info_dir}" info.XXXXXX 2>/dev/null)" \
            || [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        log_warn "更新 info.json 失败：创建临时文件失败 (${path})"
        return
    fi
    if jq "${path} = ${value}" "${PROJECT_INFO}" > "${tmp}" 2>/dev/null; then
        mv -f -- "${tmp}" "${PROJECT_INFO}"
        chmod 600 "${PROJECT_INFO}"
    else
        # tmp 路径必在 info.json 同目录（PROJECT_ETC 内），路径前缀校验后再删
        if [[ -n "${tmp}" && -f "${tmp}" && "${tmp}" == "${info_dir}"/* ]]; then
            rm -f -- "${tmp}"
        fi
        log_warn "更新 info.json 失败：${path}"
    fi
}

# -----------------------------------------------------------------------------
# 配置备份
# -----------------------------------------------------------------------------
backup_config() {
    local src="$1"
    [[ -e "${src}" ]] || return 0
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    local base
    base="$(basename "${src}")"
    local dst="${PROJECT_BACKUP_DIR}/${base}.${ts}.bak"
    cp -a "${src}" "${dst}" && log_info "已备份：${src} -> ${dst}"
}

# -----------------------------------------------------------------------------
# 端口与输入校验
# -----------------------------------------------------------------------------
is_valid_port() {
    local p="$1"
    [[ "${p}" =~ ^[0-9]+$ ]] || return 1
    (( p >= 1 && p <= 65535 ))
}

# 检查端口是否被占用；占用则输出占用进程
check_port_free() {
    local port="$1" proto="${2:-tcp}"
    local hit=""
    if command -v ss >/dev/null 2>&1; then
        if [[ "${proto}" == "udp" ]]; then
            hit="$(ss -lunp 2>/dev/null | awk -v p=":${port}" '$0 ~ p {print}')"
        else
            hit="$(ss -ltnp 2>/dev/null | awk -v p=":${port}" '$0 ~ p {print}')"
        fi
    fi
    if [[ -n "${hit}" ]]; then
        log_warn "端口 ${port}/${proto} 已被占用："
        printf '%s\n' "${hit}"
        return 1
    fi
    return 0
}

# 校验域名（基础格式）
is_valid_domain() {
    local d="$1"
    [[ "${d}" =~ ^[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?)+$ ]]
}

# -----------------------------------------------------------------------------
# 密码生成
# -----------------------------------------------------------------------------
# SS2022 需要 base64 编码的随机字节作为 PSK
#   - 2022-blake3-aes-128-gcm: 16 bytes -> base64
#   - 2022-blake3-aes-256-gcm: 32 bytes -> base64
generate_ss2022_password() {
    local method="$1"
    local bytes
    case "${method}" in
        2022-blake3-aes-128-gcm) bytes=16 ;;
        2022-blake3-aes-256-gcm) bytes=32 ;;
        *)
            log_error "未知 SS2022 加密方式：${method}"
            return 1
            ;;
    esac
    openssl rand -base64 "${bytes}" | tr -d '\n'
}

# 校验 SS2022 用户输入的 PSK 是否符合方法要求
#   - 2022-blake3-aes-128-gcm: 解码后 16 字节
#   - 2022-blake3-aes-256-gcm: 解码后 32 字节
# 返回 0 表示通过，非 0 表示失败（并向 stderr 打印原因）
validate_ss2022_psk_by_method() {
    local psk="$1" method="$2"
    local need
    case "${method}" in
        2022-blake3-aes-128-gcm) need=16 ;;
        2022-blake3-aes-256-gcm) need=32 ;;
        *)
            log_error "未知 SS2022 加密方式：${method}"
            return 2
            ;;
    esac
    if [[ -z "${psk}" ]]; then
        log_error "PSK 为空"
        return 1
    fi
    # base64 字母表校验
    if ! [[ "${psk}" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
        log_error "PSK 不是合法 base64（仅允许 A-Z a-z 0-9 + / =）"
        suggest "建议留空让脚本自动生成符合长度的 PSK"
        return 1
    fi
    local decoded_bytes
    decoded_bytes="$(printf '%s' "${psk}" | base64 -d 2>/dev/null | wc -c)"
    if [[ "${decoded_bytes}" != "${need}" ]]; then
        log_error "PSK 解码后长度为 ${decoded_bytes} 字节，方法 ${method} 要求 ${need} 字节"
        suggest "建议留空让脚本自动生成符合长度的 PSK"
        return 1
    fi
    return 0
}

# ShadowTLS 密码 — 较强随机串，不与 SS2022 复用
generate_shadowtls_password() {
    # 24 字节 -> base64（约 32 字符），去除特殊符号
    openssl rand -base64 24 | tr -d '\n=/+' | cut -c1-24
}

# -----------------------------------------------------------------------------
# URL / Base64 工具
# -----------------------------------------------------------------------------
b64_url_encode() {
    # 输入 stdin -> URL-safe base64 (无填充)
    local s
    s="$(base64 -w0 2>/dev/null || base64)"
    s="${s//+/-}"
    s="${s//\//_}"
    s="${s//=/}"
    printf '%s' "${s}"
}

url_encode() {
    # 简单 URL encode（用于域名、密码、节点名）
    local s="$1" out="" i ch
    for (( i=0; i<${#s}; i++ )); do
        ch="${s:i:1}"
        case "${ch}" in
            [A-Za-z0-9._~-]) out+="${ch}" ;;
            *) out+="$(printf '%%%02X' "'${ch}")" ;;
        esac
    done
    printf '%s' "${out}"
}

# -----------------------------------------------------------------------------
# 公网 IP 检测
# -----------------------------------------------------------------------------
detect_public_ipv4() {
    local ip=""
    ip="$(curl -fs4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    [[ -z "${ip}" ]] && ip="$(curl -fs4 --max-time 5 https://ifconfig.co 2>/dev/null || true)"
    [[ -z "${ip}" ]] && ip="$(curl -fs4 --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
    if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "${ip}"
    else
        printf ''
    fi
}

detect_public_ipv6() {
    local ip=""
    ip="$(curl -fs6 --max-time 5 https://api6.ipify.org 2>/dev/null || true)"
    [[ -z "${ip}" ]] && ip="$(curl -fs6 --max-time 5 https://ifconfig.co 2>/dev/null || true)"
    [[ -z "${ip}" ]] && ip="$(curl -fs6 --max-time 5 https://ipv6.icanhazip.com 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
    if [[ "${ip}" =~ : ]] && [[ "${ip}" != *" "* ]]; then
        printf '%s' "${ip}"
    else
        printf ''
    fi
}

refresh_public_ips() {
    log_step "检测公网 IP"
    local v4 v6
    v4="$(detect_public_ipv4)"
    v6="$(detect_public_ipv6)"
    if [[ -n "${v4}" ]]; then
        log_ok "公网 IPv4：${v4}"
        info_set ".network.ipv4" "\"${v4}\""
    else
        log_warn "未检测到公网 IPv4（或网络受限）"
    fi
    if [[ -n "${v6}" ]]; then
        log_ok "公网 IPv6：${v6}"
        info_set ".network.ipv6" "\"${v6}\""
    else
        log_warn "未检测到公网 IPv6"
    fi
}

# 格式化服务器地址，IPv6 自动加中括号
format_server_address() {
    local addr="$1"
    if [[ "${addr}" =~ : ]] && [[ "${addr}" != \[*\] ]] && ! [[ "${addr}" =~ ^[0-9a-zA-Z.-]+$ ]]; then
        printf '[%s]' "${addr}"
    else
        printf '%s' "${addr}"
    fi
}

# -----------------------------------------------------------------------------
# 下载与校验
# -----------------------------------------------------------------------------
# 安全清理临时目录：变量非空、目录存在、路径必须位于 /tmp/ 或 /var/tmp/
safe_remove_tmpdir() {
    local dir="$1"
    if [[ -n "${dir}" && -d "${dir}" && ( "${dir}" == /tmp/* || "${dir}" == /var/tmp/* ) ]]; then
        rm -rf -- "${dir}"
    else
        log_warn "跳过异常临时目录清理：${dir}"
    fi
}

# 安全清理临时文件：变量非空、文件存在、路径必须位于 /tmp/ 或 /var/tmp/
safe_remove_tmpfile() {
    local file="$1"
    if [[ -n "${file}" && -f "${file}" && ( "${file}" == /tmp/* || "${file}" == /var/tmp/* ) ]]; then
        rm -f -- "${file}"
    else
        log_warn "跳过异常临时文件清理：${file}"
    fi
}

github_latest_tag() {
    local repo="$1"
    curl -fsSL --max-time 15 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null
}

# 下载 shadowsocks-rust 二进制
download_shadowsocks_rust() {
    local version="$1"
    [[ -z "${version}" ]] && version="$(github_latest_tag "${SS_RUST_REPO}")"
    if [[ -z "${version}" ]]; then
        log_error "无法获取 shadowsocks-rust 最新版本"
        return 1
    fi
    log_info "shadowsocks-rust 版本：${version}"
    local fname="shadowsocks-${version}.${ARCH_RUST}.tar.xz"
    local url="https://github.com/${SS_RUST_REPO}/releases/download/${version}/${fname}"
    local tmpdir
    if ! tmpdir="$(mktemp -d -t ss2022-rust.XXXXXX 2>/dev/null)" || [[ -z "${tmpdir}" || ! -d "${tmpdir}" ]]; then
        log_error "创建临时目录失败"
        return 1
    fi
    log_info "下载：${url}"
    if ! curl -fSL --max-time 120 -o "${tmpdir}/ss.tar.xz" "${url}"; then
        log_error "下载 shadowsocks-rust 失败"
        safe_remove_tmpdir "${tmpdir}"
        return 1
    fi
    if ! tar -xJf "${tmpdir}/ss.tar.xz" -C "${tmpdir}"; then
        log_error "解压 shadowsocks-rust 失败"
        safe_remove_tmpdir "${tmpdir}"
        return 1
    fi
    if [[ ! -x "${tmpdir}/ssserver" ]]; then
        log_error "解压后未找到可执行 ssserver"
        safe_remove_tmpdir "${tmpdir}"
        return 1
    fi
    install -m 0755 "${tmpdir}/ssserver" "${SS_BINARY}"
    safe_remove_tmpdir "${tmpdir}"
    log_ok "已安装：${SS_BINARY}"
    info_set ".ss2022.binary_version" "\"${version}\""
}

# 下载 shadow-tls 二进制
download_shadowtls() {
    local version="$1"
    [[ -z "${version}" ]] && version="$(github_latest_tag "${STLS_REPO}")"
    if [[ -z "${version}" ]]; then
        log_error "无法获取 shadow-tls 最新版本"
        return 1
    fi
    log_info "shadow-tls 版本：${version}"
    # ihciah/shadow-tls 资源命名常见两种：
    #   shadow-tls-x86_64-unknown-linux-musl
    #   shadow-tls-aarch64-unknown-linux-musl
    local fname="shadow-tls-${ARCH_STLS}"
    local url="https://github.com/${STLS_REPO}/releases/download/${version}/${fname}"
    local tmpfile
    if ! tmpfile="$(mktemp -t ss2022-stls.XXXXXX 2>/dev/null)" || [[ -z "${tmpfile}" || ! -f "${tmpfile}" ]]; then
        log_error "创建临时文件失败"
        return 1
    fi
    log_info "下载：${url}"
    if ! curl -fSL --max-time 120 -o "${tmpfile}" "${url}"; then
        log_error "下载 shadow-tls 失败"
        safe_remove_tmpfile "${tmpfile}"
        return 1
    fi
    if [[ ! -s "${tmpfile}" ]]; then
        log_error "下载到的 shadow-tls 文件为空"
        safe_remove_tmpfile "${tmpfile}"
        return 1
    fi
    install -m 0755 "${tmpfile}" "${STLS_BINARY}"
    safe_remove_tmpfile "${tmpfile}"
    if ! "${STLS_BINARY}" --help >/dev/null 2>&1; then
        log_warn "shadow-tls --help 测试失败，二进制可能不兼容当前系统"
    fi
    log_ok "已安装：${STLS_BINARY}"
    info_set ".shadowtls.binary_version" "\"${version}\""
}

# -----------------------------------------------------------------------------
# 配置生成
# -----------------------------------------------------------------------------
# 根据监听模式与是否启用 ShadowTLS，决定 SS2022 监听地址
# 重要：启用 ShadowTLS 时 SS2022 后端固定监听 127.0.0.1，
#       listen_mode（ipv4/ipv6/dual）仅影响 ShadowTLS 公网监听与节点链接生成，
#       不影响 SS2022 后端本地监听地址。
#       如果未来要支持 ::1 作为后端，请通过单独的高级选项开启，不要默认改动这里。
ss2022_listen_address() {
    local stls_enabled
    stls_enabled="$(info_get '.shadowtls.enabled')"
    if [[ "${stls_enabled}" == "true" ]]; then
        echo "127.0.0.1"
        return
    fi
    local listen_mode
    listen_mode="$(info_get '.network.listen_mode')"
    [[ -z "${listen_mode}" ]] && listen_mode="dual"
    case "${listen_mode}" in
        ipv4) echo "0.0.0.0" ;;
        ipv6) echo "::" ;;
        *)    echo "::" ;;
    esac
}

# ShadowTLS 监听地址
shadowtls_listen_address() {
    local listen_mode
    listen_mode="$(info_get '.network.listen_mode')"
    [[ -z "${listen_mode}" ]] && listen_mode="dual"
    case "${listen_mode}" in
        ipv4) echo "0.0.0.0" ;;
        ipv6) echo "[::]" ;;
        *)    echo "[::]" ;;
    esac
}

write_ss2022_config() {
    backup_config "${SS_CONFIG}"
    local method password port mode listen
    method="$(info_get '.ss2022.method')"
    password="$(info_get '.ss2022.password')"
    mode="$(info_get '.ss2022.mode')"
    local stls_enabled
    stls_enabled="$(info_get '.shadowtls.enabled')"
    if [[ "${stls_enabled}" == "true" ]]; then
        port="$(info_get '.ss2022.local_port')"
    else
        port="$(info_get '.ss2022.public_port')"
    fi
    listen="$(ss2022_listen_address)"

    local tmp
    if ! tmp="$(mktemp -t ss2022-cfg.XXXXXX 2>/dev/null)" || [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        log_error "创建临时文件失败"
        return 1
    fi
    cat > "${tmp}" <<EOF
{
    "server": "${listen}",
    "server_port": ${port},
    "method": "${method}",
    "password": "${password}",
    "mode": "${mode}",
    "timeout": 300,
    "fast_open": false,
    "no_delay": true
}
EOF
    if ! jq . "${tmp}" >/dev/null 2>&1; then
        log_error "SS2022 配置 JSON 校验失败"
        safe_remove_tmpfile "${tmp}"
        return 1
    fi
    install -m 0600 "${tmp}" "${SS_CONFIG}"
    safe_remove_tmpfile "${tmp}"
    log_ok "已写入 SS2022 配置：${SS_CONFIG}"
}

write_shadowtls_env() {
    backup_config "${STLS_ENV}"
    local stls_listen stls_port stls_password tls_domain tls_port ss_local_port
    stls_listen="$(shadowtls_listen_address)"
    stls_port="$(info_get '.shadowtls.port')"
    stls_password="$(info_get '.shadowtls.password')"
    tls_domain="$(info_get '.shadowtls.tls_domain')"
    tls_port="$(info_get '.shadowtls.tls_port')"
    [[ -z "${tls_port}" || "${tls_port}" == "0" ]] && tls_port=443
    ss_local_port="$(info_get '.ss2022.local_port')"

    # ShadowTLS 转发目标必须与 SS2022 后端监听地址一致：默认统一 127.0.0.1
    # （listen_mode 不影响后端本地地址；如需 ::1 作为后端请走单独的高级选项）
    local server_target="127.0.0.1:${ss_local_port}"

    local tmp
    if ! tmp="$(mktemp -t ss2022-stlsenv.XXXXXX 2>/dev/null)" || [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        log_error "创建临时文件失败"
        return 1
    fi
    cat > "${tmp}" <<EOF
# shadow-tls 运行环境变量（由 ${SCRIPT_NAME} 生成）
LISTEN_ADDR=${stls_listen}:${stls_port}
SERVER_ADDR=${server_target}
TLS_NAMES=${tls_domain}:${tls_port}
PASSWORD=${stls_password}
RUST_LOG=info
EOF
    install -m 0600 "${tmp}" "${STLS_ENV}"
    safe_remove_tmpfile "${tmp}"
    log_ok "已写入 ShadowTLS 环境配置：${STLS_ENV}"
}

write_ss2022_service() {
    backup_config "${SS_SERVICE}"
    local tmp
    if ! tmp="$(mktemp -t ss2022-svc.XXXXXX 2>/dev/null)" || [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        log_error "创建临时文件失败"
        return 1
    fi
    cat > "${tmp}" <<EOF
[Unit]
Description=Shadowsocks 2022 (ssserver) - managed by ${SCRIPT_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SS_BINARY} -c ${SS_CONFIG}
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    install -m 0644 "${tmp}" "${SS_SERVICE}"
    safe_remove_tmpfile "${tmp}"
    systemctl daemon-reload >/dev/null 2>&1 || true
    log_ok "已写入 systemd：${SS_SERVICE}"
}

write_shadowtls_service() {
    backup_config "${STLS_SERVICE}"
    local tmp
    if ! tmp="$(mktemp -t ss2022-stlssvc.XXXXXX 2>/dev/null)" || [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        log_error "创建临时文件失败"
        return 1
    fi
    cat > "${tmp}" <<EOF
[Unit]
Description=ShadowTLS v3 server - managed by ${SCRIPT_NAME}
After=network-online.target ${SS_SERVICE_NAME}
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${STLS_ENV}
ExecStart=${STLS_BINARY} --v3 server --listen \${LISTEN_ADDR} --server \${SERVER_ADDR} --tls \${TLS_NAMES} --password \${PASSWORD}
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    install -m 0644 "${tmp}" "${STLS_SERVICE}"
    safe_remove_tmpfile "${tmp}"
    systemctl daemon-reload >/dev/null 2>&1 || true
    log_ok "已写入 systemd：${STLS_SERVICE}"
}

# -----------------------------------------------------------------------------
# 服务管理
# -----------------------------------------------------------------------------
restart_service() {
    local name="$1"
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable "${name}" >/dev/null 2>&1 || true
    if systemctl restart "${name}"; then
        sleep 1
        if systemctl is-active --quiet "${name}"; then
            log_ok "${name} 已运行"
            return 0
        fi
    fi
    log_error "${name} 启动失败，输出最近日志："
    systemctl status "${name}" --no-pager 2>&1 | sed -n '1,20p'
    journalctl -u "${name}" -n 50 --no-pager 2>&1 | sed -n '1,80p'
    suggest "请检查端口占用、配置文件、二进制权限"
    return 1
}

stop_service() {
    local name="$1"
    systemctl stop "${name}" >/dev/null 2>&1 || true
    systemctl is-active --quiet "${name}" && log_warn "${name} 仍在运行" || log_ok "${name} 已停止"
}

start_service() {
    local name="$1"
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable "${name}" >/dev/null 2>&1 || true
    systemctl start "${name}" >/dev/null 2>&1
    sleep 1
    if systemctl is-active --quiet "${name}"; then
        log_ok "${name} 已启动"
    else
        log_error "${name} 启动失败"
        systemctl status "${name}" --no-pager 2>&1 | sed -n '1,20p'
    fi
}

status_service() {
    local name="$1"
    systemctl status "${name}" --no-pager 2>&1 | sed -n '1,25p'
}

journal_follow() {
    local name="$1"
    log_info "正在跟随 ${name} 日志，按 Ctrl+C 退出"
    journalctl -u "${name}" -f --no-pager
}

# -----------------------------------------------------------------------------
# 防火墙处理（IPv4 + IPv6；不动 nftables 现有规则）
# -----------------------------------------------------------------------------
detect_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1; then
        echo "ufw"; return
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "firewalld"; return
    fi
    if command -v nft >/dev/null 2>&1 && systemctl is-active --quiet nftables 2>/dev/null; then
        echo "nftables"; return
    fi
    if command -v nft >/dev/null 2>&1; then
        echo "nftables-present"; return
    fi
    echo "none"
}

open_firewall_port() {
    local port="$1" proto="${2:-tcp}"
    local fw
    fw="$(detect_firewall)"
    case "${fw}" in
        ufw)
            log_info "ufw：放行 ${port}/${proto}"
            ufw allow "${port}/${proto}" >/dev/null 2>&1 || log_warn "ufw 放行失败"
            ;;
        firewalld)
            log_info "firewalld：放行 ${port}/${proto}"
            firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1 || log_warn "firewalld 放行失败"
            firewall-cmd --reload >/dev/null 2>&1 || true
            ;;
        nftables|nftables-present)
            log_warn "检测到 nftables（可能由 nftables-nat-rust-enhanced 管理），出于安全本脚本不会自动修改 nftables 规则"
            log_warn "请自行确认放行端口 ${port}/${proto}（IPv4 与 IPv6 均需考虑），示例命令仅作参考："
            printf '   nft add rule inet filter input %s dport %s accept\n' "${proto}" "${port}"
            ;;
        none)
            log_info "未检测到主动防火墙，端口 ${port}/${proto} 默认应可访问"
            ;;
    esac
}

suggest_close_port() {
    local port="$1" proto="${2:-tcp}"
    local fw
    fw="$(detect_firewall)"
    case "${fw}" in
        ufw)
            read -r -p "是否删除 ufw 旧规则 ${port}/${proto}? [y/N]: " ans
            [[ "${ans}" =~ ^[Yy]$ ]] && ufw delete allow "${port}/${proto}" >/dev/null 2>&1 || true
            ;;
        firewalld)
            read -r -p "是否删除 firewalld 旧规则 ${port}/${proto}? [y/N]: " ans
            if [[ "${ans}" =~ ^[Yy]$ ]]; then
                firewall-cmd --permanent --remove-port="${port}/${proto}" >/dev/null 2>&1 || true
                firewall-cmd --reload >/dev/null 2>&1 || true
            fi
            ;;
        nftables|nftables-present)
            log_warn "nftables 旧端口规则请用户自行检查与清理，本脚本不会自动 nft delete"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# 安装 / 卸载 SS2022
# -----------------------------------------------------------------------------
install_ss2022() {
    log_step "安装 / 重装 SS2022 (shadowsocks-rust)"
    install_dependencies
    ensure_project_dirs
    hint_time_before_install

    # 现有安装提示
    if [[ "$(info_get '.ss2022.installed')" == "true" ]]; then
        log_warn "SS2022 已安装，继续将重装并覆盖配置（旧配置会备份）"
        read -r -p "是否继续? [y/N]: " ans
        [[ "${ans}" =~ ^[Yy]$ ]] || { log_info "已取消"; return; }
    fi

    # 选择加密方式
    echo "请选择 SS2022 加密方式："
    echo "  1) 2022-blake3-aes-128-gcm  (默认)"
    echo "  2) 2022-blake3-aes-256-gcm"
    read -r -p "选择 [1-2，默认 1]: " m
    local method
    case "${m}" in
        2) method="2022-blake3-aes-256-gcm" ;;
        *) method="2022-blake3-aes-128-gcm" ;;
    esac

    # 端口
    local port
    while :; do
        read -r -p "请输入 SS2022 监听端口 [默认随机 20000-60000]: " port
        if [[ -z "${port}" ]]; then
            port=$(( (RANDOM % 40000) + 20000 ))
        fi
        if ! is_valid_port "${port}"; then
            log_error "端口非法"; continue
        fi
        if ! check_port_free "${port}" tcp; then
            read -r -p "端口被占用，仍使用? [y/N]: " a
            [[ "${a}" =~ ^[Yy]$ ]] && break
            continue
        fi
        break
    done

    # 密码
    local password
    read -r -p "是否自动生成 SS2022 密码? [Y/n]: " ans
    if [[ "${ans}" =~ ^[Nn]$ ]]; then
        # 用户自定义 PSK 时必须满足 method 对应长度
        while :; do
            read -r -s -p "请输入 SS2022 密码（base64 编码的 PSK，建议留空自动生成）: " password
            echo
            if [[ -z "${password}" ]]; then
                password="$(generate_ss2022_password "${method}")"
                break
            fi
            if validate_ss2022_psk_by_method "${password}" "${method}"; then
                break
            fi
            log_warn "PSK 校验未通过，请重新输入或留空自动生成"
        done
    else
        password="$(generate_ss2022_password "${method}")"
    fi
    [[ -z "${password}" ]] && { log_error "密码生成失败"; return 1; }

    # mode（UDP 模式）
    echo "请选择 SS2022 转发模式："
    echo "  1) tcp_and_udp  (默认，TCP+UDP)"
    echo "  2) tcp_only     (仅 TCP；启用 ShadowTLS 时推荐)"
    echo "  3) udp_only     (仅 UDP，少用)"
    read -r -p "选择 [1-3，默认 1]: " mm
    local mode
    case "${mm}" in
        2) mode="tcp_only" ;;
        3) mode="udp_only" ;;
        *) mode="tcp_and_udp" ;;
    esac

    # 监听模式
    set_listen_mode_interactive

    # 写入状态
    info_set ".ss2022.installed"   "true"
    info_set ".ss2022.method"      "\"${method}\""
    info_set ".ss2022.password"    "$(jq -nr --arg v "${password}" '$v|tojson')"
    info_set ".ss2022.public_port" "${port}"
    info_set ".ss2022.local_port"  "${port}"
    info_set ".ss2022.mode"        "\"${mode}\""

    # 下载二进制
    if [[ ! -x "${SS_BINARY}" ]]; then
        download_shadowsocks_rust "" || { log_error "ssserver 安装失败"; return 1; }
    else
        log_info "ssserver 已存在，跳过下载（可通过菜单 11 更新）"
    fi

    write_ss2022_config || return 1
    write_ss2022_service

    # 防火墙
    local stls_enabled
    stls_enabled="$(info_get '.shadowtls.enabled')"
    if [[ "${stls_enabled}" != "true" ]]; then
        case "${mode}" in
            tcp_only)    open_firewall_port "${port}" tcp ;;
            udp_only)    open_firewall_port "${port}" udp ;;
            tcp_and_udp) open_firewall_port "${port}" tcp; open_firewall_port "${port}" udp ;;
        esac
    fi

    restart_service "${SS_SERVICE_NAME}" || return 1
    refresh_public_ips
    log_ok "SS2022 安装完成"

    # 安装成功后询问是否创建快捷命令（默认 Y）
    if ! shortcut_installed; then
        read -r -p "是否创建快捷命令 ss2022（以后直接输入 ss2022 进入管理菜单）? [Y/n]: " _ans
        if [[ ! "${_ans}" =~ ^[Nn]$ ]]; then
            install_shortcut_command || log_warn "快捷命令安装失败（可稍后在「高级设置」中重试）"
        fi
    fi

    show_node_info
}

uninstall_ss2022() {
    log_step "卸载 SS2022"

    # 依赖检查：ShadowTLS 依赖 SS2022 作为后端，避免悬空
    local stls_enabled stls_installed
    stls_enabled="$(info_get '.shadowtls.enabled')"
    stls_installed="$(info_get '.shadowtls.installed')"
    if [[ "${stls_enabled}" == "true" || "${stls_installed}" == "true" ]]; then
        log_warn "检测到 ShadowTLS 状态：enabled=${stls_enabled:-false} / installed=${stls_installed:-false}"
        log_warn "ShadowTLS 依赖 SS2022 作为后端，若仅卸载 SS2022 将导致 ShadowTLS 悬空（无法转发）"
        echo "请选择处理方式："
        echo "  1) 取消，先用菜单 21/22 停用或卸载 ShadowTLS，再回来卸载 SS2022（推荐）"
        echo "  2) 现在同时卸载 ShadowTLS（将进入 ShadowTLS 卸载流程，仍需输入 YES）"
        echo "  3) 取消"
        read -r -p "选择 [1-3，默认 1]: " dep_choice
        case "${dep_choice}" in
            2)
                log_info "先进入 ShadowTLS 卸载流程..."
                uninstall_shadowtls
                if [[ "$(info_get '.shadowtls.installed')" == "true" ]]; then
                    log_warn "ShadowTLS 仍处于已安装状态，取消 SS2022 卸载以避免悬空"
                    return
                fi
                ;;
            *)
                log_info "已取消 SS2022 卸载"
                return
                ;;
        esac
    fi

    echo "将删除以下路径（仅限本项目）："
    echo "  ${SS_BINARY}"
    echo "  ${SS_CONFIG}"
    echo "  ${SS_SERVICE}"
    echo "  ${SS_DIR}（仅当为空）"
    read -r -p "请输入 YES 确认删除： " ans
    [[ "${ans}" == "YES" ]] || { log_info "已取消"; return; }
    systemctl disable --now "${SS_SERVICE_NAME}" >/dev/null 2>&1 || true
    [[ -f "${SS_SERVICE}" ]] && backup_config "${SS_SERVICE}" && rm -f "${SS_SERVICE}"
    [[ -f "${SS_CONFIG}" ]]  && backup_config "${SS_CONFIG}"  && rm -f "${SS_CONFIG}"
    [[ -x "${SS_BINARY}" ]]  && rm -f "${SS_BINARY}"
    rmdir "${SS_DIR}" 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    info_set ".ss2022.installed" "false"
    log_ok "SS2022 已卸载"
}

# -----------------------------------------------------------------------------
# ShadowTLS 启用 / 停用 / 卸载
# -----------------------------------------------------------------------------
test_tls13_domain() {
    local domain="$1" port="${2:-443}"
    if ! getent hosts "${domain}" >/dev/null 2>&1; then
        log_warn "域名 ${domain} 解析失败（仅警告）"
        return 1
    fi
    if command -v openssl >/dev/null 2>&1; then
        local out
        out="$(echo | timeout 6 openssl s_client -servername "${domain}" -connect "${domain}:${port}" -tls1_3 2>&1 | head -n 30)"
        if echo "${out}" | grep -q "TLSv1.3"; then
            return 0
        fi
        log_warn "未确认 ${domain}:${port} 支持 TLS 1.3（仅警告）"
        return 1
    fi
    return 0
}

enable_shadowtls() {
    log_step "启用 ShadowTLS v3"
    if [[ "$(info_get '.ss2022.installed')" != "true" ]]; then
        log_error "请先安装 SS2022"; return 1
    fi
    install_dependencies
    ensure_project_dirs
    hint_time_before_install

    if [[ ! -x "${STLS_BINARY}" ]]; then
        download_shadowtls "" || { log_error "shadow-tls 安装失败"; return 1; }
    else
        log_info "shadow-tls 已存在，跳过下载（可通过菜单 11 之后再次更新）"
    fi

    # 端口
    local stls_port
    while :; do
        read -r -p "请输入 ShadowTLS 公网端口 [默认 8443，常见 443/8443/2053/2087]: " stls_port
        [[ -z "${stls_port}" ]] && stls_port=8443
        is_valid_port "${stls_port}" || { log_error "端口非法"; continue; }
        if ! check_port_free "${stls_port}" tcp; then
            read -r -p "端口被占用，仍使用? [y/N]: " a
            [[ "${a}" =~ ^[Yy]$ ]] && break
            continue
        fi
        break
    done

    # 伪装域名
    echo "推荐的伪装域名示例（仅建议，可自行输入其它支持 TLS 1.3 的域名）："
    local i=1
    for d in "${STLS_DEFAULT_DOMAINS[@]}"; do
        echo "  $i) ${d}"
        ((i++))
    done
    local domain
    while :; do
        read -r -p "请输入伪装域名（或选编号 1-${#STLS_DEFAULT_DOMAINS[@]}）: " domain
        if [[ "${domain}" =~ ^[0-9]+$ ]] && (( domain >= 1 && domain <= ${#STLS_DEFAULT_DOMAINS[@]} )); then
            domain="${STLS_DEFAULT_DOMAINS[$((domain-1))]}"
        fi
        is_valid_domain "${domain}" || { log_error "域名格式错误"; continue; }
        break
    done
    test_tls13_domain "${domain}" 443 || log_warn "继续使用 ${domain}（检测失败不阻止安装）"

    # 密码（不与 SS2022 重复）
    local stls_password ss_password
    ss_password="$(info_get '.ss2022.password')"
    while :; do
        stls_password="$(generate_shadowtls_password)"
        [[ "${stls_password}" != "${ss_password}" ]] && break
    done
    read -r -p "是否自定义 ShadowTLS 密码? [y/N]: " ans
    if [[ "${ans}" =~ ^[Yy]$ ]]; then
        local p1
        read -r -s -p "请输入 ShadowTLS 密码（留空使用自动生成）: " p1; echo
        if [[ -n "${p1}" ]]; then
            if [[ "${p1}" == "${ss_password}" ]]; then
                log_error "ShadowTLS 密码不可与 SS2022 密码相同"
                return 1
            fi
            stls_password="${p1}"
        fi
    fi

    # SS2022 本机端口
    local ss_local_port
    ss_local_port="$(info_get '.ss2022.local_port')"
    if [[ -z "${ss_local_port}" || "${ss_local_port}" == "0" ]]; then
        ss_local_port="$(info_get '.ss2022.public_port')"
    fi

    # 提示 UDP 处理
    cat <<EOF

${C_YELLOW}[UDP 提示]${C_RESET} ShadowTLS 主要处理 TCP。启用后建议：
  - 默认推荐 SS2022 改为 tcp_only
  - 若需 UDP，可在菜单 70 中选择保留单独 UDP 公网端口
  - 不建议依赖 UDP over TCP（性能/兼容性风险）
EOF
    read -r -p "是否将 SS2022 切换为 tcp_only? [Y/n]: " ans
    if [[ ! "${ans}" =~ ^[Nn]$ ]]; then
        info_set ".ss2022.mode" "\"tcp_only\""
    fi

    # 备份旧端口防火墙规则提示
    local old_pub_port
    old_pub_port="$(info_get '.ss2022.public_port')"

    # 更新状态
    info_set ".shadowtls.enabled"    "true"
    info_set ".shadowtls.installed"  "true"
    info_set ".shadowtls.port"       "${stls_port}"
    info_set ".shadowtls.password"   "$(jq -nr --arg v "${stls_password}" '$v|tojson')"
    info_set ".shadowtls.tls_domain" "\"${domain}\""
    info_set ".shadowtls.tls_port"   "443"
    info_set ".ss2022.local_port"    "${ss_local_port}"

    # 写配置并重启
    write_ss2022_config    || return 1
    write_shadowtls_env    || return 1
    write_ss2022_service
    write_shadowtls_service

    # 防火墙：放行 ShadowTLS 端口，建议关掉旧 SS2022 公网端口
    open_firewall_port "${stls_port}" tcp
    if [[ -n "${old_pub_port}" && "${old_pub_port}" != "0" && "${old_pub_port}" != "${stls_port}" ]]; then
        log_info "SS2022 旧公网端口 ${old_pub_port} 不再需要公网放行"
        suggest_close_port "${old_pub_port}" tcp
        suggest_close_port "${old_pub_port}" udp
    fi

    restart_service "${SS_SERVICE_NAME}"
    restart_service "${STLS_SERVICE_NAME}"
    log_ok "ShadowTLS v3 已启用"
    show_node_info
}

disable_shadowtls() {
    log_step "停用 ShadowTLS（保留二进制和配置文件）"
    [[ "$(info_get '.shadowtls.enabled')" == "true" ]] || { log_info "ShadowTLS 当前未启用"; return; }
    systemctl disable --now "${STLS_SERVICE_NAME}" >/dev/null 2>&1 || true
    info_set ".shadowtls.enabled" "false"
    # 仅当 SS2022 已安装时才恢复其公网监听并重启
    if [[ "$(info_get '.ss2022.installed')" == "true" ]]; then
        write_ss2022_config
        restart_service "${SS_SERVICE_NAME}"
        log_ok "ShadowTLS 已停用，SS2022 已切回公网监听"
    else
        log_warn "状态异常：SS2022 未安装但 ShadowTLS 此前为启用状态；已停用 ShadowTLS，跳过 SS2022 恢复与重启"
    fi
}

uninstall_shadowtls() {
    log_step "卸载 ShadowTLS"
    echo "将删除以下路径（仅限本项目）："
    echo "  ${STLS_BINARY}"
    echo "  ${STLS_ENV}"
    echo "  ${STLS_SERVICE}"
    echo "  ${STLS_DIR}（仅当为空）"
    read -r -p "请输入 YES 确认删除： " ans
    [[ "${ans}" == "YES" ]] || { log_info "已取消"; return; }
    systemctl disable --now "${STLS_SERVICE_NAME}" >/dev/null 2>&1 || true
    [[ -f "${STLS_SERVICE}" ]] && backup_config "${STLS_SERVICE}" && rm -f "${STLS_SERVICE}"
    [[ -f "${STLS_ENV}" ]]     && backup_config "${STLS_ENV}"     && rm -f "${STLS_ENV}"
    [[ -x "${STLS_BINARY}" ]]  && rm -f "${STLS_BINARY}"
    rmdir "${STLS_DIR}" 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    info_set ".shadowtls.enabled"   "false"
    info_set ".shadowtls.installed" "false"
    # 仅当 SS2022 已安装时才恢复其公网监听并重启
    if [[ "$(info_get '.ss2022.installed')" == "true" ]]; then
        write_ss2022_config
        restart_service "${SS_SERVICE_NAME}"
    else
        log_info "SS2022 未安装，跳过恢复 SS2022 公网监听与重启 ss2022.service"
    fi
    log_ok "ShadowTLS 已卸载"
}

# -----------------------------------------------------------------------------
# 快捷命令 wrapper：/usr/local/bin/ss2022
# 用 wrapper 脚本而非软链接；通过标记 ${SHORTCUT_MARKER} 识别归属
# -----------------------------------------------------------------------------

# 返回 0 表示本项目的快捷命令已安装；其它情况返回 1
shortcut_installed() {
    [[ -f "${SHORTCUT_PATH}" ]] && grep -q "${SHORTCUT_MARKER}" "${SHORTCUT_PATH}" 2>/dev/null
}

# 创建 / 覆盖更新 wrapper
install_shortcut_command() {
    log_step "安装快捷命令 ${SHORTCUT_PATH}"
    # 解析当前脚本真实路径
    local real_path
    real_path="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null)"
    if [[ -z "${real_path}" || ! -f "${real_path}" ]]; then
        real_path="/root/ss2022-shadowtls-manager/ss2022-shadowtls-manager.sh"
        log_warn "无法解析当前脚本真实路径，回退到默认：${real_path}"
    fi

    # 已存在文件的归属判定
    if [[ -e "${SHORTCUT_PATH}" ]]; then
        if grep -q "${SHORTCUT_MARKER}" "${SHORTCUT_PATH}" 2>/dev/null; then
            log_info "已存在本项目创建的快捷命令，将覆盖更新"
        else
            log_error "${SHORTCUT_PATH} 已存在且不是本项目创建（缺少标记），拒绝覆盖"
            suggest "请手动检查该文件后再决定是否安装快捷命令"
            return 1
        fi
    fi

    # 通过临时文件写入，再 install -m 0755
    local tmp
    if ! tmp="$(mktemp -t ss2022-wrap.XXXXXX 2>/dev/null)" \
            || [[ -z "${tmp}" || ! -f "${tmp}" ]]; then
        log_error "创建临时文件失败"
        return 1
    fi
    cat > "${tmp}" <<EOF
#!/usr/bin/env bash
# ${SHORTCUT_MARKER}
exec "${real_path}" "\$@"
EOF
    if ! install -m 0755 "${tmp}" "${SHORTCUT_PATH}"; then
        safe_remove_tmpfile "${tmp}"
        log_error "安装快捷命令失败：${SHORTCUT_PATH}"
        return 1
    fi
    safe_remove_tmpfile "${tmp}"
    log_ok "已安装快捷命令：${SHORTCUT_PATH}"
    log_info "以后可以直接输入 ss2022 打开管理菜单"
}

# 仅删除带本项目标记的 wrapper；其它同名文件一律不动
remove_shortcut_command() {
    log_step "删除快捷命令 ${SHORTCUT_PATH}"
    if [[ ! -e "${SHORTCUT_PATH}" ]]; then
        log_info "${SHORTCUT_PATH} 不存在，跳过"
        return 0
    fi
    if ! grep -q "${SHORTCUT_MARKER}" "${SHORTCUT_PATH}" 2>/dev/null; then
        log_error "${SHORTCUT_PATH} 不是本项目创建（缺少标记 \"${SHORTCUT_MARKER}\"），拒绝删除"
        suggest "请手动检查该文件后再决定是否删除"
        return 1
    fi
    if rm -f -- "${SHORTCUT_PATH}"; then
        log_ok "已删除：${SHORTCUT_PATH}"
    else
        log_error "删除失败：${SHORTCUT_PATH}"
        return 1
    fi
}

# 一键完整卸载：仅删除本项目创建的内容；不动 nftables / apt 包 / 其它代理
uninstall_all() {
    log_step "一键完整卸载"
    cat <<EOF
将停止并禁用以下服务（如存在）：
  - ${STLS_SERVICE_NAME}
  - ${SS_SERVICE_NAME}

将删除以下路径（仅限本项目）：
  - ${STLS_BINARY}
  - ${SS_BINARY}
  - ${SS_CONFIG}
  - ${STLS_ENV}
  - ${SS_SERVICE}
  - ${STLS_SERVICE}
  - ${PROJECT_ETC}/        （含 info.json / qrcode / backup）
  - ${SS_DIR}/             （仅当为空时删除目录本身）
  - ${STLS_DIR}/           （仅当为空时删除目录本身）
  - ${SHORTCUT_PATH}        （仅当包含标记 "${SHORTCUT_MARKER}" 时；否则跳过）

不会删除：
  - 任何 nftables 规则 / /etc/nftables.conf
  - nftables-nat-rust-enhanced 项目
  - /usr/local/sbin/ 下非本项目文件
  - 其它代理程序
  - 已安装的 apt 包（curl / jq / qrencode / chrony / wget 等）
  - 防火墙的 ufw / firewalld 端口规则（请按需自行清理）

卸载前会将所有现存配置备份到 /root/ss2022-shadowtls-backup-<日期>/
EOF
    read -r -p "请输入 YES 确认完整卸载： " ans
    [[ "${ans}" == "YES" ]] || { log_info "已取消"; return; }

    # 1) 备份
    local ts backup_dir
    ts="$(date +%Y%m%d-%H%M%S)"
    backup_dir="/root/ss2022-shadowtls-backup-${ts}"
    if mkdir -p "${backup_dir}" 2>/dev/null; then
        chmod 700 "${backup_dir}" 2>/dev/null || true
        local src
        for src in "${SS_CONFIG}" "${STLS_ENV}" "${SS_SERVICE}" "${STLS_SERVICE}" "${PROJECT_INFO}"; do
            [[ -f "${src}" ]] && cp -a -- "${src}" "${backup_dir}/" 2>/dev/null && \
                log_info "已备份：${src}"
        done
        # 备份目录中所有备份/二维码副本（如有）
        if [[ -d "${PROJECT_BACKUP_DIR}" ]]; then
            cp -a -- "${PROJECT_BACKUP_DIR}" "${backup_dir}/" 2>/dev/null && \
                log_info "已备份：${PROJECT_BACKUP_DIR}"
        fi
        log_ok "备份完成：${backup_dir}"
    else
        log_warn "创建备份目录失败：${backup_dir}（继续卸载）"
    fi

    # 2) 停止并禁用服务（不存在则跳过）
    if systemctl list-unit-files 2>/dev/null | grep -q "^${STLS_SERVICE_NAME}"; then
        systemctl disable --now "${STLS_SERVICE_NAME}" >/dev/null 2>&1 || true
        log_info "已停止并禁用：${STLS_SERVICE_NAME}"
    else
        log_info "跳过（不存在）：${STLS_SERVICE_NAME}"
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SS_SERVICE_NAME}"; then
        systemctl disable --now "${SS_SERVICE_NAME}" >/dev/null 2>&1 || true
        log_info "已停止并禁用：${SS_SERVICE_NAME}"
    else
        log_info "跳过（不存在）：${SS_SERVICE_NAME}"
    fi

    # 3) 删除本项目文件（每个路径明确写出，避免宽泛 rm -rf）
    local removed=()
    local skipped=()

    _safe_rm_file() {
        local p="$1"
        if [[ -e "${p}" || -L "${p}" ]]; then
            rm -f -- "${p}" 2>/dev/null && removed+=("${p}") || skipped+=("${p}（删除失败）")
        else
            skipped+=("${p}（不存在）")
        fi
    }

    _safe_rm_file "${STLS_SERVICE}"
    _safe_rm_file "${SS_SERVICE}"
    _safe_rm_file "${STLS_ENV}"
    _safe_rm_file "${SS_CONFIG}"
    _safe_rm_file "${STLS_BINARY}"
    _safe_rm_file "${SS_BINARY}"

    # 快捷命令 wrapper：必须带项目标记才删除，否则跳过保护
    if [[ -e "${SHORTCUT_PATH}" ]]; then
        if grep -q "${SHORTCUT_MARKER}" "${SHORTCUT_PATH}" 2>/dev/null; then
            if rm -f -- "${SHORTCUT_PATH}" 2>/dev/null; then
                removed+=("${SHORTCUT_PATH}")
            else
                skipped+=("${SHORTCUT_PATH}（删除失败）")
            fi
        else
            skipped+=("${SHORTCUT_PATH}（不是本项目创建，保留）")
        fi
    else
        skipped+=("${SHORTCUT_PATH}（不存在）")
    fi

    # 4) PROJECT_ETC：项目自有目录，整目录删除（路径前缀严格校验）
    if [[ -d "${PROJECT_ETC}" && "${PROJECT_ETC}" == "/etc/ss2022-shadowtls-manager" ]]; then
        rm -rf -- "${PROJECT_ETC}" && removed+=("${PROJECT_ETC}/") || skipped+=("${PROJECT_ETC}/（删除失败）")
    else
        skipped+=("${PROJECT_ETC}/（不存在或路径不匹配，跳过）")
    fi

    # 5) SS_DIR / STLS_DIR：仅当为空时删除（其它进程可能仍有文件）
    if [[ -d "${SS_DIR}" ]]; then
        if rmdir "${SS_DIR}" 2>/dev/null; then
            removed+=("${SS_DIR}/")
        else
            skipped+=("${SS_DIR}/（非空或删除失败，保留）")
        fi
    fi
    if [[ -d "${STLS_DIR}" ]]; then
        if rmdir "${STLS_DIR}" 2>/dev/null; then
            removed+=("${STLS_DIR}/")
        else
            skipped+=("${STLS_DIR}/（非空或删除失败，保留）")
        fi
    fi

    # 6) systemd 重载
    systemctl daemon-reload >/dev/null 2>&1 || true

    # 7) 报告
    hr
    log_ok "卸载完成"
    echo "备份目录：${backup_dir}"
    echo
    echo "已删除路径："
    if (( ${#removed[@]} > 0 )); then
        printf '  - %s\n' "${removed[@]}"
    else
        echo "  (无)"
    fi
    echo
    echo "跳过 / 保留路径："
    if (( ${#skipped[@]} > 0 )); then
        printf '  - %s\n' "${skipped[@]}"
    else
        echo "  (无)"
    fi
    hr
    cat <<EOF
未删除内容说明：
  - 未触碰 nftables 规则与 /etc/nftables.conf
  - 未触碰 nftables-nat-rust-enhanced 项目
  - 未卸载 apt 包（curl / jq / qrencode / chrony 等仍保留，可按需 apt remove）
  - 未清理 ufw / firewalld 端口规则；若不再使用，请自行检查并删除：
      * SS2022 公网端口
      * ShadowTLS 公网端口
  - sysctl BBR 配置文件 ${SYSCTL_CONF}（若曾启用）仍保留，可手动删除后 sysctl --system
EOF
}

# -----------------------------------------------------------------------------
# SS2022 / ShadowTLS 参数修改
# -----------------------------------------------------------------------------
modify_ss2022_port() {
    [[ "$(info_get '.ss2022.installed')" == "true" ]] || { log_error "请先安装 SS2022"; return; }
    local old_pub old_local stls_enabled new
    old_pub="$(info_get '.ss2022.public_port')"
    old_local="$(info_get '.ss2022.local_port')"
    stls_enabled="$(info_get '.shadowtls.enabled')"
    while :; do
        read -r -p "请输入 SS2022 新端口（当前公网/本机: ${old_pub}/${old_local}）: " new
        is_valid_port "${new}" || { log_error "端口非法"; continue; }
        check_port_free "${new}" tcp || {
            read -r -p "端口被占用，仍使用? [y/N]: " a
            [[ "${a}" =~ ^[Yy]$ ]] || continue
        }
        break
    done
    info_set ".ss2022.local_port" "${new}"
    if [[ "${stls_enabled}" != "true" ]]; then
        info_set ".ss2022.public_port" "${new}"
        open_firewall_port "${new}" tcp
        [[ -n "${old_pub}" && "${old_pub}" != "0" && "${old_pub}" != "${new}" ]] && suggest_close_port "${old_pub}" tcp
    else
        # ShadowTLS 启用时仅本机端口
        write_shadowtls_env
    fi
    write_ss2022_config
    restart_service "${SS_SERVICE_NAME}"
    [[ "${stls_enabled}" == "true" ]] && restart_service "${STLS_SERVICE_NAME}"
    log_ok "SS2022 端口已修改为 ${new}"
}

modify_ss2022_password() {
    [[ "$(info_get '.ss2022.installed')" == "true" ]] || { log_error "请先安装 SS2022"; return; }
    local method new ss_password
    method="$(info_get '.ss2022.method')"
    read -r -p "是否自动生成新密码? [Y/n]: " a
    if [[ "${a}" =~ ^[Nn]$ ]]; then
        # 用户自定义 PSK 时必须满足 method 对应长度
        while :; do
            read -r -s -p "请输入新密码（base64 PSK，留空取消修改）: " new; echo
            if [[ -z "${new}" ]]; then
                log_info "已取消修改"
                return
            fi
            if validate_ss2022_psk_by_method "${new}" "${method}"; then
                break
            fi
            log_warn "PSK 校验未通过，请重新输入或留空取消"
        done
    else
        new="$(generate_ss2022_password "${method}")"
    fi
    [[ -z "${new}" ]] && { log_error "密码为空"; return 1; }
    local stls_pw
    stls_pw="$(info_get '.shadowtls.password')"
    if [[ "${new}" == "${stls_pw}" ]]; then
        log_error "新密码与 ShadowTLS 密码相同，拒绝"
        return 1
    fi
    info_set ".ss2022.password" "$(jq -nr --arg v "${new}" '$v|tojson')"
    write_ss2022_config
    restart_service "${SS_SERVICE_NAME}"
    log_ok "SS2022 密码已更新"
}

modify_ss2022_method() {
    [[ "$(info_get '.ss2022.installed')" == "true" ]] || { log_error "请先安装 SS2022"; return; }
    echo "选择新的加密方式："
    echo "  1) 2022-blake3-aes-128-gcm"
    echo "  2) 2022-blake3-aes-256-gcm"
    read -r -p "选择 [1-2]: " m
    local method
    case "${m}" in
        1) method="2022-blake3-aes-128-gcm" ;;
        2) method="2022-blake3-aes-256-gcm" ;;
        *) log_error "无效选择"; return 1 ;;
    esac
    local new stls_pw
    stls_pw="$(info_get '.shadowtls.password')"
    # 重新生成 SS2022 密码，并确保不与 ShadowTLS 密码相同（H2-B 不变式）
    while :; do
        new="$(generate_ss2022_password "${method}")"
        [[ -z "${new}" ]] && { log_error "密码生成失败"; return 1; }
        [[ -z "${stls_pw}" || "${new}" != "${stls_pw}" ]] && break
    done
    info_set ".ss2022.method"   "\"${method}\""
    info_set ".ss2022.password" "$(jq -nr --arg v "${new}" '$v|tojson')"
    write_ss2022_config
    restart_service "${SS_SERVICE_NAME}"
    log_ok "加密方式已更新为 ${method}，密码已重新生成"
}

modify_stls_port() {
    [[ "$(info_get '.shadowtls.enabled')" == "true" ]] || { log_error "ShadowTLS 未启用"; return; }
    local old new
    old="$(info_get '.shadowtls.port')"
    while :; do
        read -r -p "请输入 ShadowTLS 新端口（当前 ${old}）: " new
        is_valid_port "${new}" || { log_error "端口非法"; continue; }
        check_port_free "${new}" tcp || {
            read -r -p "端口被占用，仍使用? [y/N]: " a
            [[ "${a}" =~ ^[Yy]$ ]] || continue
        }
        break
    done
    info_set ".shadowtls.port" "${new}"
    write_shadowtls_env
    open_firewall_port "${new}" tcp
    [[ "${old}" != "${new}" ]] && suggest_close_port "${old}" tcp
    restart_service "${STLS_SERVICE_NAME}"
    log_ok "ShadowTLS 端口已修改为 ${new}"
}

modify_stls_password() {
    [[ "$(info_get '.shadowtls.enabled')" == "true" ]] || { log_error "ShadowTLS 未启用"; return; }
    local new ss_pw
    ss_pw="$(info_get '.ss2022.password')"
    read -r -p "是否自动生成新密码? [Y/n]: " a
    if [[ "${a}" =~ ^[Nn]$ ]]; then
        read -r -s -p "请输入新 ShadowTLS 密码: " new; echo
    else
        while :; do
            new="$(generate_shadowtls_password)"
            [[ "${new}" != "${ss_pw}" ]] && break
        done
    fi
    [[ -z "${new}" ]] && { log_error "密码为空"; return 1; }
    [[ "${new}" == "${ss_pw}" ]] && { log_error "不可与 SS2022 密码相同"; return 1; }
    info_set ".shadowtls.password" "$(jq -nr --arg v "${new}" '$v|tojson')"
    write_shadowtls_env
    restart_service "${STLS_SERVICE_NAME}"
    log_ok "ShadowTLS 密码已更新"
}

modify_stls_domain() {
    [[ "$(info_get '.shadowtls.enabled')" == "true" ]] || { log_error "ShadowTLS 未启用"; return; }
    local d
    while :; do
        read -r -p "请输入新伪装域名: " d
        is_valid_domain "${d}" || { log_error "域名格式错误"; continue; }
        break
    done
    test_tls13_domain "${d}" 443 || log_warn "继续使用 ${d}"
    info_set ".shadowtls.tls_domain" "\"${d}\""
    write_shadowtls_env
    restart_service "${STLS_SERVICE_NAME}"
    log_ok "ShadowTLS 伪装域名已更新"
}

# -----------------------------------------------------------------------------
# 监听模式 / 域名 设置
# -----------------------------------------------------------------------------
set_listen_mode_interactive() {
    echo "监听模式："
    echo "  1) 仅 IPv4"
    echo "  2) 仅 IPv6"
    echo "  3) IPv4 + IPv6 双栈（默认）"
    read -r -p "选择 [1-3]: " m
    local mode
    case "${m}" in
        1) mode="ipv4" ;;
        2) mode="ipv6" ;;
        *) mode="dual" ;;
    esac
    info_set ".network.listen_mode" "\"${mode}\""
    # 双栈情况下提示 bindv6only
    if [[ "${mode}" == "dual" ]]; then
        local v
        v="$(cat /proc/sys/net/ipv6/bindv6only 2>/dev/null || echo 0)"
        if [[ "${v}" == "1" ]]; then
            log_warn "系统 bindv6only=1，IPv6 socket 不会同时接受 IPv4，请确认是否手动开启 IPv4 监听"
        fi
    fi
    log_ok "监听模式：${mode}"
}

set_server_domain() {
    local d
    read -r -p "请输入服务器域名（留空清除）: " d
    if [[ -z "${d}" ]]; then
        info_set ".network.domain" "\"\""
        log_ok "已清除域名设置"
        return
    fi
    is_valid_domain "${d}" || { log_error "域名格式错误"; return 1; }
    info_set ".network.domain" "\"${d}\""
    log_ok "域名已设置：${d}"
}

# -----------------------------------------------------------------------------
# 链接 / 配置生成
# -----------------------------------------------------------------------------
# 生成普通 SS2022 ss:// 链接
generate_ss_uri() {
    local server="$1" port="$2" tag="$3"
    local method password userinfo b64 enc_tag
    method="$(info_get '.ss2022.method')"
    password="$(info_get '.ss2022.password')"
    userinfo="${method}:${password}"
    b64="$(printf '%s' "${userinfo}" | b64_url_encode)"
    enc_tag="$(url_encode "${tag}")"
    local server_fmt
    server_fmt="$(format_server_address "${server}")"
    printf 'ss://%s@%s:%s#%s\n' "${b64}" "${server_fmt}" "${port}" "${enc_tag}"
}

# 生成 SS2022 + ShadowTLS 合并链接（SIP002 plugin URI）
generate_ss_shadowtls_uri() {
    local server="$1" port="$2" tag="$3"
    local method password stls_pw domain
    method="$(info_get '.ss2022.method')"
    password="$(info_get '.ss2022.password')"
    stls_pw="$(info_get '.shadowtls.password')"
    domain="$(info_get '.shadowtls.tls_domain')"
    local userinfo b64 enc_tag
    userinfo="${method}:${password}"
    b64="$(printf '%s' "${userinfo}" | b64_url_encode)"
    enc_tag="$(url_encode "${tag}")"
    local server_fmt
    server_fmt="$(format_server_address "${server}")"
    local plugin_raw plugin_enc
    plugin_raw="shadow-tls;host=${domain};password=${stls_pw};version=3"
    plugin_enc="$(url_encode "${plugin_raw}")"
    printf 'ss://%s@%s:%s/?plugin=%s#%s\n' "${b64}" "${server_fmt}" "${port}" "${plugin_enc}" "${enc_tag}"
}

# sing-box 客户端配置（outbound 形式，shadowtls + shadowsocks detour）
generate_singbox_config() {
    local server="$1" port="$2" tag="$3"
    local method password stls_pw domain
    method="$(info_get '.ss2022.method')"
    password="$(info_get '.ss2022.password')"
    stls_pw="$(info_get '.shadowtls.password')"
    domain="$(info_get '.shadowtls.tls_domain')"

    if [[ "$(info_get '.shadowtls.enabled')" == "true" ]]; then
        cat <<EOF
# ===== sing-box 配置（SS2022 + ShadowTLS v3） =====
# 注意：
#   - SS + ShadowTLS 合并链接（ss://...?plugin=...）并非所有客户端都支持
#   - 若客户端无法导入合并链接，请优先使用下方 sing-box 手动配置
#   - sing-box 字段命名可能随版本变化，请以当前 sing-box 文档为准
#   - JSON 本身不支持 # 注释，复制使用时请删除以 # 开头的所有注释行
{
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "${tag}",
      "server": "${server}",
      "server_port": ${port},
      "method": "${method}",
      "password": "${password}",
      "detour": "shadowtls-${tag}"
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-${tag}",
      "server": "${server}",
      "server_port": ${port},
      "version": 3,
      "password": "${stls_pw}",
      "tls": {
        "enabled": true,
        "server_name": "${domain}",
        "utls": { "enabled": true, "fingerprint": "chrome" }
      }
    }
  ]
}
# ===== sing-box 配置结束 =====
EOF
    else
        cat <<EOF
# ===== sing-box 配置（SS2022 纯直连） =====
# 注意：JSON 本身不支持 # 注释，复制使用时请删除以 # 开头的所有注释行
{
  "outbounds": [
    {
      "type": "shadowsocks",
      "tag": "${tag}",
      "server": "${server}",
      "server_port": ${port},
      "method": "${method}",
      "password": "${password}"
    }
  ]
}
# ===== sing-box 配置结束 =====
EOF
    fi
}

# mihomo / Clash Meta 配置（YAML，格式可能随版本变化）
generate_mihomo_config() {
    local server="$1" port="$2" tag="$3"
    local method password stls_pw domain
    method="$(info_get '.ss2022.method')"
    password="$(info_get '.ss2022.password')"
    stls_pw="$(info_get '.shadowtls.password')"
    domain="$(info_get '.shadowtls.tls_domain')"

    if [[ "$(info_get '.shadowtls.enabled')" == "true" ]]; then
        cat <<EOF
# ===== mihomo / Clash Meta 配置（SS2022 + ShadowTLS v3） =====
# 注意：
#   - SS + ShadowTLS 合并链接（ss://...?plugin=...）并非所有客户端都支持
#   - 若客户端无法导入合并链接，请优先使用下方 mihomo / Clash Meta 手动配置
#   - plugin / plugin-opts 字段命名可能随 mihomo / Clash Meta 版本变化，请以当前文档为准
#   - server 加双引号以避免 IPv6 字面量在 YAML 中被误解析
proxies:
  - name: "${tag}"
    type: ss
    server: "${server}"
    port: ${port}
    cipher: ${method}
    password: "${password}"
    plugin: shadow-tls
    client-fingerprint: chrome
    plugin-opts:
      host: "${domain}"
      password: "${stls_pw}"
      version: 3
# ===== mihomo / Clash Meta 配置结束 =====
EOF
    else
        cat <<EOF
# ===== mihomo / Clash Meta 配置（SS2022 纯直连） =====
# 注意：server 加双引号以避免 IPv6 字面量在 YAML 中被误解析
proxies:
  - name: "${tag}"
    type: ss
    server: "${server}"
    port: ${port}
    cipher: ${method}
    password: "${password}"
# ===== mihomo / Clash Meta 配置结束 =====
EOF
    fi
}

# -----------------------------------------------------------------------------
# 节点信息展示（默认遮蔽敏感信息）
# -----------------------------------------------------------------------------
mask_secret() {
    local s="$1"
    local n=${#s}
    if (( n <= 6 )); then
        printf '******'
    else
        printf '%s***%s' "${s:0:3}" "${s: -3}"
    fi
}

print_endpoints_header() {
    local v4 v6 domain stls_enabled
    v4="$(info_get '.network.ipv4')"
    v6="$(info_get '.network.ipv6')"
    domain="$(info_get '.network.domain')"
    stls_enabled="$(info_get '.shadowtls.enabled')"
    hr
    echo "服务器入口："
    if [[ "${stls_enabled}" == "true" ]]; then
        local port; port="$(info_get '.shadowtls.port')"
        echo "  类型：ShadowTLS v3"
        echo "  端口：${port}"
    else
        local port; port="$(info_get '.ss2022.public_port')"
        echo "  类型：SS2022 (公网直连)"
        echo "  端口：${port}"
    fi
    [[ -n "${v4}" ]]     && echo "  IPv4 ：${v4}"
    [[ -n "${v6}" ]]     && echo "  IPv6 ：${v6}"
    [[ -n "${domain}" ]] && echo "  域名 ：${domain}"
    hr
}

# 收集可用 server 列表 (ipv4 / ipv6 / domain)
collect_servers() {
    local v4 v6 domain mode
    v4="$(info_get '.network.ipv4')"
    v6="$(info_get '.network.ipv6')"
    domain="$(info_get '.network.domain')"
    mode="$(info_get '.network.listen_mode')"
    local out=""
    case "${mode}" in
        ipv4) [[ -n "${v4}" ]] && out+="ipv4|${v4}|IPv4"$'\n' ;;
        ipv6) [[ -n "${v6}" ]] && out+="ipv6|${v6}|IPv6"$'\n' ;;
        *)
            [[ -n "${v4}" ]] && out+="ipv4|${v4}|IPv4"$'\n'
            [[ -n "${v6}" ]] && out+="ipv6|${v6}|IPv6"$'\n'
            ;;
    esac
    [[ -n "${domain}" ]] && out+="domain|${domain}|Domain"$'\n'
    printf '%s' "${out}"
}

# 显示节点信息（遮蔽）；可选 $1=full 显示完整
show_node_info_impl() {
    local full="$1"
    if [[ "$(info_get '.ss2022.installed')" != "true" ]]; then
        log_warn "SS2022 未安装"
        return
    fi
    print_endpoints_header
    local method password stls_pw stls_domain stls_enabled stls_port port
    method="$(info_get '.ss2022.method')"
    password="$(info_get '.ss2022.password')"
    stls_pw="$(info_get '.shadowtls.password')"
    stls_domain="$(info_get '.shadowtls.tls_domain')"
    stls_enabled="$(info_get '.shadowtls.enabled')"
    stls_port="$(info_get '.shadowtls.port')"
    port="$(info_get '.ss2022.public_port')"

    if [[ "${full}" == "full" ]]; then
        echo "SS2022 加密方式：${method}"
        echo "SS2022 密码    ：${password}"
    else
        echo "SS2022 加密方式：${method}"
        echo "SS2022 密码    ：$(mask_secret "${password}")  (选项 44 可显示完整)"
    fi

    if [[ "${stls_enabled}" == "true" ]]; then
        echo "ShadowTLS 端口 ：${stls_port}"
        echo "ShadowTLS 域名 ：${stls_domain}"
        if [[ "${full}" == "full" ]]; then
            echo "ShadowTLS 密码 ：${stls_pw}"
        else
            echo "ShadowTLS 密码 ：$(mask_secret "${stls_pw}")"
        fi
    fi
    hr

    # 链接
    local conn_port
    if [[ "${stls_enabled}" == "true" ]]; then
        conn_port="${stls_port}"
    else
        conn_port="${port}"
    fi

    if [[ "${full}" == "full" ]]; then
        local row server label
        if [[ "${stls_enabled}" == "true" ]]; then
            echo "=== SS2022 内部后端信息（仅本机调试 / 排障使用） ==="
            log_warn "下方 ss:// 链接指向 127.0.0.1，不能作为公网节点导入；公网入口请使用 SS + ShadowTLS 合并链接"
            local _local_port
            _local_port="$(info_get '.ss2022.local_port')"
            generate_ss_uri "127.0.0.1" "${_local_port}" "SS2022-INTERNAL-DEBUG"
        else
            echo "=== 普通 SS2022 ss:// 链接 ==="
            while IFS='|' read -r kind server label; do
                [[ -z "${kind}" ]] && continue
                generate_ss_uri "${server}" "${conn_port}" "SS2022-${label}"
            done < <(collect_servers)
        fi

        if [[ "${stls_enabled}" == "true" ]]; then
            echo
            echo "=== SS + ShadowTLS 合并链接（SIP002 plugin URI） ==="
            echo "兼容性提示：部分客户端可直接导入；不支持时请使用下方 sing-box / mihomo 配置"
            while IFS='|' read -r kind server label; do
                [[ -z "${kind}" ]] && continue
                generate_ss_shadowtls_uri "${server}" "${conn_port}" "SS-STLS-${label}"
            done < <(collect_servers)

            echo
            echo "=== sing-box 配置示例 ==="
            local first=""
            while IFS='|' read -r kind server label; do
                [[ -z "${kind}" ]] && continue
                if [[ -z "${first}" ]]; then
                    first="${server}"
                    generate_singbox_config "${server}" "${conn_port}" "SS-STLS-${label}"
                fi
            done < <(collect_servers)

            echo
            echo "=== mihomo / Clash Meta 配置示例 ==="
            local first2=""
            while IFS='|' read -r kind server label; do
                [[ -z "${kind}" ]] && continue
                if [[ -z "${first2}" ]]; then
                    first2="${server}"
                    generate_mihomo_config "${server}" "${conn_port}" "SS-STLS-${label}"
                fi
            done < <(collect_servers)

            cat <<EOF

=== Shadowrocket 手动配置 ===
  类型：Shadowsocks
  加密：${method}
  地址：<服务器 IP 或域名>
  端口：${stls_port}
  插件：ShadowTLS（需客户端支持）
  ShadowTLS version：3
  host / SNI：${stls_domain}
  ShadowTLS password：${stls_pw}

=== Surge 手动配置（注意客户端版本是否支持 ShadowTLS） ===
  Proxy = ss, <server>, ${stls_port}, encrypt-method=${method}, password=${password}, shadow-tls-password=${stls_pw}, shadow-tls-sni=${stls_domain}, shadow-tls-version=3
  请以你当前 Surge 版本文档为准，字段命名可能不同
EOF
        fi
    else
        echo "（仅展示遮蔽信息，选项 44 可显示完整节点信息 / 链接 / 配置）"
    fi
    hr
}

show_node_info()       { show_node_info_impl "mask"; }
show_full_node_info()  { show_node_info_impl "full"; }

# 单独菜单：仅生成各种链接 / 配置
gen_ss_uri_only() {
    if [[ "$(info_get '.ss2022.installed')" != "true" ]]; then
        log_warn "SS2022 未安装"; return
    fi
    print_endpoints_header
    local stls_enabled port
    stls_enabled="$(info_get '.shadowtls.enabled')"
    if [[ "${stls_enabled}" == "true" ]]; then
        # H2-A：ShadowTLS 启用时不再生成"看似普通 SS2022 公网链接但端口指向 ShadowTLS"的误导性 URI
        log_warn "已启用 ShadowTLS：公网入口为 ShadowTLS，请使用菜单 46 生成 SS + ShadowTLS 合并链接"
        log_warn "若需 SS2022 内部后端 ss:// 链接（仅本机调试 / 排障使用），可选项 44 查看完整节点信息"
        return
    fi
    port="$(info_get '.ss2022.public_port')"
    while IFS='|' read -r kind server label; do
        [[ -z "${kind}" ]] && continue
        generate_ss_uri "${server}" "${port}" "SS2022-${label}"
    done < <(collect_servers)
}

gen_ss_stls_uri_only() {
    if [[ "$(info_get '.shadowtls.enabled')" != "true" ]]; then
        log_warn "ShadowTLS 未启用，请先启用 ShadowTLS v3（菜单 20）"
        return
    fi
    local port; port="$(info_get '.shadowtls.port')"
    print_endpoints_header
    while IFS='|' read -r kind server label; do
        [[ -z "${kind}" ]] && continue
        generate_ss_shadowtls_uri "${server}" "${port}" "SS-STLS-${label}"
    done < <(collect_servers)
}

gen_singbox_only() {
    if [[ "$(info_get '.ss2022.installed')" != "true" ]]; then
        log_warn "SS2022 未安装"; return
    fi
    local port;
    if [[ "$(info_get '.shadowtls.enabled')" == "true" ]]; then
        port="$(info_get '.shadowtls.port')"
    else
        port="$(info_get '.ss2022.public_port')"
    fi
    while IFS='|' read -r kind server label; do
        [[ -z "${kind}" ]] && continue
        echo "# ===== ${label} (${server}) ====="
        generate_singbox_config "${server}" "${port}" "SS-${label}"
        echo
    done < <(collect_servers)
}

gen_mihomo_only() {
    if [[ "$(info_get '.ss2022.installed')" != "true" ]]; then
        log_warn "SS2022 未安装"; return
    fi
    local port;
    if [[ "$(info_get '.shadowtls.enabled')" == "true" ]]; then
        port="$(info_get '.shadowtls.port')"
    else
        port="$(info_get '.ss2022.public_port')"
    fi
    while IFS='|' read -r kind server label; do
        [[ -z "${kind}" ]] && continue
        echo "# ===== ${label} (${server}) ====="
        generate_mihomo_config "${server}" "${port}" "SS-${label}"
        echo
    done < <(collect_servers)
}

# -----------------------------------------------------------------------------
# 二维码生成
# -----------------------------------------------------------------------------
# 仅在终端显示二维码；不再写 PNG 文件
# 参数：content
# qrencode 缺失时尝试 apt 安装一次；仍失败则只输出文字链接并返回 1（不退出）
generate_qrcode() {
    local content="$1"
    if ! command -v qrencode >/dev/null 2>&1; then
        log_warn "qrencode 未安装，尝试 apt 安装..."
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode >/dev/null 2>&1 || true
        fi
        if ! command -v qrencode >/dev/null 2>&1; then
            log_warn "qrencode 安装失败，将仅输出文字链接"
            printf '链接：%s\n' "${content}"
            return 1
        fi
    fi
    if (( ${#content} > 300 )); then
        log_warn "链接长度 ${#content} 较长，部分客户端可能无法扫描该二维码"
    fi
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
    if (( cols < 60 )); then
        log_warn "终端宽度 ${cols} 较窄，二维码可能无法完整显示，请放大窗口"
    fi
    if ! qrencode -t ANSIUTF8 "${content}"; then
        log_warn "终端二维码渲染失败，将输出文字链接"
        printf '链接：%s\n' "${content}"
        return 1
    fi
    return 0
}

confirm_show_secret() {
    read -r -p "是否显示完整敏感内容（密码 / 完整链接）? [y/N]: " a
    [[ "${a}" =~ ^[Yy]$ ]]
}

# 二维码安全提示，确认后才在终端显示；默认不写 PNG
confirm_show_qr_terminal() {
    log_warn "二维码包含完整节点链接和密码，请勿截图发给他人"
    log_warn "默认不会保存 PNG 文件，仅在当前终端显示"
    read -r -p "是否在终端显示二维码? [y/N]: " a
    [[ "${a}" =~ ^[Yy]$ ]]
}

qr_ss2022() {
    [[ "$(info_get '.ss2022.installed')" == "true" ]] || { log_warn "SS2022 未安装"; return; }
    local stls_enabled
    stls_enabled="$(info_get '.shadowtls.enabled')"

    # H2-A：ShadowTLS 启用时不再生成"端口指向 ShadowTLS"的普通 SS 链接二维码
    if [[ "${stls_enabled}" == "true" ]]; then
        log_warn "已启用 ShadowTLS：公网入口为 ShadowTLS，请使用「显示 SS + ShadowTLS 二维码」"
        log_warn "下方仅能生成 127.0.0.1:本地端口 的 SS2022 内部调试二维码（不能作为公网节点）"
        read -r -p "是否生成内部调试二维码? [y/N]: " a
        [[ "${a}" =~ ^[Yy]$ ]] || { log_info "已取消"; return; }
        confirm_show_qr_terminal || { log_info "已取消显示"; return; }
        local _local_port _uri
        _local_port="$(info_get '.ss2022.local_port')"
        _uri="$(generate_ss_uri "127.0.0.1" "${_local_port}" "SS2022-INTERNAL-DEBUG")"
        printf '\n=== SS2022 内部调试二维码 (127.0.0.1:%s) ===\n' "${_local_port}"
        generate_qrcode "${_uri}"
        return
    fi

    # ShadowTLS 未启用：常规公网 SS2022 二维码
    confirm_show_qr_terminal || { log_info "已取消显示"; return; }
    local port
    port="$(info_get '.ss2022.public_port')"
    while IFS='|' read -r kind server label; do
        [[ -z "${kind}" ]] && continue
        local uri
        uri="$(generate_ss_uri "${server}" "${port}" "SS2022-${label}")"
        printf '\n=== SS2022 二维码 (%s: %s:%s) ===\n' "${label}" "${server}" "${port}"
        generate_qrcode "${uri}"
    done < <(collect_servers)
}

qr_ss_stls() {
    [[ "$(info_get '.shadowtls.enabled')" == "true" ]] || { log_warn "ShadowTLS 未启用"; return; }
    confirm_show_qr_terminal || { log_info "已取消显示"; return; }
    local port; port="$(info_get '.shadowtls.port')"
    while IFS='|' read -r kind server label; do
        [[ -z "${kind}" ]] && continue
        local uri
        uri="$(generate_ss_shadowtls_uri "${server}" "${port}" "SS-STLS-${label}")"
        printf '\n=== SS + ShadowTLS 二维码 (%s: %s:%s) ===\n' "${label}" "${server}" "${port}"
        generate_qrcode "${uri}"
    done < <(collect_servers)
}

qr_all() {
    qr_ss2022
    [[ "$(info_get '.shadowtls.enabled')" == "true" ]] && qr_ss_stls
}

# -----------------------------------------------------------------------------
# UDP 模式 / BBR
# -----------------------------------------------------------------------------
set_udp_mode() {
    [[ "$(info_get '.ss2022.installed')" == "true" ]] || { log_error "请先安装 SS2022"; return; }
    local stls_enabled
    stls_enabled="$(info_get '.shadowtls.enabled')"
    echo "UDP 模式："
    echo "  1) 禁用 UDP（推荐启用 ShadowTLS 时）"
    echo "  2) UDP 直连：SS2022 单独保留 UDP 公网端口（与 ShadowTLS 共存）"
    echo "  3) tcp_and_udp：SS2022 同端口承担 TCP+UDP（仅在未启用 ShadowTLS 时合理）"
    read -r -p "选择 [1-3]: " m
    case "${m}" in
        1)
            info_set ".ss2022.mode" "\"tcp_only\""
            log_ok "已设置为 tcp_only"
            ;;
        2)
            # 仍在 SS2022 单独 UDP 模式：mode=udp_only 不合适，使用 tcp_and_udp + ShadowTLS 仅前 TCP
            info_set ".ss2022.mode" "\"tcp_and_udp\""
            log_warn "SS2022 同时监听 UDP；ShadowTLS 启用时 UDP 仍直连公网，注意安全/兼容性"
            if [[ "${stls_enabled}" == "true" ]]; then
                local p; p="$(info_get '.ss2022.local_port')"
                # 切换到公网监听 UDP 不在本脚本范围（监听地址由 ShadowTLS 决定）
                # 提示用户：若要 UDP 公网，需手动单独开 SS2022 公网端口；本脚本不自动处理
                log_warn "如需 UDP 公网，请单独安装第二个 ssserver 实例或停用 ShadowTLS"
            else
                local p; p="$(info_get '.ss2022.public_port')"
                open_firewall_port "${p}" udp
            fi
            ;;
        3)
            info_set ".ss2022.mode" "\"tcp_and_udp\""
            if [[ "${stls_enabled}" != "true" ]]; then
                local p; p="$(info_get '.ss2022.public_port')"
                open_firewall_port "${p}" tcp
                open_firewall_port "${p}" udp
            fi
            ;;
        *) log_error "无效"; return 1 ;;
    esac
    write_ss2022_config
    restart_service "${SS_SERVICE_NAME}"
}

show_udp_mode() {
    echo "当前 SS2022 mode：$(info_get '.ss2022.mode')"
    if [[ "$(info_get '.shadowtls.enabled')" == "true" ]]; then
        log_warn "ShadowTLS 已启用，仅 TCP 被伪装；UDP（若开启）走 SS2022 本机端口，无法穿越 ShadowTLS"
    fi
}

enable_bbr() {
    log_step "BBR / 系统优化"
    local cc qd
    cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    qd="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    echo "当前 tcp_congestion_control: ${cc}"
    echo "当前 default_qdisc        : ${qd}"
    if [[ "${cc}" == "bbr" && "${qd}" == "fq" ]]; then
        log_ok "BBR 已启用"
        return
    fi
    read -r -p "是否启用 BBR? [y/N]: " a
    [[ "${a}" =~ ^[Yy]$ ]] || { log_info "已取消"; return; }
    backup_config "${SYSCTL_CONF}"
    cat > "${SYSCTL_CONF}" <<EOF
# Managed by ${SCRIPT_NAME}
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system >/dev/null 2>&1 || true
    cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    qd="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    echo "现在 tcp_congestion_control: ${cc}"
    echo "现在 default_qdisc        : ${qd}"
}

show_sys_opt() {
    echo "tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    echo "default_qdisc         : $(sysctl -n net.core.default_qdisc 2>/dev/null)"
    echo "ipv6 bindv6only       : $(cat /proc/sys/net/ipv6/bindv6only 2>/dev/null)"
    echo "fs.file-max           : $(sysctl -n fs.file-max 2>/dev/null)"
}

# -----------------------------------------------------------------------------
# 时间同步 / 时区
# 准确的系统时间有助于 TLS、证书校验、日志排障和部分客户端兼容性，建议保持时间同步。
# -----------------------------------------------------------------------------

# 返回时间同步状态：
#   synced   - timedatectl 报告 System clock synchronized: yes
#   unsynced - timedatectl 报告 no（NTP 启用与否另算）
#   unknown  - 无法判定（timedatectl 不可用或解析失败）
check_time_status() {
    if ! command -v timedatectl >/dev/null 2>&1; then
        echo "unknown"
        return
    fi
    local line
    line="$(timedatectl status 2>/dev/null | grep -Ei 'System clock synchronized' || true)"
    if [[ -z "${line}" ]]; then
        echo "unknown"
    elif echo "${line}" | grep -qi 'yes'; then
        echo "synced"
    else
        echo "unsynced"
    fi
}

# 简短中文状态，用于主菜单状态栏
time_status_label() {
    case "$(check_time_status)" in
        synced)   printf '%s已同步%s' "${C_GREEN}" "${C_RESET}" ;;
        unsynced) printf '%s未同步%s' "${C_YELLOW}" "${C_RESET}" ;;
        *)        printf '%s未检测%s' "${C_YELLOW}" "${C_RESET}" ;;
    esac
}

show_time_status() {
    log_step "系统时间与时区"
    echo "date:"
    date
    echo
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl status 2>/dev/null || true
    else
        log_warn "timedatectl 不可用"
    fi
}

sync_time_auto() {
    log_step "自动校准系统时间"
    if ! command -v timedatectl >/dev/null 2>&1; then
        log_error "timedatectl 不可用（systemd 缺失）"
        suggest "可手动选择安装 chrony 进行时间同步"
        return 1
    fi
    # 优先 systemd-timesyncd
    if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-timesyncd\.service'; then
        log_info "尝试启用 NTP（systemd-timesyncd）..."
        timedatectl set-ntp true 2>/dev/null || log_warn "set-ntp 失败"
        systemctl restart systemd-timesyncd 2>/dev/null || log_warn "重启 systemd-timesyncd 失败"
        sleep 1
        timedatectl status 2>/dev/null | grep -Ei 'NTP|System clock synchronized|Time zone' || true
        case "$(check_time_status)" in
            synced)
                log_ok "时间已同步"
                return 0
                ;;
            *)
                log_warn "仍未同步，可尝试安装 chrony 作为后备"
                ;;
        esac
    else
        log_info "未检测到 systemd-timesyncd"
    fi
    read -r -p "是否安装 chrony 进行时间同步? [y/N]: " a
    [[ "${a}" =~ ^[Yy]$ ]] || { log_info "已取消"; return; }
    if ! command -v apt-get >/dev/null 2>&1; then
        log_error "未找到 apt-get，无法自动安装 chrony"
        return 1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || log_warn "apt-get update 失败"
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y chrony >/dev/null 2>&1; then
        log_error "chrony 安装失败"
        return 1
    fi
    systemctl enable --now chrony >/dev/null 2>&1 || systemctl enable --now chronyd >/dev/null 2>&1 || true
    sleep 1
    if command -v chronyc >/dev/null 2>&1; then
        chronyc tracking 2>/dev/null || true
    fi
    case "$(check_time_status)" in
        synced)   log_ok "时间已同步" ;;
        *)        log_warn "时间仍未同步，请稍后再查看 timedatectl status" ;;
    esac
}

set_timezone_interactive() {
    log_step "设置时区"
    if ! command -v timedatectl >/dev/null 2>&1; then
        log_error "timedatectl 不可用"
        return 1
    fi
    echo "常用时区："
    echo "  1) Asia/Shanghai"
    echo "  2) Asia/Hong_Kong"
    echo "  3) Asia/Taipei"
    echo "  4) Asia/Tokyo"
    echo "  5) UTC"
    echo "  6) 自定义输入"
    read -r -p "选择 [1-6]: " ch
    local tz=""
    case "${ch}" in
        1) tz="Asia/Shanghai" ;;
        2) tz="Asia/Hong_Kong" ;;
        3) tz="Asia/Taipei" ;;
        4) tz="Asia/Tokyo" ;;
        5) tz="UTC" ;;
        6)
            read -r -p "请输入时区（如 Europe/Berlin）: " tz
            ;;
        *) log_error "无效选择"; return 1 ;;
    esac
    [[ -z "${tz}" ]] && { log_error "时区为空"; return 1; }
    if ! timedatectl set-timezone "${tz}" 2>/dev/null; then
        log_error "设置时区失败：${tz}"
        suggest "确认时区字符串是否合法（参考 timedatectl list-timezones）"
        return 1
    fi
    log_ok "时区已设置为 ${tz}"
    timedatectl status 2>/dev/null | grep -Ei 'Time zone' || true
}

set_time_manual() {
    log_step "手动设置系统时间"
    if ! command -v timedatectl >/dev/null 2>&1; then
        log_error "timedatectl 不可用"
        return 1
    fi
    log_warn "手动设置会自动关闭 NTP；建议优先使用「自动校准系统时间」"
    read -r -p "请输入时间 (YYYY-MM-DD HH:MM:SS): " when
    if ! [[ "${when}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        log_error "格式错误，应为 YYYY-MM-DD HH:MM:SS"
        return 1
    fi
    if ! timedatectl set-time "${when}" 2>/dev/null; then
        log_error "设置时间失败"
        suggest "请确认 NTP 已关闭：timedatectl set-ntp false"
        return 1
    fi
    log_ok "系统时间已设置为：${when}"
    date
}

# 安装前的时间提示（不强制阻止）
hint_time_before_install() {
    case "$(check_time_status)" in
        synced)   : ;;
        unsynced) log_warn "系统时间未同步：准确的时间有助于 TLS、证书校验、日志排障，建议先在「网络与时间」菜单中校准" ;;
        unknown)  log_warn "未能确认时间同步状态：建议在「网络与时间」菜单中查看与校准" ;;
    esac
}

# -----------------------------------------------------------------------------
# 更新
# -----------------------------------------------------------------------------
update_shadowsocks_rust() {
    log_step "更新 shadowsocks-rust"
    local cur latest
    cur="$(info_get '.ss2022.binary_version')"
    latest="$(github_latest_tag "${SS_RUST_REPO}")"
    echo "当前：${cur:-未知}"
    echo "最新：${latest:-未知}"
    if [[ -n "${cur}" && "${cur}" == "${latest}" ]]; then
        log_ok "已是最新，无需更新"
        return
    fi
    read -r -p "是否更新? [Y/n]: " a
    [[ "${a}" =~ ^[Nn]$ ]] && { log_info "已取消"; return; }
    systemctl stop "${SS_SERVICE_NAME}" >/dev/null 2>&1 || true
    download_shadowsocks_rust "${latest}" || { log_error "更新失败，尝试启动旧版本"; systemctl start "${SS_SERVICE_NAME}" || true; return 1; }
    restart_service "${SS_SERVICE_NAME}"
}

update_shadowtls() {
    log_step "更新 shadow-tls"
    local cur latest
    cur="$(info_get '.shadowtls.binary_version')"
    latest="$(github_latest_tag "${STLS_REPO}")"
    echo "当前：${cur:-未知}"
    echo "最新：${latest:-未知}"
    if [[ -n "${cur}" && "${cur}" == "${latest}" ]]; then
        log_ok "已是最新，无需更新"
        return
    fi
    read -r -p "是否更新? [Y/n]: " a
    [[ "${a}" =~ ^[Nn]$ ]] && { log_info "已取消"; return; }
    systemctl stop "${STLS_SERVICE_NAME}" >/dev/null 2>&1 || true
    download_shadowtls "${latest}" || { log_error "更新失败"; systemctl start "${STLS_SERVICE_NAME}" || true; return 1; }
    restart_service "${STLS_SERVICE_NAME}"
}

# -----------------------------------------------------------------------------
# 主菜单
# -----------------------------------------------------------------------------
status_line() {
    local ss_inst stls_en stls_inst v4 v6 ss_port stls_port mode
    ss_inst="$(info_get '.ss2022.installed')"
    stls_en="$(info_get '.shadowtls.enabled')"
    stls_inst="$(info_get '.shadowtls.installed')"
    v4="$(info_get '.network.ipv4')"
    v6="$(info_get '.network.ipv6')"
    ss_port="$(info_get '.ss2022.public_port')"
    stls_port="$(info_get '.shadowtls.port')"
    mode="$(info_get '.network.listen_mode')"

    local ss_active stls_active
    systemctl is-active --quiet "${SS_SERVICE_NAME}"    && ss_active="${C_GREEN}运行中${C_RESET}"   || ss_active="${C_RED}未运行${C_RESET}"
    systemctl is-active --quiet "${STLS_SERVICE_NAME}"  && stls_active="${C_GREEN}运行中${C_RESET}" || stls_active="${C_RED}未运行${C_RESET}"

    printf '版本：%s   监听模式：%s\n' "${SCRIPT_VERSION}" "${mode:-dual}"
    printf '公网 IPv4：%s   公网 IPv6：%s\n' "${v4:-未检测}" "${v6:-未检测}"
    printf 'SS2022    ：%s   端口：%s   服务：%s\n' \
        "$([[ "${ss_inst}" == "true" ]] && echo 已安装 || echo 未安装)" \
        "${ss_port:-N/A}" "${ss_active}"
    printf 'ShadowTLS ：%s / %s   端口：%s   服务：%s\n' \
        "$([[ "${stls_inst}" == "true" ]] && echo 已安装 || echo 未安装)" \
        "$([[ "${stls_en}" == "true" ]] && echo 已启用 || echo 未启用)" \
        "${stls_port:-N/A}" "${stls_active}"
    printf '时间同步  ：%s\n' "$(time_status_label)"
}

print_main_menu() {
    clear 2>/dev/null || true
    cat <<EOF
${C_BOLD}SS2022 + ShadowTLS 管理脚本 ${SCRIPT_VERSION}${C_RESET}
EOF
    status_line
    hr
    cat <<'EOF'
主菜单：
  1) 一键安装 SS2022
  2) 启用 / 配置 ShadowTLS v3
  3) 查看节点信息
  4) 生成二维码
  5) 服务管理
  6) 网络与时间
  7) 高级设置
  8) 一键完整卸载
  0) 退出
EOF
    hr
}

# ----------- 子菜单 -----------

submenu_shadowtls() {
    while :; do
        clear 2>/dev/null || true
        cat <<'EOF'
ShadowTLS v3：
  1) 启用 ShadowTLS v3
  2) 停用 ShadowTLS（保留二进制和配置）
  3) 卸载 ShadowTLS（删除二进制和配置）
  0) 返回主菜单
EOF
        read -r -p "请输入选项: " c
        case "${c}" in
            1) enable_shadowtls ;;
            2) disable_shadowtls ;;
            3) uninstall_shadowtls ;;
            0) return ;;
            *) log_error "无效选项：${c}" ;;
        esac
        press_any_key
    done
}

submenu_node_info() {
    while :; do
        clear 2>/dev/null || true
        cat <<'EOF'
节点信息：
  1) 查看节点信息（密码遮蔽）
  2) 显示完整节点信息（含完整密码 / 链接 / 客户端配置）
  3) 生成 SS2022 普通链接
  4) 生成 SS + ShadowTLS 合并链接
  5) 生成 sing-box 配置
  6) 生成 mihomo / Clash Meta 配置
  0) 返回主菜单
EOF
        read -r -p "请输入选项: " c
        case "${c}" in
            1) show_node_info ;;
            2) show_full_node_info ;;
            3) gen_ss_uri_only ;;
            4) gen_ss_stls_uri_only ;;
            5) gen_singbox_only ;;
            6) gen_mihomo_only ;;
            0) return ;;
            *) log_error "无效选项：${c}" ;;
        esac
        press_any_key
    done
}

submenu_qr() {
    while :; do
        clear 2>/dev/null || true
        cat <<'EOF'
生成二维码（默认仅在终端显示，不保存 PNG 文件）：
  1) 显示 SS2022 二维码
  2) 显示 SS + ShadowTLS 二维码
  3) 显示全部二维码
  0) 返回主菜单
EOF
        read -r -p "请输入选项: " c
        case "${c}" in
            1) qr_ss2022 ;;
            2) qr_ss_stls ;;
            3) qr_all ;;
            0) return ;;
            *) log_error "无效选项：${c}" ;;
        esac
        press_any_key
    done
}

submenu_service() {
    while :; do
        clear 2>/dev/null || true
        cat <<'EOF'
服务管理：
  1) 启动 SS2022          2) 停止 SS2022
  3) 重启 SS2022          4) 查看 SS2022 状态
  5) 查看 SS2022 日志
  6) 启动 ShadowTLS       7) 停止 ShadowTLS
  8) 重启 ShadowTLS       9) 查看 ShadowTLS 状态
 10) 查看 ShadowTLS 日志
  0) 返回主菜单
EOF
        read -r -p "请输入选项: " c
        case "${c}" in
            1)  start_service   "${SS_SERVICE_NAME}" ;;
            2)  stop_service    "${SS_SERVICE_NAME}" ;;
            3)  restart_service "${SS_SERVICE_NAME}" ;;
            4)  status_service  "${SS_SERVICE_NAME}" ;;
            5)  journal_follow  "${SS_SERVICE_NAME}" ;;
            6)  start_service   "${STLS_SERVICE_NAME}" ;;
            7)  stop_service    "${STLS_SERVICE_NAME}" ;;
            8)  restart_service "${STLS_SERVICE_NAME}" ;;
            9)  status_service  "${STLS_SERVICE_NAME}" ;;
            10) journal_follow  "${STLS_SERVICE_NAME}" ;;
            0) return ;;
            *) log_error "无效选项：${c}" ;;
        esac
        press_any_key
    done
}

submenu_network_time() {
    while :; do
        clear 2>/dev/null || true
        cat <<'EOF'
网络与时间：
  1) 检测公网 IPv4 / IPv6
  2) 设置服务器域名
  3) 设置 IPv4 / IPv6 监听模式
  4) 查看系统时间与时区
  5) 自动校准系统时间（NTP / chrony）
  6) 手动设置时区
  7) 手动设置系统时间
  0) 返回主菜单
EOF
        read -r -p "请输入选项: " c
        case "${c}" in
            1) refresh_public_ips ;;
            2) set_server_domain ;;
            3) set_listen_mode_interactive
               [[ "$(info_get '.ss2022.installed')" == "true" ]] && { write_ss2022_config; restart_service "${SS_SERVICE_NAME}"; }
               [[ "$(info_get '.shadowtls.enabled')" == "true" ]] && { write_shadowtls_env; restart_service "${STLS_SERVICE_NAME}"; }
               ;;
            4) show_time_status ;;
            5) sync_time_auto ;;
            6) set_timezone_interactive ;;
            7) set_time_manual ;;
            0) return ;;
            *) log_error "无效选项：${c}" ;;
        esac
        press_any_key
    done
}

submenu_advanced() {
    while :; do
        clear 2>/dev/null || true
        cat <<'EOF'
高级设置：
  1) 修改 SS2022 端口
  2) 修改 SS2022 密码
  3) 修改 SS2022 加密方式
  4) 修改 ShadowTLS 端口
  5) 修改 ShadowTLS 密码
  6) 修改 ShadowTLS 伪装域名
  7) 设置 UDP 模式
  8) 启用 BBR / 查看系统优化状态
  9) 更新 shadowsocks-rust
 10) 更新 shadow-tls
 11) 卸载 SS2022（不卸载 ShadowTLS / 不动其它）
 12) 安装 / 更新快捷命令 ss2022
 13) 删除快捷命令 ss2022
  0) 返回主菜单
EOF
        read -r -p "请输入选项: " c
        case "${c}" in
            1)  modify_ss2022_port ;;
            2)  modify_ss2022_password ;;
            3)  modify_ss2022_method ;;
            4)  modify_stls_port ;;
            5)  modify_stls_password ;;
            6)  modify_stls_domain ;;
            7)  set_udp_mode ;;
            8)  enable_bbr; echo; show_sys_opt ;;
            9)  update_shadowsocks_rust ;;
            10) update_shadowtls ;;
            11) uninstall_ss2022 ;;
            12) install_shortcut_command ;;
            13) remove_shortcut_command ;;
            0) return ;;
            *) log_error "无效选项：${c}" ;;
        esac
        press_any_key
    done
}

dispatch() {
    local c="$1"
    case "${c}" in
        1) install_ss2022 ;;
        2) submenu_shadowtls ;;
        3) submenu_node_info ;;
        4) submenu_qr ;;
        5) submenu_service ;;
        6) submenu_network_time ;;
        7) submenu_advanced ;;
        8) uninstall_all ;;
        0) exit 0 ;;
        *) log_error "无效选项：${c}" ;;
    esac
}

main_loop() {
    while :; do
        print_main_menu
        read -r -p "请输入选项: " choice
        dispatch "${choice}"
        # 子菜单内部自己处理 press_any_key；主菜单的一键操作再补一次
        case "${choice}" in
            1|8) press_any_key ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# 入口
# -----------------------------------------------------------------------------
main() {
    check_root
    detect_os
    detect_arch
    ensure_project_dirs
    main_loop
}

main "$@"
