#!/usr/bin/env python3
"""Write the 48x48 PNG that smdhtool needs, using only the stdlib.

Pillow/ImageMagick are not build deps for any other platform here, so the
icon is emitted directly rather than converting ports/switch/assets/icon.jpg.
"""
import struct
import sys
import zlib

W = H = 48
RGB = (30, 60, 120)


def main(path):
    raw = b"".join(b"\x00" + bytes(RGB * W) for _ in range(H))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as fh:
        fh.write(png)


if __name__ == "__main__":
    main(sys.argv[1])
