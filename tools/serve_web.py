#!/usr/bin/env python3
"""Godot Web Export용 로컬 정적 서버.

Thread Support / SharedArrayBuffer를 쓰려면 브라우저가 Cross-Origin Isolation을
요구한다. file://로 index.html을 열거나, 헤더 없는 일반 서버로는 아래 에러가 난다:
  - Cross-Origin Isolation missing
  - SharedArrayBuffer missing

사용:
  python tools/serve_web.py
  → http://127.0.0.1:8080  에서 export/web 서빙
"""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import socketserver
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DIR = ROOT / "frontend" / "gomoku" / "export" / "web"

COOP = "same-origin"
COEP = "require-corp"


class CoopCoepHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **getattr(http.server.SimpleHTTPRequestHandler, "extensions_map", {}),
        ".wasm": "application/wasm",
        ".js": "application/javascript",
        ".json": "application/json",
        ".pck": "application/octet-stream",
    }

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", COOP)
        self.send_header("Cross-Origin-Embedder-Policy", COEP)
        # 로컬에서 Godot가 :8000 백엔드(WS/API)를 치므로 CORS는 백엔드 쪽에서 이미 열어둠
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve Godot Web export with COOP/COEP")
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR, help="export/web path")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    directory = args.dir.resolve()
    if not directory.is_dir():
        raise SystemExit(f"Directory not found: {directory}\nExport the Godot project first.")

    index = directory / "index.html"
    if not index.is_file():
        raise SystemExit(f"index.html not found in {directory}")

    handler = functools.partial(CoopCoepHandler, directory=str(directory))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer((args.host, args.port), handler) as httpd:
        print(f"Serving {directory}")
        print(f"Open http://{args.host}:{args.port}/")
        print("COOP=same-origin  COEP=require-corp")
        print("Ctrl+C to stop")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")


if __name__ == "__main__":
    main()
