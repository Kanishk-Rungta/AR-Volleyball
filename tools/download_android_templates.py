"""Fetch only Android members of the official Godot template ZIP using HTTP ranges."""
import concurrent.futures
import struct
import urllib.request
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.tools'
URL = 'https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_export_templates.tpz'
SIZE = 1355592535
DEST = TOOLS / 'godot/editor_data/export_templates/4.5.1.stable'
DEST.mkdir(parents=True, exist_ok=True)

def read_range(start, end):
    for attempt in range(3):
        try:
            request = urllib.request.Request(URL, headers={'Range': f'bytes={start}-{end}'})
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.status != 206:
                    raise RuntimeError('Server did not honor range')
                data = response.read()
            if len(data) != end-start+1:
                raise RuntimeError('Truncated range')
            return data
        except Exception:
            if attempt == 2: raise

tail = read_range(SIZE-65536, SIZE-1)
entries = []
pos = 0
while True:
    pos = tail.find(b'PK\x01\x02', pos)
    if pos < 0: break
    header = struct.unpack('<IHHHHHHIIIHHHHHII', tail[pos:pos+46])
    name = tail[pos+46:pos+46+header[10]].decode()
    if name in ['templates/android_debug.apk', 'templates/android_release.apk', 'templates/android_source.zip']:
        entries.append((name, header[8], header[9], header[-1], header[7]))
    pos += 46+header[10]+header[11]+header[12]

for name, compressed, uncompressed, offset, crc in entries:
    destination = DEST / Path(name).name
    if destination.exists() and destination.stat().st_size == uncompressed:
        print('Ready: '+destination.name, flush=True)
        continue
    header = read_range(offset, offset+29)
    fields = struct.unpack('<IHHHHHIIIHH', header)
    start = offset+30+fields[-2]+fields[-1]
    block = 4*1024*1024
    spans = [(p, min(p+block-1, start+compressed-1)) for p in range(start, start+compressed, block)]
    part_dir = TOOLS / ('parts-'+destination.name)
    part_dir.mkdir(exist_ok=True)
    def fetch(span):
        a,b = span
        path = part_dir / str(a)
        if not path.exists() or path.stat().st_size != b-a+1:
            path.write_bytes(read_range(a,b))
        print('.', end='', flush=True)
        return path
    print('Downloading '+destination.name, flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        parts = list(pool.map(fetch, spans))
    decompressor = zlib.decompressobj(-15)
    checksum = 0
    with destination.open('wb') as output:
        for path in parts:
            data = decompressor.decompress(path.read_bytes())
            output.write(data)
            checksum = zlib.crc32(data, checksum)
        rest = decompressor.flush()
        output.write(rest)
        checksum = zlib.crc32(rest, checksum)
    assert decompressor.eof and destination.stat().st_size == uncompressed and checksum == crc
    print('\nReady: '+destination.name, flush=True)
(DEST / 'version.txt').write_text('4.5.1.stable')
