#!/usr/bin/env bash
# Only extracted functions are loaded; system services and production paths are never used.
set -euo pipefail
manager="${1:-$(dirname "$0")/../ss2022-shadowtls-manager.sh}"
test_root="$(mktemp -d -t ss2022-compat-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
for function_name in detect_arch safe_remove_tmpdir ssserver_usable download_shadowsocks_rust \
    install_ss2022 update_shadowsocks_rust check_and_update_all; do
    eval "$(awk -v name="$function_name" '$0 == name "() {" { printing=1 } printing { print } printing && /^}$/ { exit }' "$manager")"
done

SS_BINARY="$test_root/ssserver"
SS_RUST_REPO=shadowsocks/shadowsocks-rust
SS_SERVICE_NAME=ss2022-test.service
PROJECT_BACKUP_DIR="$test_root/backup"
MANAGER_VERSION=v1.0.21
SHORTCUT_PATH="$test_root/shortcut"
mkdir -p "$test_root/package" "$PROJECT_BACKUP_DIR"
log_info() { printf '%s\n' "$*"; }
log_warn() { log_info "$@"; }
log_error() { log_info "$@"; }
log_ok() { log_info "$@"; }
log_step() { log_info "$@"; }
suggest() { log_info "$@"; }
hr() { :; }
github_latest_tag() { echo v1.25.0; }
info_set() { printf '%s\n' "$*" >> "$test_root/state-writes"; }
info_get() {
    case "$1" in
        .ss2022.binary_version) echo v1.25.0 ;;
        .ss2022.installed) echo true ;;
        *) echo false ;;
    esac
}
curl() {
    [[ "$*" == *"x86_64-unknown-linux-musl.tar.xz" ]] || return 90
    [[ "${download_fail:-0}" == 0 ]] || return 22
    cp "$test_root/package.tar.xz" "$5"
}
install() {
    [[ "${install_fail:-0}" == 0 ]] || return 1
    command install "$@"
}

for test_arch_name in x86_64 amd64 aarch64 arm64; do
    uname() { echo "$test_arch_name"; }
    detect_arch
    case "$test_arch_name" in
        x86_64|amd64) [[ "$ARCH_RUST" == x86_64-unknown-linux-musl ]] ;;
        *) [[ "$ARCH_RUST" == aarch64-unknown-linux-musl ]] ;;
    esac
done
test_arch_name=x86_64
detect_arch
unset -f uname
printf 'PASS: supported architectures select musl\n'

# Broken executable with the same version recorded in state must not be reused.
printf '#!/bin/sh\necho "GLIBC_2.39 not found" >&2\nexit 1\n' > "$SS_BINARY"
chmod +x "$SS_BINARY"
cp "$SS_BINARY" "$test_root/original"
if ssserver_usable; then exit 1; fi
cp "$SS_BINARY" "$test_root/package/ssserver"
tar -cJf "$test_root/package.tar.xz" -C "$test_root/package" ssserver
if download_shadowsocks_rust v1.25.0 > "$test_root/log" 2>&1; then exit 1; fi
cmp "$SS_BINARY" "$test_root/original"
[[ ! -e "$test_root/state-writes" ]]
grep -q 'GLIBC_2.39' "$test_root/log"
printf 'PASS: incompatible download preserves old binary and version metadata\n'

printf '#!/bin/sh\necho "shadowsocks 1.25.0"\n' > "$test_root/package/ssserver"
tar -cJf "$test_root/package.tar.xz" -C "$test_root/package" ssserver
download_fail=1
if download_shadowsocks_rust v1.25.0 > "$test_root/log" 2>&1; then exit 1; fi
download_fail=0
install_fail=1
if download_shadowsocks_rust v1.25.0 > "$test_root/log" 2>&1; then exit 1; fi
install_fail=0
cmp "$SS_BINARY" "$test_root/original"
[[ ! -e "$test_root/state-writes" ]]
printf 'PASS: download/write failures do not report success or record a version\n'

# Stub only interactive/service operations; use the real reinstall/download logic.
install_dependencies() { :; }
ensure_project_dirs() { :; }
hint_time_before_install() { :; }
is_valid_port() { return 0; }
_port_in_use() { return 1; }
generate_ss2022_password() { echo AAAAAAAAAAAAAAAAAAAAAA==; }
set_listen_mode_interactive() { :; }
write_ss2022_config() { :; }
write_ss2022_service() { :; }
open_firewall_port() { :; }
restart_service() { printf '%s\n' "$1" >> "$test_root/restarts"; }
refresh_public_ips() { :; }
shortcut_installed() { return 0; }
show_install_result_full() { :; }
install_ss2022 <<< $'y\n1\n44336\ny\n1' > "$test_root/log" 2>&1
ssserver_usable
grep -q '重新下载' "$test_root/log"
grep -q '.ss2022.binary_version "v1.25.0"' "$test_root/state-writes"
printf 'PASS: reinstall replaces an executable that cannot run\n'

# Same-version repair via the public one-click update entry point; config untouched.
cp "$test_root/original" "$SS_BINARY"
_fetch_remote_manager_version() { echo "$MANAGER_VERSION"; }
get_manager_script_path() { echo "$manager"; }
systemctl() { :; }
check_and_update_all <<< $'y\ny' > "$test_root/log" 2>&1
grep -q '需修复（ssserver 无法运行）' "$test_root/log"
ssserver_usable
cmp "$test_root/original" "$PROJECT_BACKUP_DIR/"*.bak
printf 'PASS: one-click update repairs a broken binary even at the latest version\n'

before="$(wc -l < "$test_root/restarts")"
check_and_update_all < /dev/null > "$test_root/log" 2>&1
grep -q '全部已是最新' "$test_root/log"
[[ "$(wc -l < "$test_root/restarts")" == "$before" ]]
printf 'PASS: healthy latest binary is not downloaded or restarted\n'
