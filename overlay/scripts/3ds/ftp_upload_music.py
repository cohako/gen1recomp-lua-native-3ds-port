#!/usr/bin/env python3
"""Upload pre-rendered music WAVs to a 3DS running ftpd.

The renders belong beside the rest of the derived cache, under the save
directory the game imports into - NOT under /3ds/game, which only holds the
code. src/core/Music.lua looks for assets/generated/audio/music/<Song>.wav
there whenever Console.prefersPrerenderedMusic() is true.

Produce the files first with scripts/3ds/prerender_music.lua, then:

    scripts/3ds/ftp_upload_music.py <3DS-IP> --source <cacheDir>
    scripts/3ds/ftp_upload_music.py <3DS-IP> --source <cacheDir> --only Music_PalletTown

The whole Yellow set is ~76 MB, which is slow over the console's wifi, so
--only is there to prove the path works on a couple of songs first.
"""
import argparse
import os
import sys
from ftplib import FTP

REMOTE_TEMPLATE = "/3ds/save/pokemon-love2d/{version}/assets/generated/audio/music"
RELATIVE = "assets/generated/audio/music"


def ensure_dir(ftp, path):
    """Create every missing component of path; ftpd has no recursive mkdir."""
    built = ""
    for part in path.strip("/").split("/"):
        built += "/" + part
        try:
            ftp.mkd(built)
        except Exception:
            pass  # already there


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--source", required=True,
                    help="cache directory holding " + RELATIVE)
    ap.add_argument("--version", default="yellow",
                    help="cache version subdirectory on the console")
    ap.add_argument("--only", nargs="*", default=None,
                    help="upload just these song names (no .wav suffix)")
    args = ap.parse_args()

    local_dir = os.path.join(args.source, RELATIVE)
    if not os.path.isdir(local_dir):
        sys.exit(f"no renders at {local_dir} - run prerender_music.lua first")

    wanted = set(args.only) if args.only else None
    files = []
    for entry in sorted(os.listdir(local_dir)):
        if not entry.endswith(".wav"):
            continue
        if wanted is not None and entry[:-4] not in wanted:
            continue
        files.append(entry)

    if not files:
        sys.exit("nothing to upload (check --only against the rendered names)")

    total = sum(os.path.getsize(os.path.join(local_dir, f)) for f in files)
    remote_dir = REMOTE_TEMPLATE.format(version=args.version)
    print(f"{len(files)} arquivo(s), {total / 1e6:.1f} MB -> {remote_dir}")

    ftp = FTP()
    ftp.connect(args.host, args.port, timeout=30)
    ftp.login()
    print("conectado:", ftp.getwelcome())
    ensure_dir(ftp, remote_dir)

    sent = 0
    for entry in files:
        local = os.path.join(local_dir, entry)
        with open(local, "rb") as fh:
            ftp.storbinary(f"STOR {remote_dir}/{entry}", fh)
        sent += os.path.getsize(local)
        print(f"  {entry}  ({sent / 1e6:.1f}/{total / 1e6:.1f} MB)", flush=True)

    ftp.quit()
    print("pronto")


if __name__ == "__main__":
    main()
