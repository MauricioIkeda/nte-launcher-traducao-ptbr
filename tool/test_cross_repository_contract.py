from __future__ import annotations

import csv
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

from manifest_sync import (
    AUTHORIZED_REPOSITORY,
    atomic_apply_candidate,
    candidate_from_dispatch,
    canonical_bytes,
    parse_public_manifest,
)

PIPELINE_REPOSITORY = (
    Path(__file__).resolve().parents[2] / "nte-translation-pipeline"
)


@unittest.skipUnless(
    (PIPELINE_REPOSITORY / "nte_pipeline").is_dir(),
    "repositório privado da pipeline não está disponível neste checkout",
)
class CrossRepositoryContractTests(unittest.TestCase):
    def test_pipeline_output_is_consumed_atomically_by_launcher(self) -> None:
        sys.path.insert(0, str(PIPELINE_REPOSITORY))
        try:
            from nte_pipeline.integrity import (
                atomic_write_json,
                create_source_identity,
            )
            from nte_pipeline.manifests import (
                PAYLOAD_NAMES,
                Artifact,
                build_manifest_v2,
            )
            from nte_pipeline.release_transaction import (
                dispatch_payload,
                prepare_release,
            )

            with tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                locres = root / "Game.locres"
                locres.write_bytes(b"canonical NTE locres")
                source_csv = root / "source.csv"
                with source_csv.open(
                    "w", encoding="utf-8-sig", newline=""
                ) as handle:
                    writer = csv.DictWriter(
                        handle,
                        fieldnames=("key", "source", "Translation"),
                    )
                    writer.writeheader()
                    for index in range(5):
                        writer.writerow(
                            {
                                "key": f"ui::{index}",
                                "source": f"Source {index}",
                                "Translation": f"Tradução {index}",
                            }
                        )
                identity = create_source_identity(
                    locres,
                    source_csv,
                    game_build_id="nte-build-integrated",
                    extracted_at="2026-07-29T12:00:00.123Z",
                )
                release_dir = root / "release"
                release_dir.mkdir()
                artifacts = []
                for index, name in enumerate(PAYLOAD_NAMES):
                    path = release_dir / name
                    path.write_bytes(f"payload-{index}-{name}".encode())
                    artifacts.append(Artifact.from_path(path))
                build = build_manifest_v2(
                    created_at="2026-07-29T12:00:00.123Z",
                    pipeline_version="integrated-audit",
                    pipeline_commit=None,
                    identity=identity,
                    translation={
                        "total": 5,
                        "validated": 5,
                        "humanReviewed": 5,
                        "machineTranslated": 0,
                        "memoryReused": 0,
                        "pending": 0,
                        "invalid": 0,
                    },
                    translation_provenance={
                        "total": 5,
                        "automatic": 0,
                        "deterministic": 0,
                        "imported": 0,
                        "manualCorrections": 5,
                        "manualUniqueEntries": 5,
                        "reusedFromMemory": 0,
                        "pending": 0,
                        "invalid": 0,
                        "validatedEmpty": 0,
                    },
                    tools={
                        "ueExtractor": {
                            "version": "1.0.8.4",
                            "sha256": "a" * 64,
                            "dllSha256": "c" * 64,
                        },
                        "repak": {
                            "version": "0.2.3",
                            "sha256": "b" * 64,
                        },
                    },
                    files=artifacts,
                    deterministic=True,
                )
                atomic_write_json(release_dir / "build-manifest.json", build)
                prepared = prepare_release(
                    release_dir,
                    AUTHORIZED_REPOSITORY,
                    published_at="2026-07-29T12:01:00.987Z",
                )

                downloads: dict[str, bytes] = {}
                release_assets = []
                for asset_id, item in enumerate(prepared.files, start=1):
                    contents = item.path.read_bytes()
                    api_url = (
                        "https://api.github.com/repos/"
                        f"{AUTHORIZED_REPOSITORY}/releases/assets/{asset_id}"
                    )
                    browser_url = (
                        f"https://github.com/{AUTHORIZED_REPOSITORY}/"
                        f"releases/download/{prepared.tag}/{item.name}"
                    )
                    release_assets.append(
                        {
                            "id": asset_id,
                            "name": item.name,
                            "size": len(contents),
                            "digest": (
                                "sha256:"
                                + hashlib.sha256(contents).hexdigest()
                            ),
                            "url": api_url,
                            "browser_download_url": browser_url,
                        }
                    )
                    downloads[api_url] = contents
                    downloads[browser_url] = contents
                simulated_release = {
                    "tag_name": prepared.tag,
                    "published_at": "2026-07-29T12:02:00Z",
                    "draft": False,
                    "prerelease": False,
                    "assets": release_assets,
                }

                def json_downloader(_url: str, _token: str | None):
                    return simulated_release

                def byte_downloader(url: str, _token: str | None) -> bytes:
                    return downloads[url]

                candidate = candidate_from_dispatch(
                    {"client_payload": dispatch_payload(prepared)},
                    json_downloader=json_downloader,
                    byte_downloader=byte_downloader,
                )
                self.assertEqual(candidate["sourceHash"], identity.source_hash)
                self.assertEqual(
                    candidate["translationVersion"], prepared.tag
                )
                self.assertEqual(candidate["gameBuildId"], identity.game_build_id)
                self.assertEqual(len(candidate["files"]), 5)

                current = root / "launcher" / "translation_manifest.json"
                current.parent.mkdir(parents=True)
                legacy = json.loads(json.dumps(candidate))
                legacy["translationVersion"] = "1.0.0"
                legacy["publishedAt"] = "2026-07-28T12:01:00Z"
                legacy.pop("sourceHash")
                legacy.pop("gameBuildId")
                for entry in legacy["files"]:
                    entry["url"] = entry["url"].replace(
                        prepared.tag, "1.0.0"
                    )
                current.write_bytes(canonical_bytes(legacy))
                result = atomic_apply_candidate(
                    current, candidate, mode="integrated-audit"
                )
                self.assertTrue(result.changed)
                persisted = parse_public_manifest(current.read_bytes())
                self.assertEqual(persisted, candidate)
                self.assertEqual(
                    hashlib.sha256(locres.read_bytes()).hexdigest(),
                    persisted["sourceHash"],
                )
                self.assertEqual(
                    json.loads(
                        prepared.launcher_manifest_path.read_text(
                            encoding="utf-8"
                        )
                    ),
                    persisted,
                )
        finally:
            sys.path.remove(str(PIPELINE_REPOSITORY))


if __name__ == "__main__":
    unittest.main()
