from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class VersionConsistencyTests(unittest.TestCase):
    def test_pubspec_is_not_older_than_published_launcher_manifest(self) -> None:
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        match = re.search(
            r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
            pubspec,
            flags=re.MULTILINE,
        )
        self.assertIsNotNone(match, "pubspec.yaml version is invalid")
        manifest = json.loads(
            (ROOT / "assets/manifest/launcher_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        source_version = tuple(int(part) for part in match.group(1).split("."))
        published_version = tuple(
            int(part) for part in manifest["version"].split(".")
        )
        self.assertGreaterEqual(source_version, published_version)
        self.assertGreater(int(match.group(2)), 0)


if __name__ == "__main__":
    unittest.main()
