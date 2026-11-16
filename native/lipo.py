#!/usr/bin/env python3
"""Joins thin Mach-O libraries into one universal (fat) binary, like `lipo -create`.

    python3 lipo.py OUTPUT INPUT...
"""
import struct
import sys

FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF
ALIGN = 14  # 2^14 = 16 KiB, the page size of Apple Silicon


def main() -> None:
    out, inputs = sys.argv[1], sys.argv[2:]
    if not inputs:
        sys.exit("usage: lipo.py OUTPUT INPUT...")
    slices = []
    for path in inputs:
        data = open(path, "rb").read()
        magic, cputype, cpusubtype = struct.unpack_from("<IiI", data)
        if magic != MH_MAGIC_64:
            sys.exit(f"{path}: not a 64-bit Mach-O file")
        slices.append((cputype, cpusubtype, data))
    header = struct.pack(">II", FAT_MAGIC, len(slices))
    offset = len(header) + 20 * len(slices)
    table, body = b"", b""
    for cputype, cpusubtype, data in slices:
        pad = -offset % (1 << ALIGN)
        offset += pad
        body += b"\0" * pad + data
        table += struct.pack(">iIIII", cputype, cpusubtype, offset, len(data), ALIGN)
        offset += len(data)
    with open(out, "wb") as f:
        f.write(header + table + body)


if __name__ == "__main__":
    main()
