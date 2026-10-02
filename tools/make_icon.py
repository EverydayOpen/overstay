"""Render the Overstay app icon and write App/Assets.xcassets/AppIcon.appiconset.

Stdlib only (no Pillow). Shapes are signed distance functions, so every edge gets exact analytic antialiasing at
1024 px; smaller sizes are box-filtered down from the 1024 master in premultiplied alpha.

Layout follows the macOS (Big Sur and later) icon grid: 1024 canvas, 824 px body with continuous-looking corners,
soft drop shadow. Body: warm charcoal lit from the top. Glyph: an hourglass whose sand is still running (the session
is over, the processes overstayed) with a tilted ring around it and one bright dot on the ring, a straggler in orbit.
The ring passes behind the glass on its far side and in front of it on its near side. The one shape that has to
survive 16 px is the amber sand between the two cream caps.

Run from the repo root (about a minute):  python tools/make_icon.py
"""
import json
import math
import os
import struct
import zlib
from array import array

N = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets", "AppIcon.appiconset")

# Body: 824 px square centred on the canvas. A p=3 superellipse corner with a larger radius approximates Apple's
# continuous corner (curvature ramps in instead of jumping like a circle).
HALF, CORNER, P = 412.0, 278.0, 3.0
TOP, BOTTOM = (0.25, 0.215, 0.18), (0.075, 0.065, 0.055)        # warm charcoal -> near black

CX, CY = 512.0, 512.0
CAP_TOP = (CX, 252.0, 206.0, 22.0, 22.0)                          # cx, cy, half width, half height, corner radius
CAP_BOTTOM = (CX, 772.0, 206.0, 22.0, 22.0)
GLASS_H, GLASS_W0, GLASS_W1, WALL = 238.0, 160.0, 24.0, 22.0     # half height, half width at the caps and at the neck
SAND_TOP = 366.0                                                   # level of the sand left in the upper bulb
MOUND = (600.0, 0.5)                                               # lower pile: height at the centre, slope per px
RING = (360.0, 104.0, math.radians(-20.0), 17.0)                   # rx, ry, tilt, stroke
DOT_ANGLE, DOT_R = math.radians(38.0), 35.0
AMBER_TOP, AMBER_BOTTOM = (1.0, 0.76, 0.24), (0.92, 0.46, 0.05)
CREAM_TOP, CREAM_BOTTOM = (0.99, 0.95, 0.88), (0.80, 0.73, 0.62)


def cov(d):
    """Pixel coverage from a signed distance in pixels (negative = inside)."""
    return 0.0 if d >= 0.5 else 1.0 if d <= -0.5 else 0.5 - d


def seg(px, py, ax, ay, bx, by):
    """Distance from (px, py) to segment a-b."""
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def rrect(x, y, cx, cy, hw, hh, r):
    """Signed distance to a rounded rectangle."""
    qx, qy = abs(x - cx) - hw + r, abs(y - cy) - hh + r
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def body_sdf(x, y):
    qx, qy = abs(x - 512.0) - (HALF - CORNER), abs(y - 512.0) - (HALF - CORNER)
    if qx > 0 and qy > 0:
        return (qx ** P + qy ** P) ** (1 / P) - CORNER
    return max(qx, qy) - CORNER


def glass_sdf(x, y):
    """Outer wall of the hourglass: a concave flank between the caps (approximate distance, exact enough for AA)."""
    dy = abs(y - CY)
    t = min(dy / GLASS_H, 1.0)
    w = GLASS_W1 + (GLASS_W0 - GLASS_W1) * t ** 1.7
    slope = (GLASS_W0 - GLASS_W1) * 1.7 * t ** 0.7 / GLASS_H
    return max((abs(x - CX) - w) / math.sqrt(1.0 + slope * slope), dy - GLASS_H)


def ring_sdf(x, y):
    """Signed distance to the tilted ring's centreline stroke, and which side of the glass it is on (v > 0 = near)."""
    rx, ry, tilt, w = RING
    c, s = math.cos(tilt), math.sin(tilt)
    u, v = (x - CX) * c + (y - CY) * s, -(x - CX) * s + (y - CY) * c
    e = math.hypot(u / rx, v / ry)
    if e < 1e-6:
        return ry - w / 2, v
    g = math.hypot(u / (rx * rx), v / (ry * ry)) / e          # gradient length of the implicit ellipse
    return abs((e - 1.0) / g) - w / 2, v


def dot_centre():
    rx, ry, tilt, _ = RING
    u, v = rx * math.cos(DOT_ANGLE), ry * math.sin(DOT_ANGLE)
    c, s = math.cos(tilt), math.sin(tilt)
    return CX + u * c - v * s, CY + u * s + v * c


def sand_sdf(x, y, inner):
    """Signed distance to the sand: what is left in the upper bulb, the thin stream and the pile below."""
    upper = max(inner, SAND_TOP - y) if y < CY else 1e9
    stream = seg(x, y, CX, 470.0, CX, MOUND[0] + 6.0) - 7.0
    slope = math.sqrt(1.0 + MOUND[1] ** 2)
    pile = max(inner, (MOUND[0] + MOUND[1] * abs(x - CX) - y) / slope) if y > CY else 1e9
    return min(upper, stream, pile)


def over(px, i, r, g, b, a):
    """Composite straight-alpha colour (r, g, b, a) over premultiplied pixel i."""
    k = 1.0 - a
    px[i] = r * a + px[i] * k
    px[i + 1] = g * a + px[i + 1] * k
    px[i + 2] = b * a + px[i + 2] * k
    px[i + 3] = a + px[i + 3] * k


def mix(a, b, t):
    t = min(1.0, max(0.0, t))
    return [a[c] + (b[c] - a[c]) * t for c in range(3)]


def render():
    px = array("f", bytes(N * N * 16))
    union = array("f", [1e9]) * (N * N)        # hourglass distance per pixel, reused for its shadow
    shadow_k = 1 / (14.0 * math.sqrt(2))       # body shadow: sigma 14 px, 10 px down, 32 %
    gshadow_k = 1 / (12.0 * math.sqrt(2))      # hourglass shadow: sigma 12 px, 14 px down, 50 %
    dx0, dy0 = dot_centre()
    for yi in range(N):
        y = yi + 0.5
        base = mix(TOP, BOTTOM, (y - 100) / 824)
        for xi in range(N):
            x = xi + 0.5
            i = (yi * N + xi) * 4
            d_body = body_sdf(x, y)
            if d_body > -1:
                a = 0.32 * 0.5 * math.erfc(body_sdf(x, y - 10) * shadow_k)
                if a > 1 / 1024:
                    over(px, i, 0.0, 0.0, 0.0, a)
            a = cov(d_body)
            if a == 0.0:
                continue
            glow = max(0.0, 1.0 - ((x - 512) ** 2 + (y - 110) ** 2) / 640.0 ** 2) * 0.12   # soft light from the top
            over(px, i, *mix(base, (1, 1, 1), glow), a)
            lamp = max(0.0, 1.0 - ((x - CX) ** 2 + (y - CY - 40) ** 2) / 380.0 ** 2) ** 2 * 0.26   # warm lamp glow
            over(px, i, *AMBER_TOP, lamp * a)
            over(px, i, 1.0, 1.0, 1.0, 0.12 * cov(abs(d_body + 2.0) - 1.5))   # thin rim: keeps the edge on dark Docks
            if not (110 < x < 914 and 190 < y < 840):   # glyph + its shadow
                continue
            ring, v = ring_sdf(x, y)
            near = min(1.0, max(0.0, v / 34.0 + 0.5))   # 0 on the far side of the glass, 1 on the near side, blended at the ends
            over(px, i, *CREAM_TOP, 0.42 * (1.0 - near) * cov(ring))
            g = glass_sdf(x, y)
            cap_a, cap_b = rrect(x, y, *CAP_TOP), rrect(x, y, *CAP_BOTTOM)
            whole = min(g, cap_a, cap_b)
            union[i // 4] = whole
            d_shadow = union[i // 4 - 14 * N]           # 14 px above casts onto here
            if d_shadow < 40:
                over(px, i, 0.0, 0.0, 0.0, 0.5 * 0.5 * math.erfc(d_shadow * gshadow_k))
            over(px, i, *CREAM_TOP, 0.17 * cov(g))                                    # the glass itself
            over(px, i, *mix(CREAM_TOP, CREAM_BOTTOM, (y - 290) / 460), 0.88 * cov(abs(g + WALL / 2) - WALL / 2))   # its wall
            sand = sand_sdf(x, y, g + WALL)
            over(px, i, *mix(AMBER_TOP, AMBER_BOTTOM, (y - SAND_TOP) / 420), cov(sand))
            over(px, i, 1.0, 0.97, 0.82, 0.45 * cov(sand) * cov(abs(y - SAND_TOP - 3) - 3) if y < CY else 0.0)   # level line
            for cap, d in ((CAP_TOP, cap_a), (CAP_BOTTOM, cap_b)):
                over(px, i, *mix(CREAM_TOP, CREAM_BOTTOM, (y - (cap[1] - cap[4])) / (2 * cap[4])), cov(d))
            over(px, i, *CREAM_TOP, 0.95 * near * cov(ring))   # near side of the ring, in front of everything
            d_dot = math.hypot(x - dx0, y - dy0) - DOT_R
            if d_dot < 60:
                over(px, i, *AMBER_TOP, 0.55 * 0.5 * math.erfc(d_dot / (16.0 * math.sqrt(2)) * 1.0))   # halo
                over(px, i, *mix(AMBER_TOP, AMBER_BOTTOM, (y - dy0 + DOT_R) / (2 * DOT_R)), cov(d_dot))
                over(px, i, 1.0, 0.98, 0.88, 0.8 * cov(math.hypot(x - dx0 + 10, y - dy0 + 11) - 11))   # highlight
    return px


def half(px, n):
    """2x2 box filter (premultiplied, so edges don't darken)."""
    m = n // 2
    out = array("f", bytes(m * m * 16))
    row = n * 4
    for y in range(m):
        r0 = 2 * y * row
        r1 = r0 + row
        o = y * m * 4
        for x in range(m):
            i, j, k = r0 + 8 * x, r1 + 8 * x, o + 4 * x
            for c in range(4):
                out[k + c] = (px[i + c] + px[i + 4 + c] + px[j + c] + px[j + 4 + c]) * 0.25
    return out


def write_png(path, px, n):
    raw = bytearray()
    for y in range(n):
        raw.append(0)  # filter: none
        for x in range(n):
            i = (y * n + x) * 4
            a = px[i + 3]
            if a < 1 / 512:
                raw += b"\0\0\0\0"
                continue
            raw += bytes(min(255, int(px[i + c] / a * 255 + 0.5)) for c in range(3))
            raw.append(min(255, int(a * 255 + 0.5)))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0)))
        f.write(chunk(b"sRGB", b"\0"))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def main():
    os.makedirs(OUT, exist_ok=True)
    images, by_size = [], {N: render()}
    n = N
    while n > 16:
        by_size[n // 2] = half(by_size[n], n)
        n //= 2
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            write_png(os.path.join(OUT, name), by_size[pt * scale], pt * scale)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    with open(os.path.join(OUT, "Contents.json"), "w", newline="\n") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    with open(os.path.join(OUT, "..", "Contents.json"), "w", newline="\n") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    print(f"wrote {len(images)} PNGs to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
