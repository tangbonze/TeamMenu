#!/usr/bin/env python3
"""Extract the largest PNG chunk from an .icns file as a .png."""
import struct, sys

def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    if data[:4] != b"icns":
        sys.exit("not an icns: " + src)
    png_fourcc = {"icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10", "ic11", "ic12", "ic13", "ic14"}
    pos, best, bestlen = 8, None, -1
    while pos + 8 <= len(data):
        fourcc = data[pos:pos+4].decode("ascii", "replace")
        (ln,) = struct.unpack(">I", data[pos+4:pos+8])
        if fourcc in png_fourcc and ln - 8 > bestlen:
            best, bestlen = data[pos+8:pos+ln], ln - 8
        pos += ln
    if best is None:
        sys.exit("no PNG chunk in icns")
    open(dst, "wb").write(best)
    print(f"extracted {bestlen} bytes -> {dst}")

if __name__ == "__main__":
    main()
