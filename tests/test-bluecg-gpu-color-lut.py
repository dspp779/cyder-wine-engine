import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
try:
    from PIL import Image, ImageCms
except ImportError:
    Image = ImageCms = None

@unittest.skipIf(Image is None, 'Pillow/ImageCms required for color LUT control')
class ColorLutTest(unittest.TestCase):
    def test_identity_profile_header_and_no_overwrite(self):
        tool = Path(__file__).resolve().parents[1] / 'tools/bluecg-gpu-blit/make-color-lut.py'
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            image = Image.new('RGB', (2, 2), 'white')
            icc = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
            image.save(root/'capture.png', icc_profile=icc)
            args = [sys.executable, str(tool), '--capture', str(root/'capture.png'), '--output', str(root/'out.lut')]
            result = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = (root/'out.lut').read_bytes()
            self.assertEqual(data[:12], b'CYDLUT1\0'+struct.pack('<I',33))
            self.assertEqual(len(data), 107823)
            self.assertEqual(data[12:15], b'\0\0\0')
            self.assertEqual(data[-3:], b'\xff\xff\xff')
            self.assertEqual(hashlib.sha256(data).hexdigest(), json.loads(result.stdout)['lut_sha256'])
            again = subprocess.run(args, capture_output=True)
            self.assertNotEqual(again.returncode, 0)
            self.assertEqual((root/'out.lut').read_bytes(), data)
            image.save(root/'plain.png')
            missing = subprocess.run([sys.executable, str(tool), '--capture', str(root/'plain.png'), '--output', str(root/'missing.lut')], capture_output=True)
            self.assertNotEqual(missing.returncode, 0)
            self.assertFalse((root/'missing.lut').exists())

if __name__ == '__main__':
    unittest.main()
