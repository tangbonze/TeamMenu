#!/usr/bin/env python3
"""Pack an .icns from PNG files (replacement for broken iconutil)."""
import struct, sys, os

def chunk(fourcc, data):
    return struct.pack(">4sI", fourcc.encode("ascii"), len(data) + 8) + data

def main():
    iconset = sys.argv[1]
    out = sys.argv[2]
    # fourcc -> filename inside the iconset
    files = [
        ("icp4", "icon_16x16.png"),
        ("ic04", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("ic05", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),   # 64px
        ("ic11", "icon_16x16@2x.png"),   # 32px retina
        ("ic12", "icon_32x32@2x.png"),   # 64px retina
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"), # 256px retina
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"), # 512px retina
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"), # 1024px retina
    ]
    body = b""
    for fourcc, name in files:
        p = os.path.join(iconset, name)
        if not os.path.exists(p):
            continue
        with open(p, "rb") as f:
            data = f.read()
        body += chunk(fourcc, data)
    header = struct.pack(">4sI", b"icns", len(body) + 8)
    with open(out, "wb") as f:
        f.write(header + body)
    print(f"wrote {out} ({len(body) + 8} bytes, {len(body)//8} chunks)")

if __name__ == "__main__":
    main()
