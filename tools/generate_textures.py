#!/usr/bin/env python3
"""Builds the textures shipped in Media/ from the retained designs in design/.

Pure standard library. Run from the addon root:
    python3 tools/generate_textures.py
The game cannot load PNG files: each design/*.png listed below is converted
to a 32-bit uncompressed TGA. design/ itself is produced by
tools/generate_designs.py and previewed in design/index.html.
"""
import os
import struct
import zlib

# design file (without extension) -> Media file (without extension)
FILLS = {
    "fill-incantation": "Incantation",
    "fill-lumiere": "Lumiere",
    "fill-ferveur": "Ferveur",
    "fill-astral": "Astral",
    "fill-courant": "Courant",
}


def read_png(path):
    """Returns (width, height, rows) with rows of (r, g, b, a) tuples.
    Supports what generate_designs.py writes: 8-bit RGB or RGBA, no interlace."""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path + ": not a PNG"

    pos, idat, header = 8, [], None
    while pos < len(data):
        length, tag = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif tag == b"IDAT":
            idat.append(body)
        pos += 12 + length

    width, height, depth, color_type, _, _, interlace = header
    assert depth == 8 and color_type in (2, 6) and interlace == 0, path + ": unsupported PNG"
    bpp = 4 if color_type == 6 else 3
    stride = width * bpp
    raw = zlib.decompress(b"".join(idat))

    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up = previous[i]
            up_left = previous[i - bpp] if i >= bpp else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                nearest = left if pa <= pb and pa <= pc else up if pb <= pc else up_left
                line[i] = (line[i] + nearest) & 255
        previous = line
        rows.append([
            (line[x * bpp], line[x * bpp + 1], line[x * bpp + 2], line[x * bpp + 3] if bpp == 4 else 255)
            for x in range(width)
        ])
    return width, height, rows


def write_tga(path, width, height, rows):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(rows):  # bottom-up
            f.write(b"".join(struct.pack("BBBB", b, g, r, a) for r, g, b, a in row))


def is_power_of_two(n):
    return n > 0 and n & (n - 1) == 0


if __name__ == "__main__":
    os.makedirs("Media", exist_ok=True)
    for source, target in FILLS.items():
        width, height, rows = read_png(os.path.join("design", source + ".png"))
        assert is_power_of_two(width) and is_power_of_two(height), source + ": size must be a power of two"
        write_tga(os.path.join("Media", target + ".tga"), width, height, rows)
        print("wrote Media/%s.tga (%dx%d)" % (target, width, height))
