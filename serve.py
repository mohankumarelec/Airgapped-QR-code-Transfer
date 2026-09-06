#!/usr/bin/env python3
"""Serve the app over HTTPS (phone) and HTTP (laptop sender)."""

import http.server
import os
import socket
import ssl
import subprocess
import sys
import threading

HTTPS_PORT = 8443
HTTP_PORT = 8080
DIR = os.path.dirname(os.path.abspath(__file__))
CERT = os.path.join(DIR, "cert.pem")
KEY = os.path.join(DIR, "key.pem")
CERT_VERSION = os.path.join(DIR, ".cert-version")
REQUIRED_CERT_VERSION = "2"


def local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def ensure_cert():
    needs_regen = not (
        os.path.exists(CERT)
        and os.path.exists(KEY)
        and os.path.exists(CERT_VERSION)
        and open(CERT_VERSION).read().strip() == REQUIRED_CERT_VERSION
    )

    if not needs_regen:
        return

    if os.path.exists(CERT):
        os.remove(CERT)
    if os.path.exists(KEY):
        os.remove(KEY)

    ip = local_ip()
    san = f"DNS:localhost,DNS:airgapped-qr.local,IP:127.0.0.1,IP:{ip}"
    print(f"Generating self-signed certificate (SAN: {san})...")

    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-keyout",
            KEY,
            "-out",
            CERT,
            "-days",
            "365",
            "-nodes",
            "-subj",
            "/CN=airgapped-qr.local",
            "-addext",
            f"subjectAltName={san}",
        ],
        check=True,
    )
    with open(CERT_VERSION, "w") as f:
        f.write(REQUIRED_CERT_VERSION)


def run_http_server(handler):
    httpd = http.server.HTTPServer(("0.0.0.0", HTTP_PORT), handler)
    httpd.serve_forever()


def main():
    ensure_cert()
    os.chdir(DIR)

    handler = http.server.SimpleHTTPRequestHandler
    ip = local_ip()

    http_thread = threading.Thread(
        target=run_http_server, args=(handler,), daemon=True
    )
    http_thread.start()

    httpd = http.server.HTTPServer(("0.0.0.0", HTTPS_PORT), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT, KEY)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

    print()
    print("Airgapped QR Transfer — local server")
    print("=" * 44)
    print(f"  Sender (laptop):   http://127.0.0.1:{HTTP_PORT}/generator.html")
    print(f"  Receiver (phone):  https://{ip}:{HTTPS_PORT}/scanner.html")
    print(f"  HTTPS fallback:    https://127.0.0.1:{HTTPS_PORT}/generator.html")
    print()
    print("Use the HTTP link on laptop (no certificate warning).")
    print("Use the HTTPS link on phone (accept certificate once).")
    print("Phone and computer must be on the same Wi‑Fi.")
    print("Press Ctrl+C to stop.")
    print()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        sys.exit(0)


if __name__ == "__main__":
    main()
