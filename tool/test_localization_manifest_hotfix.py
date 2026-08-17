from __future__ import annotations

import copy
import unittest

from manifest_sync import (
    AUTHORIZED_REPOSITORY,
    DESTINATIONS,
    ContractError,
    compare_candidate,
    validate_public_manifest,
)

SOURCE_HASH = "0123456789ab" + ("c" * 52)
TAG = "nte-auto-20260729-120100-0123456789ab"
PUBLISHED_AT = "2026-07-29T12:01:00Z"
HOST_HASH = "e" * 64


def manifest(*, localization: bool) -> dict:
    value = {
        "schemaVersion": 1,
        "translationVersion": TAG,
        "publishedAt": PUBLISHED_AT,
        "gameBuildId": "official:test",
        "sourceHash": SOURCE_HASH,
        "files": [
            {
                "name": name,
                "relativeDestination": destination,
                "url": (
                    f"https://github.com/{AUTHORIZED_REPOSITORY}/"
                    f"releases/download/{TAG}/{name}"
                ),
                "size": 1,
                "sha256": "a" * 64,
            }
            for name, destination in DESTINATIONS.items()
        ],
    }
    if localization:
        value["localization"] = {
            "sourceCulture": "en",
            "installationCulture": "fr",
            "targetLanguage": "pt-BR",
            "hostCompatible": True,
            "hostLocresSha256": HOST_HASH,
        }
    return value


class HostedLocalizationManifestTests(unittest.TestCase):
    def test_valid_localization_is_preserved(self):
        result = validate_public_manifest(manifest(localization=True))
        self.assertEqual(
            result["localization"],
            {
                "sourceCulture": "en",
                "installationCulture": "fr",
                "targetLanguage": "pt-BR",
                "hostCompatible": True,
                "hostLocresSha256": HOST_HASH,
            },
        )

    def test_unauthorized_localization_contract_is_rejected(self):
        candidate = manifest(localization=True)
        candidate["localization"]["installationCulture"] = "de"
        with self.assertRaisesRegex(ContractError, "não autorizado"):
            validate_public_manifest(candidate)

    def test_same_release_may_receive_only_missing_localization_metadata(self):
        current = validate_public_manifest(manifest(localization=False))
        candidate = validate_public_manifest(manifest(localization=True))
        self.assertEqual(compare_candidate(current, candidate), "metadata-enriched")

        changed = copy.deepcopy(candidate)
        changed["files"][0]["size"] = 2
        with self.assertRaises(ContractError):
            compare_candidate(current, changed)


if __name__ == "__main__":
    unittest.main()
