#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Draw the original Feel4Speed selector icon using only Python's standard library.

All paths, strokes and small bitmap glyphs are defined below. No font, source
image, external asset, image library or generative-image model is used. The
256x256 RGBA PNG is rendered at 4x resolution and box-filtered for smooth edges.
Run from any directory: python art/feel4speed/dev/build_icon.py
"""

import argparse
import hashlib
import math
from pathlib import Path
import struct
import zlib


SIZE = 256
SCALE = 4
SIDE = SIZE * SCALE
PIXELS = bytearray(SIDE * SIDE * 4)
DARK = (20, 27, 32, 255)
BORDER = (56, 65, 71, 255)
LIGHT = (238, 243, 245, 255)
ORANGE = (255, 147, 72, 255)
MUTED = (187, 198, 205, 255)


def rect(x0, y0, x1, y1, color):
    """Paint an opaque rectangle in logical icon coordinates."""
    left = max(0, math.ceil(x0 * SCALE))
    right = min(SIDE, math.ceil(x1 * SCALE))
    row = bytes(color) * max(0, right - left)
    for y in range(max(0, math.ceil(y0 * SCALE)), min(SIDE, math.ceil(y1 * SCALE))):
        start = (y * SIDE + left) * 4
        PIXELS[start:start + len(row)] = row


def polygon(points, color):
    """Even/odd polygon fill, sampled on the supersampled pixel centres."""
    left = max(0, math.floor(min(x for x, _ in points) * SCALE))
    right = min(SIDE, math.ceil(max(x for x, _ in points) * SCALE))
    top = max(0, math.floor(min(y for _, y in points) * SCALE))
    bottom = min(SIDE, math.ceil(max(y for _, y in points) * SCALE))
    edges = list(zip(points, points[1:] + points[:1]))
    for y in range(top, bottom):
        py = (y + 0.5) / SCALE
        for x in range(left, right):
            px = (x + 0.5) / SCALE
            inside = False
            for (ax, ay), (bx, by) in edges:
                if (ay > py) != (by > py) and px < (bx - ax) * (py - ay) / (by - ay) + ax:
                    inside = not inside
            if inside:
                start = (y * SIDE + x) * 4
                PIXELS[start:start + 4] = bytes(color)


def rounded_rect(x0, y0, x1, y1, radius, color):
    for y in range(math.floor(y0 * SCALE), math.ceil(y1 * SCALE)):
        py = (y + 0.5) / SCALE
        cy = min(max(py, y0 + radius), y1 - radius)
        for x in range(math.floor(x0 * SCALE), math.ceil(x1 * SCALE)):
            px = (x + 0.5) / SCALE
            cx = min(max(px, x0 + radius), x1 - radius)
            if (px - cx) ** 2 + (py - cy) ** 2 <= radius ** 2:
                start = (y * SIDE + x) * 4
                PIXELS[start:start + 4] = bytes(color)


# Original hand-specified 5x7 block glyphs, used only for the small wordmark.
GLYPHS = {
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "4": ("10010", "10010", "10010", "11111", "00010", "00010", "00010"),
    "S": ("11111", "10000", "10000", "11111", "00001", "00001", "11111"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
}


def wordmark(text, x, y):
    for index, char in enumerate(text):
        for row, cells in enumerate(GLYPHS[char]):
            for column, filled in enumerate(cells):
                if filled == "1":
                    px = x + index * 14 + column * 2
                    py = y + row * 2
                    rect(px, py, px + 2, py + 2, ORANGE if char == "4" else MUTED)


def draw():
    rounded_rect(4, 4, 252, 252, 25, BORDER)
    rounded_rect(5, 5, 251, 251, 24, DARK)

    # Three original tapered speed strokes above the large geometric wordmark.
    polygon([(36, 47), (95, 47), (89, 53), (36, 53)], ORANGE)
    polygon([(36, 59), (77, 59), (71, 65), (36, 65)], ORANGE)
    polygon([(36, 71), (59, 71), (53, 77), (36, 77)], ORANGE)

    # Large F: three rectangular strokes. The 4 and S are original filled paths.
    rect(40, 91, 52, 171, LIGHT)
    rect(40, 91, 86, 103, LIGHT)
    rect(40, 121, 78, 133, LIGHT)
    polygon([(125, 91), (139, 91), (115, 130), (150, 130),
             (150, 142), (97, 142), (97, 129)], ORANGE)
    rect(138, 112, 150, 171, ORANGE)
    polygon([(218, 91), (218, 103), (184, 103), (184, 121),
             (218, 121), (218, 171), (172, 171), (172, 159),
             (206, 159), (206, 133), (172, 133), (172, 91)], LIGHT)

    wordmark("FEEL4SPEED", 60, 196)
    rect(60, 220, 196, 222, ORANGE)


def rgba_rows():
    rows = bytearray()
    samples = SCALE * SCALE
    for y in range(SIZE):
        rows.append(0)  # PNG filter: none.
        for x in range(SIZE):
            alpha = red = green = blue = 0
            for sy in range(SCALE):
                for sx in range(SCALE):
                    i = (((y * SCALE + sy) * SIDE) + x * SCALE + sx) * 4
                    r, g, b, a = PIXELS[i:i + 4]
                    alpha += a
                    red += r * a
                    green += g * a
                    blue += b * a
            if alpha:
                rows.extend((round(red / alpha), round(green / alpha),
                             round(blue / alpha), round(alpha / samples)))
            else:
                rows.extend((0, 0, 0, 0))
    return rows


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def main():
    mod_root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=mod_root / "ui/modules/apps/Feel4Speed/app.png")
    args = parser.parse_args()
    draw()
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
    png += chunk(b"IDAT", zlib.compress(rgba_rows(), 9)) + chunk(b"IEND", b"")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(png)
    print(f"Generated original {SIZE}x{SIZE} RGBA icon: {args.output}")
    print(f"SHA-256: {hashlib.sha256(png).hexdigest()}")


if __name__ == "__main__":
    main()
