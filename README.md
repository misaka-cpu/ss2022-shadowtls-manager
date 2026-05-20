# ss2022-shadowtls-manager

SS2022 + ShadowTLS v3 one-click manager script for Debian/Ubuntu.

## Status

Current version: v0.1.0-alpha

This project is still in testing.  
Do not use it on production servers before testing on a clean Debian/Ubuntu system.

## Features

- Install and manage Shadowsocks 2022 via shadowsocks-rust
- Optional ShadowTLS v3 support
- systemd service management
- IPv4 / IPv6 support
- SS2022 URI generation
- SS2022 + ShadowTLS combined URI generation
- QR code generation
- sing-box and mihomo config output
- Basic BBR toggle
- Safe nftables behavior: this script does not modify existing nftables rules

## Supported Systems

- Debian 11 / 12
- Ubuntu 20.04 / 22.04 / 24.04
- amd64 / arm64

## Usage

```bash
chmod +x ss2022-shadowtls-manager.sh
./ss2022-shadowtls-manager.sh

