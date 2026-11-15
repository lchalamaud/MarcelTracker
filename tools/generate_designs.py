#!/usr/bin/env python3
"""Generates the design proposals of the textured paladin bar into design/.

Pure standard library. Run from the addon root:
    python3 tools/generate_designs.py
Writes design/fill-*.png (bar fills, 512x64, tileable horizontally) and
design/frame-*.png (9-slice borders, 20px margins). design/index.html
assembles them into bar mock-ups. Nothing here is loaded by the game: the
retained design is meant to be ported to Media/ (see generate_textures.py).
"""
import math
import os
import random
import struct
import zlib

W, H = 512, 64
OUT = "design"

# Paladin class colour and the light that goes with it
PINK = (245, 140, 186)
PINK_LIGHT = (255, 226, 238)
GOLD_LIGHT = (255, 240, 180)


def clamp01(t):
    return 0.0 if t < 0 else 1.0 if t > 1 else t


def smoothstep(a, b, x):
    t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)


def mix(c0, c1, t):
    return tuple(c0[i] + (c1[i] - c0[i]) * t for i in range(3))


def add(c, light, k):
    return tuple(c[i] + light[i] * k for i in range(3))


def scale(c, k):
    return tuple(ch * k for ch in c)


def gradient(stops, t):
    """stops: sorted list of (position, (r, g, b))."""
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p1:
            return mix(c0, c1, 0 if p1 == p0 else (t - p0) / (p1 - p0))
    return stops[-1][1]


def make_noise(seed, cells_x, cells_y):
    """Smooth value noise in [0, 1], tileable horizontally."""
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(cells_x)] for _ in range(cells_y + 1)]

    def sample(u, v):
        x, y = u * cells_x, clamp01(v) * cells_y
        x0, y0 = int(math.floor(x)), min(int(math.floor(y)), cells_y - 1)
        fx, fy = x - x0, y - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = grid[y0][x0 % cells_x]
        b = grid[y0][(x0 + 1) % cells_x]
        c = grid[y0 + 1][x0 % cells_x]
        d = grid[y0 + 1][(x0 + 1) % cells_x]
        return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy

    return sample


def render(width, height, pixel):
    """pixel(x, y) -> (r, g, b) or (r, g, b, a in [0, 1])."""
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            p = pixel(x, y)
            alpha = p[3] if len(p) > 3 else 1.0
            row.append(tuple(max(0, min(255, int(c + 0.5))) for c in p[:3])
                       + (max(0, min(255, int(alpha * 255 + 0.5))),))
        rows.append(row)
    return rows


def write_png(path, rows):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in rows)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


# --- Fills -----------------------------------------------------------------

def incantation():
    """Modern cast bar: glossy band near the top, long flowing streaks."""
    profile = [
        (0.00, (156, 66, 108)),
        (0.07, (255, 190, 220)),
        (0.18, (255, 166, 206)),
        (0.40, PINK),
        (0.70, (214, 100, 152)),
        (0.92, (160, 60, 108)),
        (1.00, (112, 34, 72)),
    ]
    long_streaks = make_noise(21, 5, 20)
    fine_streaks = make_noise(22, 28, 32)
    wisps = make_noise(23, 8, 3)
    warp = make_noise(24, 6, 2)
    gloss_noise = make_noise(25, 10, 1)

    def pixel(x, y):
        u, v = x / W, y / (H - 1)
        c = gradient(profile, v)
        vv = clamp01(v + (warp(u, v) - 0.5) * 0.10)
        streak = (long_streaks(u, vv) * 0.6 + fine_streaks(u, vv) * 0.4 - 0.5) * 2
        c = scale(c, 1 + streak * 0.13)
        energy = max(0.0, wisps(u, vv) - 0.52) * 2.0
        c = add(c, PINK_LIGHT, energy * 0.22)
        gloss = math.exp(-((v - 0.20) / 0.085) ** 2) * (0.22 + 0.16 * gloss_noise(u, 0.5))
        return mix(c, (255, 240, 247), gloss)

    return render(W, H, pixel)


def lumiere():
    """Holy light: golden light falling from above onto the pink, with motes."""
    profile = [
        (0.00, (255, 236, 176)),
        (0.12, (255, 212, 190)),
        (0.35, (248, 150, 190)),
        (0.70, (214, 100, 152)),
        (1.00, (120, 40, 80)),
    ]
    wide_rays = make_noise(42, 12, 1)
    thin_rays = make_noise(41, 32, 1)
    grain = make_noise(43, 48, 24)
    cloud = make_noise(44, 6, 2)
    rng = random.Random(45)
    motes = [(rng.uniform(0, W), rng.uniform(6, H - 6), rng.uniform(1.2, 2.8), rng.uniform(0.4, 1.0))
             for _ in range(46)]

    def pixel(x, y):
        u, v = x / W, y / (H - 1)
        c = gradient(profile, v)
        s = ((x - y * 0.55) / W) % 1.0  # slanted shafts
        ray = max(0.0, thin_rays(s, 0.5) * 0.55 + wide_rays(s, 0.5) * 0.45 - 0.45) * 2.2
        c = add(c, GOLD_LIGHT, ray * (1 - v * 0.7) * 0.30)
        c = scale(c, 1 + (grain(u, v) - 0.5) * 0.08 + (cloud(u, v) - 0.5) * 0.12)
        glow = 0.0
        for mx, my, radius, strength in motes:
            dx = abs(x - mx)
            dx = min(dx, W - dx)
            d2 = dx * dx + (y - my) ** 2
            if d2 < 16 * radius * radius:
                glow += strength * math.exp(-d2 / (radius * radius))
        return add(c, (255, 244, 200), min(glow, 1.0) * 0.6)

    return render(W, H, pixel)


# The three fills below follow Blizzard's painted resource bars (Fury, Lunar
# Power, Maelstrom...): deep shadows, bright flowing shapes, no gloss band.
# Noise is sampled in the middle of its vertical range (0.2 + 0.6 v) so that
# domain warping has room before hitting the clamped borders.

def make_fbm(seed, cells_x, cells_y, octaves=3):
    """Sum of noise octaves, in [0, 1], tileable horizontally."""
    layers = [make_noise(seed * 10 + i, cells_x * 2 ** i, cells_y * 2 ** i) for i in range(octaves)]
    total = sum(0.5 ** i for i in range(octaves))

    def sample(u, v):
        return sum(layer(u, v) * 0.5 ** i for i, layer in enumerate(layers)) / total

    return sample


def make_stars(seed, count, min_radius, max_radius):
    """Returns glow(x, y): small points of light, the biggest with a glint."""
    rng = random.Random(seed)
    stars = [(rng.uniform(0, W), rng.uniform(8, H - 8), rng.uniform(min_radius, max_radius),
              rng.uniform(0.5, 1.0)) for _ in range(count)]

    def glow(x, y):
        total = 0.0
        for sx, sy, radius, strength in stars:
            dx = abs(x - sx)
            dx = min(dx, W - dx)
            dy = abs(y - sy)
            if dx > 14 or dy > 14:
                continue
            total += strength * math.exp(-(dx * dx + dy * dy) / (radius * radius))
            if radius > max_radius * 0.75:  # four-pointed glint
                total += strength * 0.6 * (math.exp(-dx / (radius * 2.5) - dy * dy)
                                           + math.exp(-dy / (radius * 2.5) - dx * dx))
        return min(total, 1.0)

    return glow


def vignette(c, v, strength):
    """Darkens the top and bottom edges."""
    return scale(c, 1 - strength * abs(2 * v - 1) ** 2.5)


def ferveur():
    """Fury-like: curls of light swirling over deep magenta."""
    ramp = [
        (0.00, (104, 26, 78)),
        (0.35, (190, 70, 136)),
        (0.68, PINK),
        (1.00, (255, 200, 226)),
    ]
    warp_x = make_fbm(61, 6, 2, 2)
    warp_y = make_fbm(62, 6, 2, 2)
    base = make_fbm(63, 10, 3, 2)
    shade = make_fbm(64, 7, 2, 3)
    stars = make_stars(65, 14, 0.8, 1.6)

    def pixel(x, y):
        u, v = x / W, y / (H - 1)
        vm = 0.2 + 0.6 * v
        du = (warp_x(u, vm) - 0.5) * 0.10
        dv = (warp_y(u, vm) - 0.5) * 0.45
        n = base(u + du, vm + dv)
        # contour lines of a smooth field close into loops: the curls
        curl = (0.5 + 0.5 * math.cos(2 * math.pi * n * 7)) ** 3
        tone = clamp01((shade(u + du * 0.5, vm + dv * 0.5) - 0.3) / 0.4 + (n - 0.5) * 0.5 + 0.12)
        c = gradient(ramp, tone)
        c = mix(c, PINK_LIGHT, curl * 0.45 * (0.4 + 0.6 * tone))
        c = add(c, (255, 240, 246), stars(x, y) * 0.5)
        return vignette(c, v, 0.22)

    return render(W, H, pixel)


def astral():
    """Lunar Power / Insanity-like: rose nebula in the dark, with stars."""
    ramp = [
        # shadows kept on the hue of the class colour (no drift to violet)
        (0.00, (78, 18, 50)),
        (0.30, (160, 46, 100)),
        (0.60, (230, 108, 162)),
        (0.85, PINK),
        (1.00, (255, 214, 232)),
    ]
    warp_x = make_fbm(71, 5, 2, 2)
    warp_y = make_fbm(72, 5, 2, 2)
    cloud = make_fbm(73, 6, 2, 4)
    wisp = make_fbm(74, 5, 3, 2)
    stars = make_stars(75, 34, 0.7, 2.2)

    def pixel(x, y):
        u, v = x / W, y / (H - 1)
        vm = 0.2 + 0.6 * v
        du = (warp_x(u, vm) - 0.5) * 0.14
        dv = (warp_y(u, vm) - 0.5) * 0.40
        c = gradient(ramp, clamp01((cloud(u + du, vm + dv) - 0.32) / 0.36))
        filament = (1 - abs(2 * wisp(u + du * 1.5, vm + dv * 1.5) - 1)) ** 8
        c = add(c, PINK_LIGHT, filament * 0.30)
        c = add(c, (255, 246, 226), stars(x, y) * 0.8)
        return vignette(c, v, 0.25)

    return render(W, H, pixel)


def courant():
    """Maelstrom-like: wavy currents of light running along the bar."""
    ramp = [
        (0.00, (118, 34, 88)),
        (0.40, (212, 92, 150)),
        (0.75, PINK),
        (1.00, (255, 190, 220)),
    ]
    stream = make_fbm(81, 3, 12, 2)
    warp = make_fbm(82, 5, 2, 2)
    tone = make_fbm(83, 5, 2, 2)

    def pixel(x, y):
        u, v = x / W, y / (H - 1)
        vm = 0.2 + 0.6 * v
        w = warp(u, vm)
        vv = vm + 0.10 * math.sin(2 * math.pi * u * 2 + 3 * w) + (w - 0.5) * 0.2
        filament = (1 - abs(2 * stream(u, vv) - 1)) ** 6
        t = clamp01((tone(u, vv) - 0.3) / 0.4) * 0.75 + 0.25 * (1 - v)
        c = gradient(ramp, t)
        c = mix(c, (255, 238, 222), filament * 0.55)  # warm, slightly golden light
        return vignette(c, v, 0.22)

    return render(W, H, pixel)


# --- Frames ----------------------------------------------------------------

FRAME_W, FRAME_H, FRAME_RADIUS = 96, 64, 11

METALS = {
    "or": {"dark": (122, 78, 24), "light": (255, 226, 140), "ridge": (255, 248, 214)},
    "acier": {"dark": (64, 64, 80), "light": (206, 210, 224), "ridge": (255, 255, 255)},
}


def frame(metal):
    """Bevelled metal border with an inner shadow; transparent centre."""
    dark, light, ridge_color = metal["dark"], metal["light"], metal["ridge"]

    def pixel(x, y):
        px, py = x + 0.5 - FRAME_W / 2, y + 0.5 - FRAME_H / 2
        qx = abs(px) - (FRAME_W / 2 - FRAME_RADIUS)
        qy = abs(py) - (FRAME_H / 2 - FRAME_RADIUS)
        depth = FRAME_RADIUS - math.hypot(max(qx, 0), max(qy, 0)) - min(max(qx, qy), 0)
        if depth <= -0.5:
            return (0, 0, 0, 0)

        # outward normal, to light the bevel from the top left
        if qx > 0 and qy > 0:
            length = math.hypot(qx, qy)
            nx, ny = qx / length, qy / length
        elif qx > qy:
            nx, ny = 1.0, 0.0
        else:
            nx, ny = 0.0, 1.0
        nx, ny = math.copysign(nx, px), math.copysign(ny, py)
        lit = -ny * 0.85 - nx * 0.3

        coverage = clamp01(depth + 0.5)
        if depth < 1.5:
            return (18, 8, 14, coverage)
        if depth < 8:
            k = (depth - 1.5) / 6.5
            facing = lit if k < 0.5 else -lit
            c = mix(dark, light, clamp01(0.5 + 0.5 * facing))
            ridge = math.exp(-((k - 0.5) / 0.12) ** 2)
            return mix(c, ridge_color, ridge * (0.35 + 0.25 * lit)) + (1.0,)
        if depth < 9.5:
            return (30, 12, 22, 1.0)
        if depth < 16:
            return (0, 0, 0, 0.6 * (1 - (depth - 9.5) / 6.5) ** 1.5)
        return (0, 0, 0, 0)

    return render(FRAME_W, FRAME_H, pixel)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    fills = {"incantation": incantation, "lumiere": lumiere, "ferveur": ferveur,
             "astral": astral, "courant": courant}
    for name, build in fills.items():
        write_png(os.path.join(OUT, "fill-" + name + ".png"), build())
        print("wrote fill", name)
    for name, metal in METALS.items():
        write_png(os.path.join(OUT, "frame-" + name + ".png"), frame(metal))
        print("wrote frame", name)
