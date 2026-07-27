import hashlib
import unittest

from generate_manifest import DESTINATIONS, build_manifest


class GenerateManifestTests(unittest.TestCase):
    def test_uses_release_digests_without_downloading(self):
        release = {
            "tag_name": "1.2.3",
            "published_at": "2026-07-27T12:00:00Z",
            "assets": [
                {
                    "name": name,
                    "size": index + 1,
                    "digest": f"sha256:{str(index) * 64}",
                    "browser_download_url": (
                        "https://github.com/Luxx34/nte-pt-br/"
                        f"releases/download/1.2.3/{name}"
                    ),
                }
                for index, name in enumerate(DESTINATIONS, start=1)
            ],
        }

        manifest = build_manifest(
            release,
            "Luxx34/nte-pt-br",
            downloader=lambda *_: self.fail("Download should not be called"),
        )

        self.assertEqual(manifest["translationVersion"], "1.2.3")
        self.assertEqual(len(manifest["files"]), 5)

    def test_rejects_missing_assets(self):
        release = {
            "tag_name": "1.2.3",
            "published_at": "2026-07-27T12:00:00Z",
            "assets": [],
        }

        with self.assertRaisesRegex(ValueError, "missing assets"):
            build_manifest(release, "Luxx34/nte-pt-br")

    def test_downloads_asset_when_github_digest_is_missing(self):
        contents_by_name = {
            name: f"contents-for-{name}".encode()
            for name in DESTINATIONS
        }
        release = {
            "tag_name": "1.2.3",
            "published_at": "2026-07-27T12:00:00Z",
            "assets": [
                {
                    "name": name,
                    "size": len(contents_by_name[name]),
                    "digest": None,
                    "browser_download_url": (
                        "https://github.com/Luxx34/nte-pt-br/"
                        f"releases/download/1.2.3/{name}"
                    ),
                }
                for name in DESTINATIONS
            ],
        }

        manifest = build_manifest(
            release,
            "Luxx34/nte-pt-br",
            downloader=lambda url, _: contents_by_name[url.rsplit("/", 1)[-1]],
        )

        for file_entry in manifest["files"]:
            expected = hashlib.sha256(
                contents_by_name[file_entry["name"]]
            ).hexdigest()
            self.assertEqual(file_entry["sha256"], expected)


if __name__ == "__main__":
    unittest.main()
