"""Temporary-folder installation tests; no real installation or scanner I/O."""
from pathlib import Path
import tempfile
import unittest
from install_app import install, rollback, NAME


class PackageTests(unittest.TestCase):
    def test_install_preserve_and_rollback(self):
        source = Path(__file__).resolve().parent/'build'/NAME
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            destination = root/'Applications'/NAME
            self.assertEqual(install(source, destination), destination)
            binary = destination/'Contents/MacOS/NativeScan'
            original = binary.read_bytes()
            with self.assertRaises(FileExistsError):
                install(source, destination)
            self.assertEqual(binary.read_bytes(), original)
            moved = rollback(destination, root/'Trash')
            self.assertFalse(destination.exists())
            self.assertEqual((moved/'Contents/MacOS/NativeScan').read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
