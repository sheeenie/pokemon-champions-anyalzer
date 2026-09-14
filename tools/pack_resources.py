#!/usr/bin/env python3
"""Packs the app's resources into one blob that build.sh links into the executable.

Everything under Resources/ (sprites, type icons, pokedex.json) goes in, so the
built app needs no Resources folder and no setup script to run.

Format, little-endian:
  magic b"PKRS", u32 version (1), u32 entry count
  per entry: u32 path length, path (UTF-8, relative to Resources/), u64 offset, u64 length
  then the file contents back to back; offsets count from the start of the blob.

EmbeddedResources.swift reads the same format.
"""

import os
import struct
import sys


def main(src, out):
    files = []
    for dirpath, _, names in os.walk(src):
        for name in names:
            if name.startswith("."):
                continue
            full = os.path.join(dirpath, name)
            files.append((os.path.relpath(full, src).replace(os.sep, "/"), full))
    files.sort()

    index_size = sum(4 + len(path.encode("utf-8")) + 16 for path, _ in files)
    offset = 12 + index_size
    header = bytearray(b"PKRS" + struct.pack("<II", 1, len(files)))
    contents = []
    for path, full in files:
        with open(full, "rb") as f:
            data = f.read()
        encoded = path.encode("utf-8")
        header += struct.pack("<I", len(encoded)) + encoded + struct.pack("<QQ", offset, len(data))
        contents.append(data)
        offset += len(data)

    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "wb") as f:
        f.write(header)
        for data in contents:
            f.write(data)

    sprites = sum(1 for path, _ in files if path.startswith("icons/"))
    print(f"Packed {len(files)} resources ({sprites} sprites, "
          f"{offset / 1048576:.1f} MB) into {out}")
    if sprites == 0:
        print("WARNING: no sprites packed - run python3 tools/fetch_pokedex.py first")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: pack_resources.py <Resources dir> <output blob>")
    main(sys.argv[1], sys.argv[2])
