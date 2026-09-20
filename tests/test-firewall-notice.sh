#!/usr/bin/env bash
# Load only the functions under test; all firewall and service commands are mocked.
set -euo pipefail
manager="${1:-$(dirname "$0")/../ss2022-shadowtls-manager.sh}"
test_root="$(mktemp -d -t ss2022-firewall-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
for function_name in open_firewall_port set_udp_mode; do
    eval "$(awk -v name="$function_name" '$0 == name "() {" { printing=1 } printing { print } printing && /^}$/ { exit }' "$manager")"
done

detect_firewall() { echo "$test_firewall"; }
log_info() { printf '[信息] %s\n' "$*"; }
log_warn() { printf '[警告] %s\n' "$*"; }
log_ok() { printf '[成功] %s\n' "$*"; }
nft() { printf 'nft %s\n' "$*" >> "$test_root/commands"; return 99; }
ufw() { printf 'ufw %s\n' "$*" >> "$test_root/commands"; }
firewall-cmd() { printf 'firewall-cmd %s\n' "$*" >> "$test_root/commands"; }

for test_firewall in nftables nftables-present; do
    for protocol in tcp udp tcp_and_udp; do
        display_protocol="$protocol"
        [[ "$protocol" != tcp_and_udp ]] || display_protocol=tcp/udp
        open_firewall_port 22101 "$protocol" > "$test_root/output"
        [[ "$(grep -Fc '[信息]' "$test_root/output")" == 2 ]]
        grep -Fq '未检查或修改现有防火墙规则' "$test_root/output"
        [[ "$(grep -Fc "端口 22101/$display_protocol " "$test_root/output")" == 1 ]]
        if grep -Eq '警告|nftables-nat-rust-enhanced|nft add rule' "$test_root/output"; then exit 1; fi
        [[ ! -e "$test_root/commands" ]]
    done
done
printf 'PASS: nftables notices are informational, accurate and grouped; no firewall writes\n'

open_firewall_port 22102 tcp_and_udp > "$test_root/output"
grep -Fq '端口 22102/tcp/udp ' "$test_root/output"
printf 'PASS: a later operation still reports its own port\n'

# The real mode-switch caller must group the protocols as well.
SS_SERVICE_NAME=ss2022-test.service
info_get() {
    case "$1" in
        .ss2022.installed) echo true ;;
        .shadowtls.enabled) echo false ;;
        .ss2022.public_port) echo 22101 ;;
    esac
}
menu_sep() { :; }
read_menu_choice() { printf -v "$1" '%s' 3; }
info_set() { :; }
write_ss2022_config() { :; }
restart_service() { :; }
set_udp_mode > "$test_root/output"
[[ "$(grep -Fc '检测到 nft 命令' "$test_root/output")" == 1 ]]
[[ "$(grep -Fc '端口 22101/tcp/udp ' "$test_root/output")" == 1 ]]
[[ ! -e "$test_root/commands" ]]
printf 'PASS: switching to TCP+UDP emits one grouped nftables notice\n'

for test_firewall in ufw firewalld; do
    for answers in $'\n' $'n\nn'; do
        : > "$test_root/commands"
        open_firewall_port 22101 tcp_and_udp <<< "$answers" > "$test_root/output"
        [[ ! -s "$test_root/commands" ]]
        grep -Fq '22101/tcp' "$test_root/output"
        grep -Fq '22101/udp' "$test_root/output"
    done
    for answers in $'y\nn' $'n\ny' $'y\ny'; do
        : > "$test_root/commands"
        : > "$test_root/expected"
        open_firewall_port 22101 tcp_and_udp <<< "$answers" > "$test_root/output"
        for protocol in tcp udp; do
            if [[ "$protocol" == tcp ]]; then answer="${answers%%$'\n'*}"; else answer="${answers##*$'\n'}"; fi
            [[ "$answer" == y ]] || continue
            if [[ "$test_firewall" == ufw ]]; then
                printf 'ufw allow 22101/%s\n' "$protocol" >> "$test_root/expected"
            else
                printf 'firewall-cmd --permanent --add-port=22101/%s\nfirewall-cmd --reload\n' "$protocol" >> "$test_root/expected"
            fi
        done
        cmp "$test_root/expected" "$test_root/commands"
    done
done
printf 'PASS: ufw/firewalld default to no changes and require approval per protocol\n'

test_firewall=none
: > "$test_root/commands"
open_firewall_port 22101 tcp_and_udp > "$test_root/output"
grep -Fq '22101/tcp' "$test_root/output"
grep -Fq '22101/udp' "$test_root/output"
[[ ! -s "$test_root/commands" ]]
printf 'PASS: no-firewall behavior remains unchanged\n'
