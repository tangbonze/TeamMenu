#!/usr/bin/env python3
"""Extract the logo from TeamoRouter's official favicon.ico and emit a padded PNG."""
import struct, zlib, binascii, sys

def ico_to_rgba(ico_path):
    data = open(ico_path, "rb").read()
    w = data[6] or 256
    h = data[7] or 256
    bitcount = struct.unpack("<H", data[12:14])[0]
    size = struct.unpack("<I", data[14:18])[0]
    offset = struct.unpack("<I", data[18:22])[0]
    if w != h:
        sys.exit(f"unsupported non-square ico: {w}x{h}")
    if bitcount != 32:
        sys.exit(f"unsupported bpp: {bitcount}")
    xor_bytes = w * w * 4
    raw = data[offset:offset + xor_bytes]
    px = []
    for y in range(w):
        row = raw[(w - 1 - y) * w * 4:(w - y) * w * 4]
        for x in range(w):
            b, g, r, a = row[x * 4:x * 4 + 4]
            px.append((r, g, b, a))
    return w, px

def write_png(path, w, h, rgba):
    def chunk(typ, payload):
        c = struct.pack(">I", len(payload)) + typ + payload
        return c + struct.pack(">I", binascii.crc32(typ + payload) & 0xffffffff)

    raw = b"".join(b"\x00" + b"".join(bytes(rgba[y * w + x]) for x in range(w)) for y in range(h))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)

def main():
    ico, out = sys.argv[1], sys.argv[2]
    pad = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    w, px = ico_to_rgba(ico)
    size = w + pad * 2
    canvas = [(0, 0, 0, 0)] * (size * size)
    for y in range(w):
        for x in range(w):
            canvas[(y + pad) * size + (x + pad)] = px[y * w + x]
    write_png(out, size, size, canvas)
    print(f"wrote {out}: {size}x{size} (logo {w}x{w}, pad {pad})")

if __name__ == "__main__":
    main()
