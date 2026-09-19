#!/usr/bin/env python3
"""Send a CIA URL to FBI's "Receive URLs over the network" mode.

FBI listens on TCP port 5000 and expects a 4-byte big-endian length prefix
followed by the URL bytes (newline-separated for multiple URLs). Sending the
raw URL makes FBI read "http" as the length and reject it as too large.

Useful when there is no SD card reader around: the console downloads the CIA
itself.

Usage: scripts/3ds/fbi_send_url.py <3DS-IP> <url> [url ...]
"""
import socket
import struct
import sys

PORT = 5000


def main(host, urls):
    payload = "\n".join(urls).encode()
    with socket.create_connection((host, PORT), timeout=10) as sock:
        sock.sendall(struct.pack(">I", len(payload)))
        sock.sendall(payload)
    print(f"sent {len(urls)} URL(s), {len(payload)} bytes to {host}:{PORT}")
    print("watch the 2DS - FBI should prompt to install")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
