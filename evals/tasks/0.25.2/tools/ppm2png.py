#!/usr/bin/env python3
"""Convert a binary PPM (P6, maxval 255) to a PNG, standard library only.

usage: ppm2png.py IN.ppm OUT.png

Provided by the eval's harness so that an agent can look at its own
program's output (the Read tool shows PNG, not PPM).
"""
import struct
import sys
import zlib


def read_token(data, pos):
    while True:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while data[pos:pos + 1] not in (b"\n", b""):
                pos += 1
            continue
        break
    start = pos
    while not data[pos:pos + 1].isspace():
        pos += 1
    return data[start:pos], pos


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: ppm2png.py IN.ppm OUT.png")
    data = open(sys.argv[1], "rb").read()
    magic, pos = read_token(data, 0)
    if magic != b"P6":
        sys.exit("ppm2png: not a binary PPM (P6): %r" % magic[:8])
    w, pos = read_token(data, pos)
    h, pos = read_token(data, pos)
    maxval, pos = read_token(data, pos)
    w, h, maxval = int(w), int(h), int(maxval)
    if maxval != 255:
        sys.exit("ppm2png: maxval %d, only 255 is supported" % maxval)
    pos += 1
    pixels = data[pos:pos + w * h * 3]
    if len(pixels) != w * h * 3:
        sys.exit("ppm2png: %d bytes of pixels, %dx%d needs %d" % (len(pixels), w, h, w * h * 3))
    raw = b"".join(b"\x00" + pixels[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(kind, body):
        c = struct.pack(">I", len(body)) + kind + body
        return c + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6))
    png += chunk(b"IEND", b"")
    open(sys.argv[2], "wb").write(png)
    print("ppm2png: wrote %s (%dx%d)" % (sys.argv[2], w, h))


if __name__ == "__main__":
    main()
