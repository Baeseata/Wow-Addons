#!/usr/bin/env python3
"""Generate the four wedge masks for the board.

One square, split on its diagonals into four triangles -- which is what the
room actually looks like. A Texture is always a rectangle, so the triangle has
to live in the alpha channel.

Four separate files rather than one file rotated four ways: SetRotation's sign
convention is something this machine cannot verify without launching the game,
and "the wedges are 90 degrees out" is a bug you only find in a boss fight.
Four files cost 64 KB each and cannot be wrong.

White pixels throughout -- Board.lua tints them with SetVertexColor, so the
colour scheme stays in the Lua where it can be read and changed.

Run:  python tools/gen_wedges.py
"""

import os

SIZE = 128          # power of two, required by the client
GAP = 1.5           # half-width of the seam along each diagonal, in pixels
AA = 1.5            # antialias ramp beyond the seam

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Media")


def owner_of(dx, dy):
    """Which wedge owns this pixel. Image y grows downward."""
    if abs(dx) <= abs(dy):
        return "s" if dy > 0 else "n"
    return "e" if dx > 0 else "w"


def build(which):
    centre = (SIZE - 1) / 2.0
    px = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - centre, y - centre
            edge = abs(abs(dx) - abs(dy))    # distance to the nearest diagonal

            if owner_of(dx, dy) != which or edge <= GAP:
                alpha = 0
            elif edge >= GAP + AA:
                alpha = 255
            else:
                alpha = int(255 * (edge - GAP) / AA)

            px += bytes((255, 255, 255, alpha))   # TGA is BGRA

    header = bytes((
        0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        SIZE & 0xFF, SIZE >> 8,
        SIZE & 0xFF, SIZE >> 8,
        32,        # bits per pixel
        0x28,      # 8 alpha bits, origin top-left
    ))

    # TGA 2.0 footer. Optional by the spec, but SnakeSays' wedges are
    # 18 + 256*256*4 + 26 = 262188 bytes -- i.e. header, pixels, footer -- and
    # those are known to render in 12.1. Matching a file that demonstrably
    # works is the strongest guarantee available from a machine that cannot
    # launch the game to look.
    footer = (b"\x00\x00\x00\x00"          # no extension area
              b"\x00\x00\x00\x00"          # no developer directory
              b"TRUEVISION-XFILE." + b"\x00")

    return header + bytes(px) + footer


def main():
    os.makedirs(OUT, exist_ok=True)
    for which in ("n", "e", "s", "w"):
        blob = build(which)
        path = os.path.join(OUT, "wedge-%s.tga" % which)
        # Build fully in memory first: open(path,"wb") truncates on the spot,
        # and a half-written texture is worse than no texture.
        with open(path, "wb") as fh:
            fh.write(blob)
        print("%s  %d bytes" % (path, len(blob)))


if __name__ == "__main__":
    main()
