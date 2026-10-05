#!/usr/bin/env python3
import base64
import hashlib
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 8765
ROOT = Path.home() / "Library" / "Application Support" / "ClockArtBridge"
DYLIB = ROOT / "libClockNowPlaying.dylib"
LOADER = ROOT / "clock-nowplaying.pl"

lock = threading.Lock()
state = {
    "playing": False,
    "title": None,
    "artist": None,
    "album": None,
    "bundleIdentifier": None,
    "hasArtwork": False,
    "artworkSHA256": None,
    "updatedAt": time.time(),
}
artwork_bytes = None
artwork_mime = "image/jpeg"
helper = None
dns_sd = None


def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def normalize_mime(data, declared):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return "image/gif"
    if data.startswith(b"RIFF") and b"WEBP" in data[:16]:
        return "image/webp"
    # MediaRemote has been observed declaring JPEG while returning TIFF.
    if data.startswith(b"II*\x00") or data.startswith(b"MM\x00*"):
        return "image/tiff"
    if isinstance(declared, str) and declared.startswith("image/"):
        return declared
    return "application/octet-stream"


def reader():
    global state, artwork_bytes, artwork_mime, helper

    cmd = ["/usr/bin/perl", str(LOADER), str(DYLIB)]
    helper = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    def stderr_reader():
        assert helper.stderr is not None
        for line in helper.stderr:
            line = line.rstrip()
            if line:
                print(f"[MediaRemote] {line}", file=sys.stderr, flush=True)

    threading.Thread(target=stderr_reader, daemon=True).start()

    assert helper.stdout is not None
    for line in helper.stdout:
        line = line.strip()
        if not line:
            continue

        try:
            payload = json.loads(line)
        except Exception as exc:
            print(f"[Bridge] bad helper JSON: {exc}: {line[:160]}", file=sys.stderr)
            continue

        art = None
        art_b64 = payload.pop("artworkData", None)
        if isinstance(art_b64, str):
            try:
                art = base64.b64decode(art_b64, validate=True)
            except Exception as exc:
                print(f"[Bridge] artwork decode failed: {exc}", file=sys.stderr)

        with lock:
            next_state = {
                "playing": bool(payload.get("playing", False)),
                "title": payload.get("title"),
                "artist": payload.get("artist"),
                "album": payload.get("album"),
                "bundleIdentifier": payload.get("bundleIdentifier"),
                "hasArtwork": artwork_bytes is not None,
                "artworkSHA256": state.get("artworkSHA256"),
                "updatedAt": time.time(),
            }

            if art:
                artwork_bytes = art
                artwork_mime = normalize_mime(
                    art,
                    payload.get("artworkMimeType")
                )
                next_state["hasArtwork"] = True
                next_state["artworkSHA256"] = hashlib.sha256(art).hexdigest()

            state = next_state

        label = payload.get("title") or "(no title)"
        artist = payload.get("artist") or ""
        art_note = " + artwork" if art else ""
        print(f"[Now Playing] {label} — {artist}{art_note}", flush=True)

    rc = helper.wait()
    print(f"[Bridge] MediaRemote helper exited with code {rc}", file=sys.stderr)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _headers(self, status, content_type, length):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

    def do_GET(self):
        global artwork_bytes, artwork_mime, state

        if self.path.startswith("/artwork"):
            with lock:
                data = artwork_bytes
                mime = artwork_mime

            if not data:
                body = b"No artwork yet\n"
                self._headers(404, "text/plain; charset=utf-8", len(body))
                self.wfile.write(body)
                return

            self._headers(200, mime, len(data))
            self.wfile.write(data)
            return

        if self.path.startswith("/status"):
            with lock:
                body = json.dumps(state, separators=(",", ":")).encode("utf-8")
            self._headers(200, "application/json; charset=utf-8", len(body))
            self.wfile.write(body)
            return

        body = (
            b"Clock Art Bridge is running.\n"
            b"Use /status for metadata or /artwork for the current artwork.\n"
        )
        self._headers(200, "text/plain; charset=utf-8", len(body))
        self.wfile.write(body)


def stop(*_):
    global helper, dns_sd
    if helper and helper.poll() is None:
        helper.terminate()
    if dns_sd and dns_sd.poll() is None:
        dns_sd.terminate()
    os._exit(0)


def main():
    global dns_sd

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    threading.Thread(target=reader, daemon=True).start()

    # Advertise for a future zero-config iPad client. The HTTP server works
    # without Bonjour as well.
    try:
        dns_sd = subprocess.Popen(
            [
                "/usr/bin/dns-sd",
                "-R",
                "Clock Art Bridge",
                "_clockart._tcp",
                "local",
                str(PORT),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        dns_sd = None

    ip = local_ip()
    try:
        local_name = subprocess.check_output(
            ["/usr/sbin/scutil", "--get", "LocalHostName"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        local_name = ""

    print("", flush=True)
    print("Clock Art Bridge is running.", flush=True)
    print(f"IP URL:      http://{ip}:{PORT}/status", flush=True)
    if local_name:
        print(
            f"Stable URL:  http://{local_name}.local:{PORT}/status",
            flush=True,
        )
    print("Artwork:     /artwork", flush=True)
    print("", flush=True)
    print(
        "Keep this Terminal window open for this first test. "
        "CPU use should remain near idle between track changes.",
        flush=True,
    )
    print("", flush=True)

    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever(poll_interval=1.0)


if __name__ == "__main__":
    main()
