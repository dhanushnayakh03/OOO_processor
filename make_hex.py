#!/usr/bin/env python3
import sys

# Usage: python3 make_hex.py input.bin output.mem
if len(sys.argv) < 3:
    print("Usage: python3 make_hex.py input.bin output.mem")
    sys.exit(1)

with open(sys.argv[1], "rb") as f:
    data = f.read()

# Pad to multiple of 8 bytes (64-bit lines)
while len(data) % 8 != 0:
    data += b'\x00'

with open(sys.argv[2], "w") as f:
    words = 0
    for i in range(0, len(data), 8):
        chunk = data[i:i+8]
        # In memory.v: line[63:32] is upper, line[31:0] is lower
        # chunk[0..3] is word 0 (lower), chunk[4..7] is word 1 (upper)
        val = int.from_bytes(chunk, byteorder='little')
        f.write(f"{val:016x}\n")
        words += 1
    # Pad remaining memory up to 8192 words (64KB) so $readmemh does not trigger a warning
    while words < 8192:
        f.write("0000000000000000\n")
        words += 1
