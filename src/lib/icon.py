#!/usr/bin/env python3
#
# Writes one icon of a Windows program as PNG to stdout. It picks the largest
# image, like Explorer does for a big view.
#
# Usage: icon.py <file> [index]
#   <file>   an .exe or .dll, an .ico, or a .png
#   [index]  Windows' DefaultIcon index: n >= 0 is the n-th icon, -n the icon
#            with resource id n
#
# Needs icoextract for executables, which Bottles depends on. Exit codes:
# 3 icoextract missing, 4 no such icon.
#
# Copyright (C) 2026 Felitendo
# SPDX-License-Identifier: GPL-3.0-or-later

import struct
import sys
import zlib

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def png_encode(width, height, rgba):
    def chunk(kind, data):
        return (
            struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    stride = width * 4
    raw = b"".join(b"\0" + rgba[y * stride:(y + 1) * stride] for y in range(height))
    return (
        PNG_SIG
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def dib_to_png(data, width, height):
    """An icon's bitmap image: BITMAPINFOHEADER, palette, colour, AND mask."""
    (hdr, w, h2, _planes, bpp, compression) = struct.unpack_from("<IiiHHI", data, 0)
    if compression != 0 or bpp not in (1, 4, 8, 24, 32):
        raise ValueError("unsupported bitmap")
    width = width or w
    height = height or abs(h2) // 2

    colours = struct.unpack_from("<I", data, 32)[0] or (1 << bpp if bpp <= 8 else 0)
    palette_at = hdr
    pixels_at = palette_at + colours * 4
    stride = ((width * bpp + 31) // 32) * 4
    mask_at = pixels_at + stride * height
    mask_stride = ((width + 31) // 32) * 4
    has_mask = len(data) >= mask_at + mask_stride * height

    out = bytearray(width * height * 4)
    any_alpha = False

    for y in range(height):
        row = pixels_at + (height - 1 - y) * stride
        for x in range(width):
            if bpp == 32:
                b, g, r, a = data[row + x * 4:row + x * 4 + 4]
                any_alpha = any_alpha or a != 0
            elif bpp == 24:
                b, g, r = data[row + x * 3:row + x * 3 + 3]
                a = 255
            else:
                bit = x * bpp
                byte = data[row + bit // 8]
                index = (byte >> (8 - bpp - bit % 8)) & ((1 << bpp) - 1)
                b, g, r = data[palette_at + index * 4:palette_at + index * 4 + 3]
                a = 255
            o = (y * width + x) * 4
            out[o:o + 4] = bytes((r, g, b, a))

    # Without alpha of its own the AND mask says what is transparent.
    if has_mask and not (bpp == 32 and any_alpha):
        for y in range(height):
            row = mask_at + (height - 1 - y) * mask_stride
            for x in range(width):
                if data[row + x // 8] & (0x80 >> (x % 8)):
                    out[(y * width + x) * 4 + 3] = 0

    return png_encode(width, height, bytes(out))


def ico_to_png(ico):
    reserved, kind, count = struct.unpack_from("<HHH", ico, 0)
    if reserved != 0 or kind != 1 or count == 0:
        raise ValueError("not an icon")

    entries = []
    for i in range(count):
        w, h, _c, _r, _p, bpp, size, offset = struct.unpack_from("<BBBBHHII", ico, 6 + 16 * i)
        data = ico[offset:offset + size]
        if data[:8] == PNG_SIG:
            w = struct.unpack_from(">I", data, 16)[0]
            h = struct.unpack_from(">I", data, 20)[0]
            bpp = bpp or 32
        entries.append((w or 256, h or 256, bpp or 32, data))

    # Largest first, then the most colours.
    for w, h, _bpp, data in sorted(entries, key=lambda e: (e[0], e[2]), reverse=True):
        try:
            return data if data[:8] == PNG_SIG else dib_to_png(data, w, h)
        except (ValueError, struct.error, IndexError):
            continue
    raise ValueError("no usable image")


def main():
    if len(sys.argv) < 2:
        return 2
    path = sys.argv[1]
    index = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else 0

    try:
        with open(path, "rb") as f:
            head = f.read(8)
    except OSError:
        return 4

    try:
        if head == PNG_SIG:
            with open(path, "rb") as f:
                png = f.read()
        elif head[:4] == b"\0\0\1\0":
            with open(path, "rb") as f:
                png = ico_to_png(f.read())
        else:
            try:
                import icoextract
            except ImportError:
                return 3
            extractor = icoextract.IconExtractor(path)
            if index < 0:
                ico = extractor.get_icon(resource_id=-index)
            else:
                ico = extractor.get_icon(num=index)
            png = ico_to_png(ico.getvalue())
    except Exception:  # anything a broken or unusual file can throw
        return 4

    sys.stdout.buffer.write(png)
    return 0


if __name__ == "__main__":
    sys.exit(main())
