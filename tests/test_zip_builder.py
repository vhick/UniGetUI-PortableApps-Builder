import pathlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'scripts/package_zip.py'


class IndependentZipTests(unittest.TestCase):
    def test_empty_folders_and_valid_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / 'UniGetUIPortable'
            app = root / 'App/UniGetUI'
            info = root / 'App/AppInfo'
            source = root / 'Other/Source'
            for folder in (app, info, source, root/'Data', root/'App/DefaultData/empty/nested'):
                folder.mkdir(parents=True, exist_ok=True)
            (root/'UniGetUIPortable.exe').write_bytes(b'MZfake-test-data')
            (app/'UniGetUI.exe').write_bytes(b'MZfake-test-data')
            (info/'appinfo.ini').write_text('[Format]\nType=PortableApps.comFormat\n')
            (info/'appicon.ico').write_bytes(b'placeholder-fixture-icon')
            (source/'Build-Manifest.json').write_text('{}')
            output = pathlib.Path(tmp) / 'dist' / 'result.zip'
            subprocess.run([sys.executable, str(SCRIPT), str(root), str(output)], check=True)
            with zipfile.ZipFile(output) as z:
                self.assertIsNone(z.testzip())
                self.assertIn('UniGetUIPortable/Data/', z.namelist())
                self.assertIn('UniGetUIPortable/App/DefaultData/empty/nested/', z.namelist())

    def test_prevents_user_data_in_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / 'UniGetUIPortable'
            (root/'Data').mkdir(parents=True)
            app = root / 'App/UniGetUI'
            info = root / 'App/AppInfo'
            source = root / 'Other/Source'
            for folder in (app, info, source):
                folder.mkdir(parents=True, exist_ok=True)
            (root/'UniGetUIPortable.exe').write_bytes(b'MZ')
            (app/'UniGetUI.exe').write_bytes(b'MZ')
            (info/'appinfo.ini').write_text('[Format]\nType=PortableApps.comFormat\n')
            (info/'appicon.ico').write_bytes(b'fixture')
            (source/'Build-Manifest.json').write_text('{}')
            (root/'Data/private.txt').write_text('do-not-ship')
            output = pathlib.Path(tmp) / 'result.zip'
            result = subprocess.run([sys.executable, str(SCRIPT), str(root), str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('user Data', result.stderr + result.stdout)


if __name__ == '__main__':
    unittest.main()
