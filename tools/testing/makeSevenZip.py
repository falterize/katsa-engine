#!/usr/bin/env python3
"""Builds a minimal .7z archive from a directory (test fixtures; no external 7z tool needed).

Usage: makeSevenZip.py <directory> <output.7z> [copy|lzma|lzma2]
All files go into one solid folder; directories are stored as empty entries.
"""
import lzma
import os
import re
import struct
import sys
import zlib


def number(value):
    if value < 0x80:
        return bytes([value])
    for extra in range(1, 9):
        if value < (1 << (7 * (extra + 1))):
            first = (0xFF << (8 - extra)) & 0xFF
            return bytes([first | (value >> (8 * extra))]) + (
                value & ((1 << (8 * extra)) - 1)
            ).to_bytes(extra, 'little')
    return b'\xff' + value.to_bytes(8, 'little')


def bit_vector(flags):
    out, current, mask = bytearray(), 0, 0x80
    for flag in flags:
        if flag:
            current |= mask
        mask >>= 1
        if mask == 0:
            out.append(current)
            current, mask = 0, 0x80
    if mask != 0x80:
        out.append(current)
    return bytes(out)


def collect(root):
    directories, files = [], []
    for current, _, names in os.walk(root):
        relative = os.path.relpath(current, root)
        if relative != '.':
            directories.append(relative)
        for name in names:
            files.append(name if relative == '.' else os.path.join(relative, name))
    return sorted(directories), sorted(files)


def compress(raw, method):
    if method == 'copy':
        return raw, b'\x00', b''
    if method == 'lzma':
        filters = [{'id': lzma.FILTER_LZMA1, 'dict_size': 1 << 16, 'lc': 3, 'lp': 0, 'pb': 2}]
        packed = lzma.compress(raw, format=lzma.FORMAT_RAW, filters=filters)
        properties = bytes([3 + 9 * (0 + 5 * 2)]) + struct.pack('<I', 1 << 16)
        return packed, b'\x03\x01\x01', properties
    filters = [{'id': lzma.FILTER_LZMA2, 'dict_size': 1 << 16}]
    packed = lzma.compress(raw, format=lzma.FORMAT_RAW, filters=filters)
    return packed, b'\x21', bytes([0x0A])


def build(root, method):
    directories, files = collect(root)
    contents = [
        re.sub(rb'\blove\.', b'katsa.', open(os.path.join(root, f), 'rb').read()) for f in files
    ]
    raw = b''.join(contents)
    packed, coder_id, properties = compress(raw, method)

    header = bytearray(b'\x01\x04\x06' + number(0) + number(1) + b'\x09' + number(len(packed)))
    header += b'\x00\x07\x0b' + number(1) + b'\x00' + number(1)
    flags = len(coder_id) | (0x20 if properties else 0)
    header += bytes([flags]) + coder_id
    if properties:
        header += number(len(properties)) + properties
    header += b'\x0c' + number(len(raw)) + b'\x00'
    header += b'\x08\x0d' + number(len(files)) + b'\x09'
    for content in contents[:-1]:
        header += number(len(content))
    header += b'\x00\x00'

    entries = [(f, False) for f in files] + [(d, True) for d in directories]
    header += b'\x05' + number(len(entries))
    if directories:
        empty = bit_vector([is_directory for _, is_directory in entries])
        header += b'\x0e' + number(len(empty)) + empty
    names = b''.join(
        name.replace(os.sep, '/').encode('utf-16-le') + b'\0\0' for name, _ in entries
    )
    header += b'\x11' + number(len(names) + 1) + b'\x00' + names + b'\x00\x00'

    start = struct.pack('<QQI', len(packed), len(header), zlib.crc32(bytes(header)))
    signature = b'7z\xbc\xaf\x27\x1c\x00\x04'
    return signature + struct.pack('<I', zlib.crc32(start)) + start + packed + bytes(header)


if __name__ == '__main__':
    method = sys.argv[3] if len(sys.argv) > 3 else 'copy'
    with open(sys.argv[2], 'wb') as output:
        output.write(build(sys.argv[1], method))
