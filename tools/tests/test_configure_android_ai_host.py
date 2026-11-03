import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

from tools.configure_android_ai_host import configure, ANDROID


class AndroidAiHostTest(unittest.TestCase):
    def test_generated_manifest_is_idempotent_and_secure(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "AndroidManifest.xml"
            flutter_application = "$" + "{applicationName}"
            path.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                f'<application android:name="{flutter_application}" android:label="RPG"/>'
                '</manifest>',
                encoding="utf-8",
            )
            configure(path)
            first = path.read_bytes()
            configure(path)
            self.assertEqual(first, path.read_bytes())
            root = ET.parse(path).getroot()
            self.assertEqual(
                [p.get(ANDROID + "name") for p in root.findall("uses-permission")],
                ["android.permission.INTERNET"],
            )
            application = root.find("application")
            self.assertEqual(application.get(ANDROID + "name"),
                             flutter_application)
            self.assertEqual(application.get(ANDROID + "allowBackup"), "false")
            self.assertEqual(application.get(ANDROID + "usesCleartextTraffic"), "false")

    def test_missing_application_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "AndroidManifest.xml"
            path.write_text("<manifest/>", encoding="utf-8")
            with self.assertRaises(ValueError):
                configure(path)


if __name__ == "__main__":
    unittest.main()
