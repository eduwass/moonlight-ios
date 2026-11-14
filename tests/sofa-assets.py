#!/usr/bin/env python3
"""Run: python3 tests/sofa-assets.py — check both tvOS icon catalogs before Xcode."""
import json
import struct
from pathlib import Path

root = Path(__file__).resolve().parents[1]
for name in ['Moonlight TV', 'Consoles']:
    catalog = root / name / 'Assets.xcassets'
    for manifest in catalog.rglob('Contents.json'):
        entries = json.loads(manifest.read_text()).get('images')
        if entries is None:
            continue
        referenced = {entry['filename'] for entry in entries if 'filename' in entry}
        actual = {p.name for p in manifest.parent.iterdir() if p.suffix.lower() in ['.png', '.jpg']}
        assert actual == referenced, f'{manifest}: missing or unreferenced images: {actual ^ referenced}'
        for entry in entries:
            if 'filename' not in entry or '.imagestack/' not in str(manifest):
                continue
            image = manifest.parent / entry['filename']
            data = image.read_bytes()
            assert data[:8] == b'\x89PNG\r\n\x1a\n', image
            dimensions = struct.unpack('>II', data[16:24])
            if 'App Icon - App Store' in str(manifest):
                assert 'scale' not in entry, 'Marketing icon uses an unscaled image'
                expected = (1280, 768)
            else:
                scale = int(entry['scale'][0])
                expected = (400 * scale, 240 * scale)
            assert dimensions == expected, (image, dimensions, expected)
print('Computers and Consoles: icon sizes, manifests and image references pass.')
