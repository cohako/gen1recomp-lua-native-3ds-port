#!/usr/bin/env python3
"""Mirror the console's /3ds/game and /3ds/save/pokemon-love2d trees to a
local directory (default: the Azahar virtual SD), so the exact on-device
file set runs in the emulator.

Usage: scripts/3ds/mirror_sd.py <3DS-IP> [--port 5000] [--dest DIR]

Files already present locally with the same size are skipped, so re-runs
only pull what changed.
"""
import argparse
import os
from ftplib import FTP

TREES = ["/3ds/game", "/3ds/save/pokemon-love2d"]
DEFAULT_DEST = os.path.expanduser("~/.local/share/azahar-emu/sdmc")


def walk(ftp, remote, dest, stats):
    os.makedirs(dest, exist_ok=True)
    entries = []
    ftp.retrlines(f"LIST {remote}", entries.append)
    for line in entries:
        parts = line.split(maxsplit=8)
        if len(parts) < 9:
            continue
        name = parts[8]
        if name in (".", ".."):
            continue
        rpath = f"{remote}/{name}"
        lpath = os.path.join(dest, name)
        if line.startswith("d"):
            walk(ftp, rpath, lpath, stats)
        else:
            size = int(parts[4])
            if os.path.exists(lpath) and os.path.getsize(lpath) == size:
                stats["skipped"] += 1
                continue
            with open(lpath, "wb") as fh:
                ftp.retrbinary(f"RETR {rpath}", fh.write)
            stats["files"] += 1
            stats["bytes"] += size
            if stats["files"] % 50 == 0:
                print(f"  {stats['files']} arquivos, {stats['bytes']/1e6:.1f} MB", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--dest", default=DEFAULT_DEST)
    args = ap.parse_args()

    ftp = FTP()
    ftp.connect(args.host, args.port, timeout=30)
    ftp.login()
    stats = {"files": 0, "bytes": 0, "skipped": 0}
    for tree in TREES:
        print(f"espelhando {tree} ...", flush=True)
        walk(ftp, tree, os.path.join(args.dest, tree.lstrip("/")), stats)
    ftp.quit()
    print(f"pronto: {stats['files']} baixados ({stats['bytes']/1e6:.1f} MB), "
          f"{stats['skipped']} já em dia")


if __name__ == "__main__":
    main()
