#!/usr/bin/env bash
# Real JSON/config writers, isolated paths, and mocked downloads/system services.
set -euo pipefail
manager="${1:-$(dirname "$0")/../ss2022-shadowtls-manager.sh}"
test_root="$(mktemp -d -t ss2022-state-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
for fn in info_get info_set is_ss2022_installed ssserver_usable safe_remove_tmpfile \
    write_ss2022_config write_ss2022_service install_ss2022; do
    eval "$(awk -v name="$fn" '
        $0 == name "() {" { p=1 }
        p && /<<EOF$/ { heredoc=1 }
        p { print }
        p && /^EOF$/ { heredoc=0 }
        p && /^}$/ && !heredoc { exit }
    ' "$manager")"
done
eval "$(declare -f info_set | sed '1s/info_set/real_info_set/')"
log_info() { printf '%s\n' "$*"; }
log_warn() { log_info "$@"; }
log_error() { log_info "$@"; }
log_ok() { log_info "$@"; }
log_step() { log_info "$@"; }
install_dependencies() { :; }
ensure_project_dirs() { :; }
hint_time_before_install() { :; }
is_valid_port() { [[ "$1" == 44336 ]]; }
_port_in_use() { return 1; }
generate_ss2022_password() { echo AAAAAAAAAAAAAAAAAAAAAA==; }
set_listen_mode_interactive() { printf 'listen\n' >> "$test_dir/events"; }
ss2022_listen_address() { echo 0.0.0.0; }
open_firewall_port() { :; }
refresh_public_ips() { :; }
shortcut_installed() { return 0; }
show_install_result_full() { :; }
systemctl() { [[ "$1" == daemon-reload ]]; }
backup_config() { [[ ! -f "$1" ]] || cp "$1" "$1.bak"; }
info_set() {
    [[ "$test_fail" != metadata || "$1" != .ss2022.method ]] || return 1
    [[ "$test_fail" != success_flag || "$1:$2" != .ss2022.installed:true ]] || return 1
    real_info_set "$@"
}
download_shadowsocks_rust() {
    printf 'download\n' >> "$test_dir/events"
    [[ "$test_fail" != download ]] || return 1
    printf '#!/bin/sh\nexit 0\n' > "$SS_BINARY"
    chmod +x "$SS_BINARY"
}
install() {
    [[ "$test_fail" != config || "${*: -1}" != "$SS_CONFIG" ]] || return 1
    [[ "$test_fail" != service || "${*: -1}" != "$SS_SERVICE" ]] || return 1
    command install "$@"
}
restart_service() {
    [[ "$(jq -r '.ss2022.installed' "$PROJECT_INFO")" == "$expected_before_restart" ]] || return 96
    [[ "$test_fail" != restart ]] || return 1
    printf 'started\n' >> "$test_dir/events"
}
SCRIPT_NAME=ss2022-state-test
SS_SERVICE_NAME=ss2022-test.service
case_count=0
reset_case() {
    case_count=$((case_count + 1))
    test_dir="$test_root/$case_count"
    mkdir -p "$test_dir"
    PROJECT_INFO="$test_dir/info.json"
    SS_BINARY="$test_dir/ssserver"
    SS_CONFIG="$test_dir/config.json"
    SS_SERVICE="$test_dir/ss2022.service"
    test_fail=""
    expected_before_restart=false
    jq -n --argjson installed "$1" '{ss2022:{installed:$installed,method:"old-method",password:"old-key",public_port:12345},shadowtls:{enabled:false}}' > "$PROJECT_INFO"
}
assert_not_installed() {
    [[ "$(jq -r '.ss2022.installed' "$PROJECT_INFO")" == false ]]
    if is_ss2022_installed; then return 1; fi
    if grep -q 'SS2022 安装完成' "$test_dir/log"; then return 1; fi
}
new_input=$'1\n44336\ny\n1'

for recorded in true false; do
    reset_case "$recorded"
    test_fail=download
    if install_ss2022 <<< "$new_input" > "$test_dir/log" 2>&1; then exit 1; fi
    assert_not_installed
    if grep -q 'SS2022 已安装' "$test_dir/log"; then exit 1; fi
    [[ "$(jq -r '.ss2022.password' "$PROJECT_INFO")" == old-key ]]
    [[ "$(cat "$test_dir/events")" == download ]]
done
printf 'PASS: fresh/stale download failures remain uninstalled without reinstall warnings\n'

for test_stage in metadata config service restart success_flag; do
    reset_case false
    test_fail="$test_stage"
    if install_ss2022 <<< "$new_input" > "$test_dir/log" 2>&1; then exit 1; fi
    assert_not_installed
done
printf 'PASS: metadata/config/service/startup failures cannot claim installation success\n'

reset_case false
install_ss2022 <<< "$new_input" > "$test_dir/log" 2>&1
is_ss2022_installed
grep -q 'SS2022 安装完成' "$test_dir/log"
[[ "$(jq -r '.server_port' "$SS_CONFIG")" == 44336 ]]
printf 'PASS: installed=true is recorded only after files and service startup succeed\n'

# Incomplete installs must still protect existing configuration with confirmation.
reset_case true
printf 'old config\n' > "$SS_CONFIG"
cp "$PROJECT_INFO" "$test_dir/original-info"
install_ss2022 <<< n > "$test_dir/log" 2>&1
grep -q '未完成安装或残留配置' "$test_dir/log"
if grep -q 'SS2022 已安装' "$test_dir/log"; then exit 1; fi
cmp "$PROJECT_INFO" "$test_dir/original-info"
[[ "$(cat "$SS_CONFIG")" == 'old config' && ! -e "$test_dir/events" ]]
install_ss2022 <<< $'y\n1\n44336\ny\n1' > "$test_dir/log" 2>&1
is_ss2022_installed
[[ "$(cat "$SS_CONFIG.bak")" == 'old config' ]]
printf 'PASS: incomplete configuration is protected and backed up after confirmation\n'

reset_case true
printf 'old config\n' > "$SS_CONFIG"
printf 'old unit\n' > "$SS_SERVICE"
printf '#!/bin/sh\nexit 1\n' > "$SS_BINARY"
chmod +x "$SS_BINARY"
cp "$PROJECT_INFO" "$test_dir/original-info"
expected_before_restart=true
install_ss2022 <<< n > "$test_dir/log" 2>&1
grep -q 'SS2022 已安装' "$test_dir/log"
cmp "$PROJECT_INFO" "$test_dir/original-info"
[[ ! -e "$test_dir/events" ]]
test_fail=download
if install_ss2022 <<< $'y\n1\n44336\ny\n1' > "$test_dir/log" 2>&1; then exit 1; fi
cmp "$PROJECT_INFO" "$test_dir/original-info"
is_ss2022_installed
test_fail=restart
if install_ss2022 <<< $'y\n1\n44336\ny\n1' > "$test_dir/log" 2>&1; then exit 1; fi
is_ss2022_installed
if grep -q 'SS2022 安装完成' "$test_dir/log"; then exit 1; fi
test_fail=""
install_ss2022 <<< $'y\n1\n44336\ny\n1' > "$test_dir/log" 2>&1
is_ss2022_installed
printf 'PASS: reinstall cancellation/download failure preserves prior state; normal reinstall works\n'

reset_case false
cp "$PROJECT_INFO" "$test_dir/original-info"
if real_info_set .ss2022.installed '{invalid' > "$test_dir/log" 2>&1; then exit 1; fi
cmp "$PROJECT_INFO" "$test_dir/original-info"
mktemp() { return 1; }
if real_info_set .ss2022.installed true > "$test_dir/log" 2>&1; then exit 1; fi
unset -f mktemp
mv() { return 1; }
if real_info_set .ss2022.installed true > "$test_dir/log" 2>&1; then exit 1; fi
unset -f mv
cmp "$PROJECT_INFO" "$test_dir/original-info"
printf 'PASS: JSON/tempfile/rename errors propagate instead of reporting a saved state\n'
