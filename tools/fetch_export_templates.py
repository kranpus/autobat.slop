#!/usr/bin/env python3
"""Download only the Godot 4.3 export templates you need (instead of the whole
~1 GB template archive) and install them where Godot looks for them.

    python3 tools/fetch_export_templates.py web            # browser build
    python3 tools/fetch_export_templates.py web linux windows

It reads just the needed files out of the official archive with HTTP range
requests (about 33 MB for web), retrying and resuming if the connection stalls.
Uses only the Python standard library.
"""
import os
import socket
import struct
import sys
import time
import urllib.request
import zlib

VERSION = "4.3"
URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
SETS = {
    "web": ["web_nothreads_release.zip", "web_nothreads_debug.zip", "web_release.zip", "web_debug.zip"],
    "linux": ["linux_release.x86_64", "linux_debug.x86_64"],
    "windows": ["windows_release_x86_64.exe", "windows_debug_x86_64.exe",
                "windows_release_x86_64_console.exe", "windows_debug_x86_64_console.exe"],
    "macos": ["macos.zip"],
    "android": ["android_release.apk", "android_debug.apk", "android_source.zip"],
}


def template_dir() -> str:
    if sys.platform.startswith("win"):
        base = os.path.join(os.environ["APPDATA"], "Godot")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "godot")
    return os.path.join(base, "export_templates", f"{VERSION}.stable")


STALL_SECONDS = 30     # give up on a connection that sends nothing for this long...
ATTEMPTS = 8           # ...and retry (resuming where it stopped) this many times
CHUNK = 256 * 1024


def fetch(start: int, end: int, label: str = "") -> bytes:
    """Bytes start..end of the archive. Resumes after stalls and dropped
    connections, and prints progress for big pieces."""
    data = bytearray()
    total = end - start + 1
    next_report = 2 * 1024 * 1024
    for attempt in range(1, ATTEMPTS + 1):
        try:
            req = urllib.request.Request(URL, headers={"Range": f"bytes={start + len(data)}-{end}"})
            with urllib.request.urlopen(req, timeout=STALL_SECONDS) as r:
                if r.status != 206:
                    raise OSError(f"server ignored the byte range (HTTP {r.status})")
                while len(data) < total:
                    chunk = r.read(min(CHUNK, total - len(data)))
                    if not chunk:
                        break
                    data += chunk
                    if label and len(data) >= next_report:
                        print(f"    {label}: {len(data) // (1024 * 1024)} / {total // (1024 * 1024)} MB", flush=True)
                        next_report += 2 * 1024 * 1024
            if len(data) >= total:
                return bytes(data[:total])
            raise OSError("connection closed early")
        except (OSError, socket.timeout) as e:
            if attempt == ATTEMPTS:
                raise SystemExit(f"Download failed after {ATTEMPTS} attempts: {e}\n"
                                 "Check the server can reach github.com, then run the build again.")
            wait = min(30, 2 ** attempt)
            print(f"    {label or 'download'}: {e}; retrying in {wait} s ({len(data) // 1024} KB kept)", flush=True)
            time.sleep(wait)
    return bytes(data)


def main() -> int:
    wanted_sets = sys.argv[1:] or ["web"]
    want = {"templates/version.txt"}
    for s in wanted_sets:
        if s not in SETS:
            print(f"Unknown set '{s}'. Choose from: {', '.join(SETS)}")
            return 2
        want.update("templates/" + f for f in SETS[s])
    out = template_dir()
    os.makedirs(out, exist_ok=True)
    print(f"Fetching Godot {VERSION} export templates ({', '.join(wanted_sets)}) from github.com...", flush=True)
    size = 0
    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(urllib.request.Request(URL, method="HEAD"), timeout=STALL_SECONDS) as r:
                size = int(r.headers["Content-Length"])
            break
        except OSError as e:
            if attempt == ATTEMPTS:
                raise SystemExit(f"Can't reach the template archive: {e}")
            print(f"    {e}; retrying", flush=True)
            time.sleep(min(30, 2 ** attempt))
    tail = fetch(size - 65536, size - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    cd_size, cd_off = struct.unpack("<II", tail[eocd + 12:eocd + 20])
    cd = fetch(cd_off, cd_off + cd_size - 1)
    p = 0
    got = 0
    while p < len(cd):
        fields = struct.unpack("<IHHHHHHIIIHHHHHII", cd[p:p + 46])
        method, csize, nlen, elen, clen, loff = fields[4], fields[8], fields[10], fields[11], fields[12], fields[16]
        name = cd[p + 46:p + 46 + nlen].decode()
        p += 46 + nlen + elen + clen
        if name not in want:
            continue
        lh = fetch(loff, loff + 29)
        ln, le = struct.unpack("<HH", lh[26:30])
        data = fetch(loff + 30 + ln + le, loff + 30 + ln + le + csize - 1, os.path.basename(name))
        if method == 8:
            data = zlib.decompress(data, -15)
        dest = os.path.join(out, os.path.basename(name))
        with open(dest, "wb") as f:
            f.write(data)
        if not dest.endswith((".zip", ".txt", ".apk")):
            os.chmod(dest, 0o755)
        got += 1
        print(f"  {os.path.basename(name)}  ({len(data) // 1024} KB)", flush=True)
    print(f"Installed {got} file(s) into {out}", flush=True)
    return 0 if got > 1 else 1


if __name__ == "__main__":
    sys.exit(main())
