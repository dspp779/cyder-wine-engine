#!/usr/bin/env python3
"""Create a bounded sRGB-to-capture-profile GPU LUT; never changes OS profiles."""
import argparse
import hashlib
import io
import json
import struct
from pathlib import Path
from PIL import Image, ImageCms

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    image = Image.open(args.capture)
    icc = image.info.get('icc_profile')
    if not icc:
        parser.error('capture has no embedded output ICC profile')
    target = ImageCms.ImageCmsProfile(io.BytesIO(icc))
    source = ImageCms.createProfile('sRGB')
    levels = [round(i*255/32) for i in range(33)]
    colors = [(r,g,b) for b in levels for g in levels for r in levels]
    grid = Image.new('RGB', (33*33,33))
    grid.putdata(colors)
    converted = ImageCms.profileToProfile(grid, source, target, renderingIntent=0, outputMode='RGB')
    payload = b'CYDLUT1\0' + struct.pack('<I',33) + converted.tobytes()
    with args.output.open('xb') as file:
        file.write(payload)
    print(json.dumps(dict(edge=33, profile=ImageCms.getProfileName(target).strip(),
                          icc_sha256=hashlib.sha256(icc).hexdigest(),
                          lut_sha256=hashlib.sha256(payload).hexdigest(), bytes=len(payload))))

if __name__ == '__main__':
    main()
