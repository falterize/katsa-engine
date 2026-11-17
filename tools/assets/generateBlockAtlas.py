#!/usr/bin/env python3
"""Generates the 16x16 block tile sheet of the voxelWorld scene (a 4x4 grid, 64x64 pixels).

The tiles are drawn from a seeded noise so the file is reproducible. Tile order (row by row):
grass top, grass side, dirt, stone | sand, log side, log top, leaves | planks, cobblestone, brick, snow
| coal ore, sandstone, gravel, glass-like ice.
"""
import random
import struct
import sys
import zlib

TILE, GRID = 16, 4


def shade(color, amount):
    return tuple(max(0, min(255, int(c + amount))) for c in color)


def noisy(rng, base, spread):
    return lambda x, y: shade(base, rng.randint(-spread, spread))


def tile_grass_top(rng):
    return noisy(rng, (96, 160, 64), 14)


def tile_dirt(rng):
    return noisy(rng, (134, 96, 67), 16)


def tile_grass_side(rng):
    dirt = tile_dirt(rng)
    grass = tile_grass_top(rng)
    edge = [3 + rng.randint(0, 2) for _ in range(TILE)]

    def pixel(x, y):
        return grass(x, y) if y < edge[x] else dirt(x, y)

    return pixel


def tile_stone(rng):
    return noisy(rng, (125, 125, 125), 12)


def tile_sand(rng):
    return noisy(rng, (219, 207, 142), 9)


def tile_log_side(rng):
    def pixel(x, y):
        stripe = 18 if x % 4 in (0, 1) else -10
        return shade((102, 81, 49), stripe + rng.randint(-5, 5))

    return pixel


def tile_log_top(rng):
    def pixel(x, y):
        ring = int(max(abs(x - 7.5), abs(y - 7.5)))
        base = (176, 144, 90) if ring % 3 != 2 else (140, 108, 64)
        if ring >= 7:
            base = (102, 81, 49)
        return shade(base, rng.randint(-5, 5))

    return pixel


def tile_leaves(rng):
    def pixel(x, y):
        dark = rng.random() < 0.3
        return shade((52, 128, 40) if not dark else (34, 94, 28), rng.randint(-10, 10))

    return pixel


def tile_planks(rng):
    def pixel(x, y):
        board = y // 4
        seam = y % 4 == 3
        base = (188, 152, 98) if board % 2 == 0 else (176, 140, 88)
        return shade(base, -34 if seam else rng.randint(-6, 6))

    return pixel


def tile_cobble(rng):
    stones = [[rng.randint(-26, 26) for _ in range(4)] for _ in range(4)]

    def pixel(x, y):
        cell = stones[y // 4][x // 4]
        seam = x % 4 == 0 or y % 4 == 0
        return shade((120, 120, 120), -40 if seam else cell + rng.randint(-5, 5))

    return pixel


def tile_brick(rng):
    def pixel(x, y):
        row = y // 4
        offset = 4 if row % 2 else 0
        seam = y % 4 == 3 or (x + offset) % 8 == 7
        if seam:
            return shade((190, 190, 185), rng.randint(-5, 5))
        return shade((150, 74, 58), rng.randint(-10, 10))

    return pixel


def tile_snow(rng):
    return noisy(rng, (240, 244, 248), 5)


def tile_coal(rng):
    stone = tile_stone(rng)
    spots = {(rng.randint(1, 14), rng.randint(1, 14)) for _ in range(9)}

    def pixel(x, y):
        near = any(abs(x - sx) + abs(y - sy) <= 1 for sx, sy in spots)
        return shade((30, 30, 34), rng.randint(-6, 6)) if near else stone(x, y)

    return pixel


def tile_sandstone(rng):
    def pixel(x, y):
        band = -14 if y % 6 == 5 else 0
        return shade((214, 196, 140), band + rng.randint(-6, 6))

    return pixel


def tile_gravel(rng):
    return noisy(rng, (138, 132, 128), 28)


def tile_ice(rng):
    return noisy(rng, (150, 200, 240), 10)


TILES = [
    tile_grass_top, tile_grass_side, tile_dirt, tile_stone,
    tile_sand, tile_log_side, tile_log_top, tile_leaves,
    tile_planks, tile_cobble, tile_brick, tile_snow,
    tile_coal, tile_sandstone, tile_gravel, tile_ice,
]


def png(width, height, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xFFFFFFFF)

    raw = b''.join(b'\x00' + bytes(row) for row in rows)
    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')


def main(path):
    rng = random.Random(1337)
    size = TILE * GRID
    rows = [[0] * (size * 4) for _ in range(size)]
    for index, make in enumerate(TILES):
        pixel = make(rng)
        ox, oy = (index % GRID) * TILE, (index // GRID) * TILE
        for y in range(TILE):
            for x in range(TILE):
                r, g, b = pixel(x, y)
                at = (ox + x) * 4
                rows[oy + y][at:at + 4] = [r, g, b, 255]
    with open(path, 'wb') as handle:
        handle.write(png(size, size, rows))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'blocks.png')
