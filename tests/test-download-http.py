#!/usr/bin/env python3
"""Exercise the real Bash helper and curl against a loopback HTTP server only."""
import os
from pathlib import Path
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess
import tempfile
import threading

PAYLOAD = bytes(range(256)) * 256
requests = {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        seen = requests.setdefault(self.path, [])
        seen.append(self.headers.get("Range"))
        count = len(seen)
        if self.path == "/404":
            status = 404
        elif (self.path == "/always503" or (self.path == "/503" and count == 1)
              or (self.path == "/resume503" and count == 2)):
            status = 503
        elif self.path == "/416" and count == 2:
            status = 416
        else:
            status = 200
        offset = 0
        if (self.path == "/resume" and count > 1) or (self.path == "/resume503" and count > 2):
            offset = int(self.headers["Range"].split("=")[1].split("-")[0])
            status = 206
        self.send_response(status)
        self.send_header("Content-Length", str(len(PAYLOAD) - offset if status < 400 else 0))
        if status == 206:
            self.send_header("Content-Range", f"bytes {offset}-{len(PAYLOAD)-1}/{len(PAYLOAD)}")
        self.end_headers()
        if status >= 400:
            return
        try:
            if self.path in ("/resume", "/resume503", "/no-range", "/416") and count == 1:
                self.wfile.write(PAYLOAD[:4096])
                self.wfile.flush()
                self.connection.shutdown(socket.SHUT_RDWR)
            else:
                self.wfile.write(PAYLOAD[offset:])
        except (BrokenPipeError, ConnectionResetError):
            pass


SCRIPT = r'''
set -euo pipefail
eval "$(awk '$0 == "download_release_asset() {" { p=1 } p { print } p && /^}$/ { exit }' "$3")"
log_info() { printf '%s\n' "$*"; }
log_warn() { log_info "$@"; }
sleep() { :; }
curl() {
    printf '%s\n' "$*" >> "$TEST_CALLS"
    if [[ "$TEST_TIMEOUT" == 1 ]]; then printf 000; return 28; fi
    command curl --noproxy '*' "$@"
}
download_release_asset "$1" "$2"
'''


def main():
    manager = Path(__file__).resolve().parents[1] / "ss2022-shadowtls-manager.sh"
    server = HTTPServer(("127.0.0.1", 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        with tempfile.TemporaryDirectory(prefix="ss2022-http-test-") as temp:
            for case, attempts, success in (
                ("success", 1, True), ("resume", 2, True), ("resume503", 3, True), ("no-range", 3, True),
                ("416", 3, True), ("503", 2, True), ("always503", 3, False),
                ("404", 1, False), ("timeout", 3, False),
            ):
                target, calls = Path(temp) / case, Path(temp) / (case + ".calls")
                env = dict(os.environ, TEST_CALLS=str(calls), TEST_TIMEOUT=str(int(case == "timeout")))
                result = subprocess.run(
                    ["bash", "-c", SCRIPT, "--", f"http://127.0.0.1:{server.server_port}/{case}",
                     str(target), str(manager)], env=env, capture_output=True, text=True, timeout=20,
                )
                assert (result.returncode == 0) == success, (case, result.stdout, result.stderr)
                commands = calls.read_text().splitlines()
                assert len(commands) == attempts, (case, commands)
                for command in commands:
                    for option in ("--connect-timeout 20", "--max-time 600", "--continue-at -",
                                   "--speed-limit 1024", "--speed-time 60"):
                        assert option in command, (case, option)
                if success:
                    assert target.read_bytes() == PAYLOAD, case
                if case in ("resume", "resume503", "no-range", "416"):
                    assert requests["/" + case][1] == "bytes=4096-", (case, requests)
                if case == "resume503":
                    assert requests["/" + case][2] == "bytes=4096-", (case, requests)
                if case in ("no-range", "416"):
                    assert requests["/" + case][2] is None, (case, requests)
                print(f"PASS: {case} ({attempts} attempt(s))")
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


if __name__ == "__main__":
    main()
