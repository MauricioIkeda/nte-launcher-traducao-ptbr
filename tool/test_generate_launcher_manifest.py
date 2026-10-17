import tempfile
import json
import subprocess
import sys
import unittest
from pathlib import Path

from generate_launcher_manifest import build_manifest


class GenerateLauncherManifestTests(unittest.TestCase):
    def test_cli_without_any_policy_flag_generates_mandatory_update(self):
        with tempfile.TemporaryDirectory() as directory:
            installer = Path(directory) / 'Setup.exe'
            installer.write_bytes(b'synthetic-installer')
            output = Path(directory) / 'manifest.json'
            subprocess.run([
                sys.executable, str(Path(__file__).with_name('generate_launcher_manifest.py')),
                '--version', '1.2.3', '--installer', str(installer),
                '--output', str(output), '--published-at', '2026-10-17T00:00:00Z',
            ], check=True, capture_output=True)
            self.assertIs(json.loads(output.read_text(encoding='utf-8'))['mandatory'], True)

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
            )

        self.assertEqual(manifest["version"], "1.2.3")
        self.assertIs(manifest["mandatory"], True)
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
                )


if __name__ == "__main__":
    unittest.main()
