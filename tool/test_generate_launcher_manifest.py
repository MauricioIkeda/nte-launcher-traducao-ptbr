import tempfile
import unittest
from pathlib import Path

from generate_launcher_manifest import build_manifest


class GenerateLauncherManifestTests(unittest.TestCase):
    def test_generates_release_url_size_and_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            installer = Path(directory) / "Launcher-Setup.exe"
            installer.write_bytes(b"installer-contents")

            manifest = build_manifest(
                version="1.2.3",
                installer=installer,
                repository="owner/repository",
                published_at="2026-07-27T12:00:00Z",
                release_notes="Correções.",
                mandatory=False,
            )

        self.assertEqual(manifest["version"], "1.2.3")
        self.assertEqual(manifest["installer"]["size"], 18)
        self.assertEqual(
            manifest["installer"]["url"],
            "https://github.com/owner/repository/releases/download/"
            "v1.2.3/Launcher-Setup.exe",
        )
        self.assertEqual(
            manifest["installer"]["sha256"],
            "fa193b87f6ee01ac90ba67e5bcd5812fcb7f3d20c0abd3ee"
            "24518858162de576",
        )

    def test_rejects_non_semantic_version(self):
        with tempfile.TemporaryDirectory() as directory:
            installer = Path(directory) / "Launcher-Setup.exe"
            installer.write_bytes(b"x")
            with self.assertRaisesRegex(ValueError, "semantic version"):
                build_manifest(
                    version="latest",
                    installer=installer,
                    repository="owner/repository",
                    published_at="2026-07-27T12:00:00Z",
                    release_notes="",
                    mandatory=False,
                )


if __name__ == "__main__":
    unittest.main()
