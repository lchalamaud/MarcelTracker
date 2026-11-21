#!/usr/bin/env python3
"""Builds the textures shipped in Media/: the retained designs of design/,
the highlight of unlocked bars and the border of the widgets.

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


def move_highlight(size=32, radius=5.0, border=1.6):
    """Edit Mode style highlight: a light-blue rounded border around a
    translucent blue veil. Meant to be cut in nine slices of size / 4."""
    line = (140, 214, 255)   # light blue border
    veil = (60, 150, 235)    # blue veil
    veil_alpha = 0.32
    half = size / 2
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            # signed distance to the rounded rectangle (negative inside)
            qx = abs(x + 0.5 - half) - (half - radius)
            qy = abs(y + 0.5 - half) - (half - radius)
            outside = (max(qx, 0) ** 2 + max(qy, 0) ** 2) ** 0.5
            distance = outside + min(max(qx, qy), 0) - radius

            shape = max(0.0, min(1.0, 0.5 - distance))           # inside the shape
            inner = max(0.0, min(1.0, 0.5 - (distance + border)))  # inside the border
            line_part = shape - inner
            alpha = line_part + inner * veil_alpha
            if alpha <= 0:
                row.append((0, 0, 0, 0))
                continue
            weight = line_part / alpha
            color = tuple(int(round(veil[i] + (line[i] - veil[i]) * weight)) for i in range(3))
            row.append(color + (int(round(alpha * 255)),))
        rows.append(row)
    return size, size, rows


def border(size=32, band=4, chamfer=3.0):
    """Border of the widgets, in the style of the native frames: a thin gold
    bevel lit from the top left, with a dark outer line, notched (chamfered)
    corners and a soft shadow cast inwards. Transparent centre.

    Meant to be cut in nine slices of size / 4: the band only fills the outer
    half of a slice, the inner half holds the shadow."""
    outline = (22, 15, 8)
    dark = (104, 72, 28)     # gold in the shade (bottom, right)
    light = (236, 204, 124)  # gold in the light (top, left)
    shine = (255, 244, 200)
    profile = {1: 1.0, 2: 0.86, 3: 0.62}  # brightness across the band
    slice_size = size // 4
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            dx, dy = min(px, size - px), min(py, size - py)
            diagonal = (dx + dy - chamfer) / 2 ** 0.5
            depth = min(dx, dy, diagonal)  # into the notched outer shape
            flat = min(dx, dy)             # into the square it is cut from
            coverage = max(0.0, min(1.0, depth + 0.5))
            if coverage <= 0:
                row.append((0, 0, 0, 0))
                continue

            if flat >= band:
                # inner shadow, fading over the rest of the slice
                fade = 1 - (flat - band) / (slice_size - band)
                alpha = 0.45 * max(0.0, fade) ** 1.6
                row.append((0, 0, 0, int(round(alpha * 255))))
                continue

            if depth < 1:
                color = outline
            else:
                # outward normal: (-1, 0) on the left edge, (0, -1) at the top
                if diagonal < flat:
                    nx, ny = 0.7071, 0.7071
                elif dx < dy:
                    nx, ny = 1.0, 0.0
                else:
                    nx, ny = 0.0, 1.0
                if px < size / 2:
                    nx = -nx
                if py < size / 2:
                    ny = -ny
                lit = -ny * 0.85 - nx * 0.5
                base = [dark[i] + (light[i] - dark[i]) * (0.5 + 0.5 * max(-1.0, min(1.0, lit))) for i in range(3)]
                step = min(int(depth), band - 1)
                color = [c * profile[step] for c in base]
                if step == 1 and lit > 0:
                    color = [color[i] + (shine[i] - color[i]) * 0.45 * lit for i in range(3)]
                color = tuple(int(round(max(0, min(255, c)))) for c in color)
            row.append(tuple(color) + (int(round(coverage * 255)),))
        rows.append(row)
    return size, size, rows


def is_power_of_two(n):
    return n > 0 and n & (n - 1) == 0


if __name__ == "__main__":
    os.makedirs("Media", exist_ok=True)
    for source, target in FILLS.items():
        width, height, rows = read_png(os.path.join("design", source + ".png"))
        assert is_power_of_two(width) and is_power_of_two(height), source + ": size must be a power of two"
        write_tga(os.path.join("Media", target + ".tga"), width, height, rows)
        print("wrote Media/%s.tga (%dx%d)" % (target, width, height))

    width, height, rows = move_highlight()
    write_tga(os.path.join("Media", "MoveHighlight.tga"), width, height, rows)
    print("wrote Media/MoveHighlight.tga (%dx%d)" % (width, height))

    width, height, rows = border()
    write_tga(os.path.join("Media", "Border.tga"), width, height, rows)
    print("wrote Media/Border.tga (%dx%d)" % (width, height))
