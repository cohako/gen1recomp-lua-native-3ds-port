#!/usr/bin/env python3
"""Upload the game tree to a 3DS running ftpd, into sdmc:/3ds/game/.

LÖVE Potion loads the game from a `game` folder next to the executable
(sdmc:/3ds/game), not from the 3DSX RomFS - see boot.lua's "cannot load game
at path" error. This mirrors the file set packed by scripts/pack_love.sh.

Usage: scripts/3ds/ftp_upload_game.py <3DS-IP> [--port 5000]
"""
import argparse
import os
import sys
from ftplib import FTP

REMOTE_ROOT = "/3ds/game"

# Same include set as scripts/pack_love.sh.
INCLUDE_FILES = ["main.lua", "conf.lua"]
INCLUDE_DIRS = ["src", "data", "assets"]
# Every version's import metadata (RomManifest.decode reads
# tools/rom_manifest_<version>.json), not just the Gen 1 trio.
EXTRA_FILES = sorted(
    "tools/" + f for f in os.listdir(os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
    if f.startswith("rom_manifest") and f.endswith(".json")
)
EXTRA_DIRS = ["tools/save-editor"]

SKIP_DIRS = {".git", "__pycache__", "generated"}
SKIP_SUFFIXES = (".DS_Store",)


def ensure_dir(ftp, path):
    """Create every missing component of path; ftpd has no recursive mkdir."""
    built = ""
    for part in path.strip("/").split("/"):
        built += "/" + part
        try:
            ftp.mkd(built)
        except Exception:
            pass  # already there


def upload_file(ftp, local, remote, state):
    with open(local, "rb") as fh:
        ftp.storbinary(f"STOR {remote}", fh)
    state["files"] += 1
    state["bytes"] += os.path.getsize(local)
    if state["files"] % 25 == 0:
        print(f"  {state['files']} arquivos, {state['bytes'] / 1e6:.1f} MB", flush=True)


def upload_tree(ftp, root, rel, state):
    local_dir = os.path.join(root, rel)
    remote_dir = f"{REMOTE_ROOT}/{rel}"
    ensure_dir(ftp, remote_dir)

    for entry in sorted(os.listdir(local_dir)):
        if entry in SKIP_DIRS or entry.endswith(SKIP_SUFFIXES):
            continue
        local = os.path.join(local_dir, entry)
        child_rel = f"{rel}/{entry}"
        if os.path.isdir(local):
            upload_tree(ftp, root, child_rel, state)
        else:
            upload_file(ftp, local, f"{REMOTE_ROOT}/{child_rel}", state)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host")
    ap.add_argument("--port", type=int, default=5000)
    # A directory tree of pre-converted .t3x textures (tex3ds output),
    # mirrored over the same remote root so each .t3x lands next to its .png.
    # The 3DS build cannot decode PNG at all; Assets.resolve swaps in the
    # sibling .t3x when it exists.
    ap.add_argument("--t3x", metavar="DIR", default=None)
    args = ap.parse_args()

    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    state = {"files": 0, "bytes": 0}

    ftp = FTP()
    ftp.connect(args.host, args.port, timeout=30)
    ftp.login()
    print("conectado:", ftp.getwelcome())
    ensure_dir(ftp, REMOTE_ROOT)

    for name in INCLUDE_FILES + EXTRA_FILES:
        path = os.path.join(root, name)
        if not os.path.exists(path):
            print(f"  aviso: faltando {name}", file=sys.stderr)
            continue
        remote = f"{REMOTE_ROOT}/{name}"
        ensure_dir(ftp, os.path.dirname(remote))
        upload_file(ftp, path, remote, state)

    for name in INCLUDE_DIRS + EXTRA_DIRS:
        if os.path.isdir(os.path.join(root, name)):
            print(f"enviando {name}/ ...", flush=True)
            upload_tree(ftp, root, name, state)

    if args.t3x:
        print("enviando texturas .t3x ...", flush=True)
        for name in sorted(os.listdir(args.t3x)):
            if os.path.isdir(os.path.join(args.t3x, name)):
                upload_tree(ftp, args.t3x, name, state)

    ftp.quit()
    print(f"pronto: {state['files']} arquivos, {state['bytes'] / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
