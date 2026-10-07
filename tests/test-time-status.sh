#!/usr/bin/env bash
# Extract functions only; never source the installer or touch real system services.
set -euo pipefail
repo="${1:-$(dirname "$0")/..}"
load_function() {
    eval "$(awk -v name="$2" '$0 == name "() {" { printing=1 } printing { print } printing && /^}$/ { exit }' "$1")"
}
have_cmd() { command -v "$1" >/dev/null 2>&1; }
print_stage() { :; }
log_step() { :; }
OS_FAMILY=debian
test_units=""
test_active=""
test_masked=""
test_bus_error=0
test_synced=yes
test_status_synced=yes
systemctl() {
    local test_unit="${*: -1}"
    [[ "$test_bus_error" == 0 ]] || return 1
    case "$1" in
        show)
            if [[ "$test_unit" == "$test_masked" ]]; then echo masked
            elif [[ " $test_units " == *" $test_unit "* ]]; then echo loaded
            else echo not-found; fi ;;
        is-active)
            if [[ "$test_unit" == "$test_active" ]]; then
                [[ "$*" == *--quiet* ]] || echo active
            else
                [[ "$*" == *--quiet* ]] || echo inactive
                return 3
            fi ;;
        *) echo 'Unexpected systemctl command' >&2; return 99 ;;
    esac
}
timedatectl() {
    case "$*" in
        'show -p NTPSynchronized --value') printf '%s\n' "$test_synced" ;;
        'show -p Timezone --value') echo UTC ;;
        'show -p NTP --value') [[ -n "$test_active" ]] && echo yes || echo no ;;
        status)
            [[ "${LC_ALL:-}" == C ]] || return 1
            printf 'System clock synchronized: %s\nNTP service: %s\n' "$test_status_synced" "${test_active:+active}" ;;
        *) return 99 ;;
    esac
}

for variant in install.sh ss2022-shadowtls-manager.sh; do
    if [[ "$variant" == install.sh ]]; then
        for fn in print_chrony_manual_commands ensure_ntp_service; do load_function "$repo/$variant" "$fn"; done
    else
        for fn in _ntp_service_unit _ntp_unit_exists _ntp_unit_active _ntp_service_state \
            _ntp_service_state_label ntp_status_label check_time_status time_status_label \
            _timedatectl_status_value _human_tz_offset show_time_status; do
            load_function "$repo/$variant" "$fn"
        done
    fi
    load_function "$repo/$variant" detect_ntp_unit
    for test_active in systemd-timesyncd.service chrony.service chronyd.service ntp.service ntpd.service ntpsec.service openntpd.service; do
        # A stopped timesyncd must not hide a running alternative.
        test_units="systemd-timesyncd.service $test_active"
        [[ "$(detect_ntp_unit)" == "$test_active" ]]
    done
    test_active=""
    test_units=systemd-timesyncd.service
    [[ "$(detect_ntp_unit)" == systemd-timesyncd.service ]]
    test_units=""
    test_masked=systemd-timesyncd.service
    [[ "$(detect_ntp_unit)" == systemd-timesyncd.service ]]
    test_masked=""
    [[ -z "$(detect_ntp_unit)" ]]
    test_bus_error=1
    [[ -z "$(detect_ntp_unit)" ]]
    test_bus_error=0

    if [[ "$variant" == install.sh ]]; then
        output="$(ensure_ntp_service)"
        [[ "$output" == *'已同步（系统报告）'* && "$output" == *'未检测到已知的本机 NTP 服务'* ]]
        test_units=systemd-timesyncd.service
        output="$(ensure_ntp_service)"
        [[ "$output" == *'systemd-timesyncd.service'* && "$output" != *'安装 chrony'* ]]
    fi
    printf 'PASS: %s detects loaded/masked NTP units and prefers running services\n' "$variant"
done

test_units=systemd-timesyncd.service
[[ "$(_ntp_service_state)" == systemd-timesyncd.service=inactive ]]
[[ "$(ntp_status_label)" == 'systemd-timesyncd.service（未运行）' ]]
test_units='systemd-timesyncd.service chrony.service'
test_active=chrony.service
[[ "$(ntp_status_label)" == 'chrony.service（运行中）' ]]
test_active=""
test_units=""
[[ "$(time_status_label)" == '已同步（系统报告）' ]]
[[ "$(ntp_status_label)" == '未检测到已知服务（或无法读取）' ]]
test_synced=no
[[ "$(check_time_status)" == unsynced ]]
test_units=systemd-timesyncd.service
output="$(show_time_status)"
[[ "$output" == *'未运行'* && "$output" != *'NTP 服务已运行'* ]]
test_synced=""
test_status_synced=yes
[[ "$(check_time_status)" == synced ]]
test_status_synced=unavailable
[[ "$(check_time_status)" == unknown ]]
printf 'PASS: clock reports and service states stay separate; inactive is not running\n'
