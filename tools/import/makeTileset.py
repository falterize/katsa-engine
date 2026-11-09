"""Generates the example tileset assets/textures/examples/tileset.png (8x3 tiles of 16x16).

Tiles 0-15 are the 4-neighbour autotile "ground": the index is the bitmask of neighbouring
ground cells (N=1, E=2, S=4, W=8), so tile 15 is fully surrounded and tile 0 is alone.
Tiles 16-23: water, brick, crate, spike, coin, ladder, sign, flag.
Run: python tools/import/makeTileset.py
"""
import random
from PIL import Image

T = 16
COLS, ROWS = 8, 3
STONE = [(104, 92, 84), (96, 85, 78), (112, 99, 90)]
EDGE = (62, 54, 50)
GRASS = [(84, 168, 74), (96, 184, 84), (70, 148, 62)]


def put(img, ox, oy, x, y, color):
    img.putpixel((ox + x, oy + y), color + (255,))


def ground(img, ox, oy, mask, rng):
    n, e, s, w = mask & 1, mask & 2, mask & 4, mask & 8
    for y in range(T):
        for x in range(T):
            put(img, ox, oy, x, y, rng.choice(STONE))
    if not n:
        for x in range(T):
            depth = 4 + rng.randint(0, 1)
            for y in range(depth):
                put(img, ox, oy, x, y, rng.choice(GRASS))
            put(img, ox, oy, x, depth, EDGE)
    if not s:
        for x in range(T):
            put(img, ox, oy, x, T - 1, EDGE)
    if not w:
        for y in range(T):
            put(img, ox, oy, 0, y, EDGE)
    if not e:
        for y in range(T):
            put(img, ox, oy, T - 1, y, EDGE)


def fill(img, ox, oy, color, noise=None, rng=None):
    for y in range(T):
        for x in range(T):
            c = color
            if noise:
                d = rng.randint(-noise, noise)
                c = tuple(max(0, min(255, v + d)) for v in color)
            put(img, ox, oy, x, y, c)


def main():
    rng = random.Random(7)
    img = Image.new('RGBA', (COLS * T, ROWS * T), (0, 0, 0, 0))
    for mask in range(16):
        ground(img, (mask % COLS) * T, (mask // COLS) * T, mask, rng)
    base = 2 * T
    # 16 water (semi transparent)
    for y in range(T):
        for x in range(T):
            wave = 1 if (x + y // 3) % 6 < 2 else 0
            img.putpixel((x, base + y), (60 + wave * 40, 130 + wave * 40, 220, 170))
    # 17 brick
    for y in range(T):
        for x in range(T):
            mortar = y % 8 == 7 or (x + (4 if (y // 8) % 2 else 0)) % 8 == 7
            img.putpixel((T + x, base + y), (150, 70, 60, 255) if not mortar else (190, 170, 160, 255))
    # 18 crate
    for y in range(T):
        for x in range(T):
            frame = x in (0, T - 1) or y in (0, T - 1) or x == y or x == T - 1 - y
            img.putpixel((2 * T + x, base + y), (120, 80, 40, 255) if frame else (176, 124, 66, 255))
    # 19 spike
    for y in range(T):
        for x in range(T):
            tip = abs((x % 8) - 4)
            if y > 4 + tip * 2 - 8 and y > 6 and tip < (y - 6) // 2 + 1:
                img.putpixel((3 * T + x, base + y), (200, 205, 215, 255))
    # 20 coin
    for y in range(T):
        for x in range(T):
            if (x - 7.5) ** 2 + (y - 7.5) ** 2 <= 22:
                img.putpixel((4 * T + x, base + y), (255, 205, 40, 255))
    # 21 ladder
    for y in range(T):
        for x in range(T):
            if x in (3, 12) or y % 5 == 2:
                img.putpixel((5 * T + x, base + y), (160, 110, 60, 255))
    # 22 sign, 23 flag
    for y in range(T):
        for x in range(T):
            if 6 <= x <= 9 and y >= 8:
                img.putpixel((6 * T + x, base + y), (120, 80, 40, 255))
            if 2 <= x <= 13 and 1 <= y <= 8:
                img.putpixel((6 * T + x, base + y), (200, 160, 100, 255))
            if x == 3 and y >= 1:
                img.putpixel((7 * T + x, base + y), (210, 210, 210, 255))
            if 4 <= x <= 12 and 1 <= y <= 7 and x - 4 <= (7 - abs(y - 4)) * 2:
                img.putpixel((7 * T + x, base + y), (230, 70, 70, 255))
    img.save('assets/textures/examples/tileset.png')


main()
