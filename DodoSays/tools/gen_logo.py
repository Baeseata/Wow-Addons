#!/usr/bin/env python3
"""Generate the CurseForge project logo.

The addon's own board, at 400x400: one square split on its diagonals, each
quarter in the colour of the raid marker that owns it. Recognisable at the
size CurseForge actually renders it (64px in listings), which rules out
anything with detail in it.

Lives in tools/ so it never ships -- the packaging filter drops that folder.

Run:  python tools/gen_logo.py
"""

import os
import struct
import zlib

SIZE = 400
INSET = 26          # dark margin around the square
GAP = 3.0           # half-width of the seam along each diagonal
AA = 1.5

BG = (18, 18, 22)
# Clockwise from the top, matching QUADRANTS in Util.lua. The 180-degree
# quarter went from the green triangle to the purple diamond in 0.14 because
# Venomfall Deeps has a green floor and a player could not pick the green
# marker out against it -- so this file has to move with it, or the listing
# icon keeps advertising a marker the addon no longer names.
QUAD = {
    "n": (206, 58, 54),      # cross   - red
    "e": (74, 140, 226),     # square  - blue
    "s": (176, 88, 216),     # diamond - purple
    "w": (233, 150, 40),     # circle  - orange
}

HERE = os.path.dirname(os.path.abspath(__file__))


def owner_of(dx, dy):
    if abs(dx) <= abs(dy):
        return "s" if dy > 0 else "n"
    return "e" if dx > 0 else "w"


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def build():
    centre = (SIZE - 1) / 2.0
    half = SIZE / 2.0 - INSET
    rows = []

    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            dx, dy = x - centre, y - centre

            if abs(dx) > half or abs(dy) > half:
                row += bytes(BG + (255,))
                continue

            colour = QUAD[owner_of(dx, dy)]
            edge = abs(abs(dx) - abs(dy))
            if edge <= GAP:
                row += bytes(BG + (255,))
            elif edge >= GAP + AA:
                row += bytes(colour + (255,))
            else:
                row += bytes(mix(BG, colour, (edge - GAP) / AA) + (255,))
        rows.append(bytes(row))

    return rows


def write_png(path, rows):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    raw = b"".join(b"\x00" + r for r in rows)      # filter byte 0 per scanline
    blob = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))

    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)


if __name__ == "__main__":
    out = os.path.join(HERE, "logo.png")
    n = write_png(out, build())
    print("%s  %d bytes  %dx%d" % (out, n, SIZE, SIZE))
