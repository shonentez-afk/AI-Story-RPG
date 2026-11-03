#!/usr/bin/env python3
"""Secure the generated Flutter Android host for opt-in HTTPS Z.ai calls.

The Android host is created dynamically in CI, so modifying a checked-in
AndroidManifest.xml would have no effect. This script is deliberately small
and idempotent. Never store credentials in Android resources or the repo.
"""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
ET.register_namespace("android", "http://schemas.android.com/apk/res/android")


def configure(path: Path) -> None:
    tree = ET.parse(path)
    root = tree.getroot()
    if root.tag != "manifest":
        raise ValueError("Unexpected Android manifest")
    application = root.find("application")
    if application is None:
        raise ValueError("Android application node missing")

    permissions = [
        el for el in root.findall("uses-permission")
        if el.get(ANDROID + "name") == "android.permission.INTERNET"
    ]
    if not permissions:
        permission = ET.Element("uses-permission")
        permission.set(ANDROID + "name", "android.permission.INTERNET")
        root.insert(0, permission)
    elif len(permissions) != 1:
        raise ValueError("Duplicate INTERNET permissions")

    # The encrypted API key is bound to the current device's keystore.
    # Restoring only encrypted bytes from backup would break key unwrapping.
    application.set(ANDROID + "allowBackup", "false")
    application.set(ANDROID + "usesCleartextTraffic", "false")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    reloaded = ET.parse(path).getroot()
    checked = reloaded.find("application")
    assert checked is not None
    assert checked.get(ANDROID + "allowBackup") == "false"
    assert checked.get(ANDROID + "usesCleartextTraffic") == "false"
    assert any(e.get(ANDROID + "name") == "android.permission.INTERNET"
               for e in reloaded.findall("uses-permission"))


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "apps/story_reader/android/app/src/main/AndroidManifest.xml"
    )
    configure(target)
    print("Android host: HTTPS-only, INTERNET permission, backup disabled")
