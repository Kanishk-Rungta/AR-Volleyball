"""Generate an original deterministic grayscale PNG heightmap, no packages needed."""
import math
import struct
import zlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
size = 257
pixels = bytearray()
for z in range(size):
    pixels.append(0)
    for x in range(size):
        u, v = x / (size - 1) * 2 - 1, z / (size - 1) * 2 - 1
        edge = max(0, 1 - max(abs(u), abs(v)) ** 4)
        hills = (0.50 * math.exp(-((u - .3) ** 2 + (v + .2) ** 2) * 7)
                 + .33 * math.exp(-((u + .45) ** 2 + (v - .25) ** 2) * 11)
                 + .07 * (math.sin(u * 9) * math.cos(v * 7) + 1))
        h = max(0, min(1, (.08 + hills) * edge))
        pixels.append(round(h * 255))

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 0, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
(root / 'assets').mkdir(exist_ok=True)
(root / 'assets/heightmap.png').write_bytes(png)
print('Generated assets/heightmap.png (257 x 257)')
