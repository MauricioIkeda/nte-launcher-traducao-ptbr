from __future__ import annotations

import copy
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from manifest_sync import (
    AUTHORIZED_REPOSITORY,
    BUILD_MANIFEST_ASSET,
    DESTINATIONS,
    MANIFEST_ASSET,
    MAX_MANIFEST_BYTES,
    ContractError,
    RegressionError,
    atomic_apply_candidate,
    candidate_from_dispatch,
    candidate_from_recovery,
    canonical_bytes,
    compare_candidate,
    compare_manifest_to_payload,
    compare_manifest_to_release,
    download_manifest_asset,
    parse_public_manifest,
    request_asset_sha256,
    request_bytes,
    safe_summary,
    validate_dispatch_payload,
    validate_public_manifest,
    validate_release,
)

SOURCE_HASH = "0123456789ab" + ("c" * 52)
TAG = "nte-auto-20260729-120100-0123456789ab"
PUBLISHED_AT = "2026-07-29T12:01:00Z"
VALID_HASH = "a" * 64


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class PipelineFixture:
    def __init__(
        self,
        *,
        tag: str = TAG,
        published_at: str = PUBLISHED_AT,
        source_hash: str = SOURCE_HASH,
        game_build_id: str | None = None,
        asset_id_offset: int = 0,
    ) -> None:
        self.tag = tag
        self.published_at = published_at
        self.source_hash = source_hash
        self.game_build_id = game_build_id
        self.contents = {
            name: f"small fixture for {name}".encode()
            for name in DESTINATIONS
        }
        self.manifest = {
            "schemaVersion": 1,
            "translationVersion": tag,
            "publishedAt": published_at,
            "gameBuildId": game_build_id,
            "sourceHash": source_hash,
            "files": [
                {
                    "name": name,
                    "relativeDestination": destination,
                    "url": (
                        f"https://github.com/{AUTHORIZED_REPOSITORY}/"
                        f"releases/download/{tag}/{name}"
                    ),
                    "size": len(self.contents[name]),
                    "sha256": hashlib.sha256(
                        self.contents[name]
                    ).hexdigest(),
                }
                for name, destination in DESTINATIONS.items()
            ],
        }
        self.manifest_bytes = canonical_bytes(self.manifest)
        self.build_manifest = {
            "schemaVersion": 2,
            "source": {
                "sourceHash": source_hash,
                "sourceLocresSha256": source_hash,
                "sourceEntryCount": 5,
            },
            "translation": {
                "total": 5,
                "validated": 5,
                "pending": 0,
                "invalid": 0,
            },
            "files": [
                {
                    "name": name,
                    "size": len(contents),
                    "sha256": hashlib.sha256(contents).hexdigest(),
                }
                for name, contents in self.contents.items()
            ],
        }
        self.build_bytes = canonical_bytes(self.build_manifest)
        release_contents = {
            **self.contents,
            MANIFEST_ASSET: self.manifest_bytes,
            BUILD_MANIFEST_ASSET: self.build_bytes,
        }
        self.release = {
            "tag_name": tag,
            "published_at": "2026-07-29T12:02:00Z",
            "draft": False,
            "prerelease": False,
            "assets": [],
        }
        self.downloads: dict[str, bytes] = {}
        for asset_id, (name, contents) in enumerate(
            release_contents.items(), start=asset_id_offset + 1
        ):
            api_url = (
                f"https://api.github.com/repos/{AUTHORIZED_REPOSITORY}/"
                f"releases/assets/{asset_id}"
            )
            browser_url = (
                f"https://github.com/{AUTHORIZED_REPOSITORY}/"
                f"releases/download/{tag}/{name}"
            )
            self.release["assets"].append(
                {
                    "id": asset_id,
                    "name": name,
                    "size": len(contents),
                    "digest": f"sha256:{hashlib.sha256(contents).hexdigest()}",
                    "url": api_url,
                    "browser_download_url": browser_url,
                }
            )
            self.downloads[api_url] = contents
            self.downloads[browser_url] = contents
        self.payload = {
            "repository": AUTHORIZED_REPOSITORY,
            "tag": tag,
            "manifestAsset": MANIFEST_ASSET,
            "manifestSha256": hashlib.sha256(
                self.manifest_bytes
            ).hexdigest(),
            "publishedAt": published_at,
            "gameBuildId": game_build_id,
            "sourceHash": source_hash,
        }
        self.event = {"client_payload": self.payload}

    def bytes(self, url: str, _token: str | None) -> bytes:
        if url not in self.downloads:
            raise AssertionError(f"unexpected byte request: {url}")
        return self.downloads[url]

    def json(self, url: str, _token: str | None):
        expected = (
            f"https://api.github.com/repos/{AUTHORIZED_REPOSITORY}/"
            f"releases/tags/{self.tag}"
        )
        if url != expected:
            raise AssertionError(f"unexpected JSON request: {url}")
        return self.release


class PayloadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = PipelineFixture()

    def test_valid_payload_and_null_build_are_accepted(self):
        result = validate_dispatch_payload(self.fixture.payload)
        self.assertEqual(result["tag"], TAG)
        self.assertIsNone(result["gameBuildId"])

    def test_hash_is_normalized(self):
        self.fixture.payload["manifestSha256"] = (
            self.fixture.payload["manifestSha256"].upper()
        )
        self.assertTrue(
            validate_dispatch_payload(self.fixture.payload)[
                "manifestSha256"
            ].islower()
        )

    def test_repository_is_pinned(self):
        self.fixture.payload["repository"] = "attacker/repository"
        with self.assertRaisesRegex(ContractError, "não autorizado"):
            validate_dispatch_payload(self.fixture.payload)

    def test_invalid_tags_are_rejected(self):
        invalid = (
            "",
            "tools-ueextractor-1",
            "nte-auto-20260729-120100-xyz",
            "nte-auto-20260729-120100-0123456789ab;echo pwn",
            "nte-auto-20260729-120100-0123456789ab\nbad",
        )
        for tag in invalid:
            with self.subTest(tag=tag):
                self.fixture.payload["tag"] = tag
                with self.assertRaises(ContractError):
                    validate_dispatch_payload(self.fixture.payload)
                self.fixture.payload["tag"] = TAG

    def test_manifest_asset_is_exact(self):
        for value in ("other.json", "../translation_manifest.json", "x/y"):
            with self.subTest(value=value):
                self.fixture.payload["manifestAsset"] = value
                with self.assertRaises(ContractError):
                    validate_dispatch_payload(self.fixture.payload)

    def test_invalid_hash_and_non_utc_date_are_rejected(self):
        self.fixture.payload["manifestSha256"] = "xyz"
        with self.assertRaisesRegex(ContractError, "SHA-256"):
            validate_dispatch_payload(self.fixture.payload)
        self.fixture = PipelineFixture()
        self.fixture.payload["publishedAt"] = "2026-07-29T12:01:00+00:00"
        with self.assertRaisesRegex(ContractError, "UTC"):
            validate_dispatch_payload(self.fixture.payload)

    def test_source_hash_must_match_tag(self):
        self.fixture.payload["sourceHash"] = "f" * 64
        with self.assertRaisesRegex(ContractError, "prefixo"):
            validate_dispatch_payload(self.fixture.payload)

    def test_tag_timestamp_must_match_published_at(self):
        self.fixture.payload["publishedAt"] = "2026-07-29T12:01:01Z"
        with self.assertRaisesRegex(ContractError, "horário"):
            validate_dispatch_payload(self.fixture.payload)

    def test_empty_or_unsafe_build_is_rejected(self):
        for value in ("", " ", "build\ninjection", "x" * 201):
            with self.subTest(value=value[:20]):
                self.fixture.payload["gameBuildId"] = value
                with self.assertRaises(ContractError):
                    validate_dispatch_payload(self.fixture.payload)

    def test_payload_types_are_strict(self):
        cases = {
            "repository": None,
            "tag": 123,
            "manifestAsset": True,
            "publishedAt": [],
            "sourceHash": {},
        }
        for field, value in cases.items():
            with self.subTest(field=field):
                fixture = PipelineFixture()
                fixture.payload[field] = value
                with self.assertRaises(ContractError):
                    validate_dispatch_payload(fixture.payload)


class ReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = PipelineFixture()

    def test_valid_release_with_exact_tag_is_accepted(self):
        release, assets = validate_release(
            self.fixture.release, expected_tag=TAG
        )
        self.assertEqual(release["tag_name"], TAG)
        self.assertEqual(len(assets), 7)

    def test_absent_release_is_reported_by_dispatch(self):
        def missing(_url, _token):
            raise RuntimeError("404")

        with self.assertRaisesRegex(ContractError, "não foi encontrada"):
            candidate_from_dispatch(
                self.fixture.event,
                json_downloader=missing,
                byte_downloader=self.fixture.bytes,
            )

    def test_draft_and_prerelease_are_rejected(self):
        for field in ("draft", "prerelease"):
            with self.subTest(field=field):
                release = copy.deepcopy(self.fixture.release)
                release[field] = True
                with self.assertRaises(ContractError):
                    validate_release(release)

    def test_duplicate_assets_case_insensitively_are_rejected(self):
        release = copy.deepcopy(self.fixture.release)
        duplicate = copy.deepcopy(release["assets"][0])
        duplicate["name"] = duplicate["name"].upper()
        duplicate["id"] = 99
        duplicate["url"] = (
            f"https://api.github.com/repos/{AUTHORIZED_REPOSITORY}/"
            "releases/assets/99"
        )
        release["assets"].append(duplicate)
        with self.assertRaisesRegex(ContractError, "duplicado"):
            validate_release(release)

    def test_missing_manifest_and_duplicate_manifest_are_rejected(self):
        missing = copy.deepcopy(self.fixture.release)
        missing["assets"] = [
            item for item in missing["assets"] if item["name"] != MANIFEST_ASSET
        ]
        with self.assertRaisesRegex(ContractError, "ausentes"):
            validate_release(missing)
        duplicate = copy.deepcopy(self.fixture.release)
        extra = copy.deepcopy(
            next(
                item
                for item in duplicate["assets"]
                if item["name"] == MANIFEST_ASSET
            )
        )
        extra["name"] = MANIFEST_ASSET.upper()
        extra["id"] = 88
        extra["url"] = (
            f"https://api.github.com/repos/{AUTHORIZED_REPOSITORY}/"
            "releases/assets/88"
        )
        duplicate["assets"].append(extra)
        with self.assertRaisesRegex(ContractError, "duplicado"):
            validate_release(duplicate)

    def test_unexpected_asset_is_rejected(self):
        release = copy.deepcopy(self.fixture.release)
        release["assets"][-1]["name"] = "unexpected.exe"
        with self.assertRaisesRegex(ContractError, "divergente"):
            validate_release(release)

    def test_tool_release_is_ignored_in_recovery(self):
        tool = copy.deepcopy(self.fixture.release)
        tool["tag_name"] = "tools-ueextractor-1.0.0"
        candidate = candidate_from_recovery(
            releases=[tool, self.fixture.release],
            byte_downloader=self.fixture.bytes,
        )
        self.assertEqual(candidate["translationVersion"], TAG)

    def test_api_asset_url_is_pinned(self):
        release = copy.deepcopy(self.fixture.release)
        release["assets"][0]["url"] = "https://evil.example/asset"
        with self.assertRaisesRegex(ContractError, "não autorizada"):
            validate_release(release)


class ManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = PipelineFixture()

    def test_schema_one_contract_is_accepted(self):
        parsed = parse_public_manifest(self.fixture.manifest_bytes)
        self.assertEqual(parsed["sourceHash"], SOURCE_HASH)
        self.assertNotIn("source", parsed)

    def test_wrong_schema_invalid_json_and_oversize_are_rejected(self):
        invalid_schema = copy.deepcopy(self.fixture.manifest)
        invalid_schema["schemaVersion"] = 2
        with self.assertRaises(ContractError):
            validate_public_manifest(invalid_schema)
        with self.assertRaisesRegex(ContractError, "JSON"):
            parse_public_manifest(b"{broken")
        with self.assertRaisesRegex(ContractError, "limite"):
            parse_public_manifest(b"x" * (MAX_MANIFEST_BYTES + 1))

    def test_http_reader_rejects_response_above_explicit_limit(self):
        with patch(
            "manifest_sync.urllib.request.urlopen",
            return_value=FakeResponse(b"x" * 9),
        ):
            with self.assertRaisesRegex(ContractError, "mais de 8 bytes"):
                request_bytes("https://api.github.com/test", max_bytes=8)

    def test_fallback_asset_hash_is_streamed_and_size_bounded(self):
        contents = b"streamed fixture"
        with patch(
            "manifest_sync.urllib.request.urlopen",
            return_value=FakeResponse(contents),
        ):
            self.assertEqual(
                request_asset_sha256(
                    "https://github.com/test", len(contents)
                ),
                hashlib.sha256(contents).hexdigest(),
            )
        with patch(
            "manifest_sync.urllib.request.urlopen",
            return_value=FakeResponse(contents + b"!"),
        ):
            with self.assertRaisesRegex(ContractError, "excedeu"):
                request_asset_sha256(
                    "https://github.com/test", len(contents)
                )

    def test_missing_fields_and_wrong_types_are_rejected(self):
        for field in (
            "schemaVersion",
            "translationVersion",
            "publishedAt",
            "sourceHash",
            "files",
        ):
            with self.subTest(field=field):
                manifest = copy.deepcopy(self.fixture.manifest)
                del manifest[field]
                with self.assertRaises(ContractError):
                    validate_public_manifest(manifest)
        manifest = copy.deepcopy(self.fixture.manifest)
        manifest["schemaVersion"] = True
        with self.assertRaises(ContractError):
            validate_public_manifest(manifest)
        manifest = copy.deepcopy(self.fixture.manifest)
        manifest["files"][0]["size"] = True
        with self.assertRaises(ContractError):
            validate_public_manifest(manifest)

    def test_duplicate_name_and_destination_are_rejected(self):
        duplicate_name = copy.deepcopy(self.fixture.manifest)
        duplicate_name["files"][1]["name"] = duplicate_name["files"][0][
            "name"
        ].upper()
        with self.assertRaisesRegex(ContractError, "duplicado"):
            validate_public_manifest(duplicate_name)
        duplicate_destination = copy.deepcopy(self.fixture.manifest)
        duplicate_destination["files"][1]["relativeDestination"] = (
            duplicate_destination["files"][0]["relativeDestination"].upper()
        )
        with self.assertRaises(ContractError):
            validate_public_manifest(duplicate_destination)

    def test_invalid_hash_size_http_host_and_destination_are_rejected(self):
        mutations = (
            ("sha256", "bad"),
            ("size", 0),
            (
                "url",
                self.fixture.manifest["files"][0]["url"].replace(
                    "https://", "http://"
                ),
            ),
            (
                "url",
                self.fixture.manifest["files"][0]["url"].replace(
                    "github.com", "evil.example"
                ),
            ),
            ("relativeDestination", "../outside.dll"),
        )
        for field, value in mutations:
            with self.subTest(field=field, value=value):
                manifest = copy.deepcopy(self.fixture.manifest)
                manifest["files"][0][field] = value
                with self.assertRaises(ContractError):
                    validate_public_manifest(manifest)

    def test_url_cannot_point_to_other_tag_or_repository(self):
        for replacement in (
            ("releases/download/", "releases/download/other/"),
            (AUTHORIZED_REPOSITORY, "other/repository"),
        ):
            manifest = copy.deepcopy(self.fixture.manifest)
            manifest["files"][0]["url"] = manifest["files"][0]["url"].replace(
                *replacement
            )
            with self.assertRaisesRegex(ContractError, "inesperado"):
                validate_public_manifest(manifest)

    def test_nested_source_cannot_replace_top_level_source_hash(self):
        manifest = copy.deepcopy(self.fixture.manifest)
        manifest["source"] = {"sourceHash": manifest.pop("sourceHash")}
        with self.assertRaisesRegex(ContractError, "source"):
            validate_public_manifest(manifest)

    def test_only_exact_five_installable_files_are_accepted(self):
        missing = copy.deepcopy(self.fixture.manifest)
        missing["files"].pop()
        with self.assertRaisesRegex(ContractError, "cinco"):
            validate_public_manifest(missing)
        extra = copy.deepcopy(self.fixture.manifest)
        extra["files"].append(copy.deepcopy(extra["files"][0]))
        with self.assertRaisesRegex(ContractError, "cinco"):
            validate_public_manifest(extra)


class PayloadManifestComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = PipelineFixture(game_build_id="NTE-build-42")

    def test_exact_payload_match_is_accepted(self):
        compare_manifest_to_payload(
            self.fixture.manifest, self.fixture.payload
        )

    def test_tag_date_source_and_build_divergence_are_rejected(self):
        cases = {
            "translationVersion": "nte-auto-20260729-120101-0123456789ab",
            "publishedAt": "2026-07-29T12:01:01Z",
            "sourceHash": "f" * 64,
            "gameBuildId": "other-build",
        }
        for field, value in cases.items():
            with self.subTest(field=field):
                manifest = copy.deepcopy(self.fixture.manifest)
                manifest[field] = value
                with self.assertRaisesRegex(ContractError, "payload"):
                    compare_manifest_to_payload(
                        manifest, self.fixture.payload
                    )

    def test_raw_manifest_hash_divergence_fails_before_parse(self):
        with self.assertRaisesRegex(ContractError, "SHA-256 bruto"):
            download_manifest_asset(
                self.fixture.release,
                expected_sha256="f" * 64,
                downloader=self.fixture.bytes,
            )

    def test_remote_manifest_digest_divergence_fails(self):
        release = copy.deepcopy(self.fixture.release)
        manifest_asset = next(
            item for item in release["assets"] if item["name"] == MANIFEST_ASSET
        )
        manifest_asset["digest"] = "sha256:" + ("f" * 64)
        with self.assertRaisesRegex(ContractError, "digest remoto"):
            download_manifest_asset(
                release,
                expected_sha256=self.fixture.payload["manifestSha256"],
                downloader=self.fixture.bytes,
            )


class AssetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = PipelineFixture()

    def test_all_assets_match_release(self):
        compare_manifest_to_release(
            self.fixture.manifest,
            self.fixture.release,
            downloader=self.fixture.bytes,
        )

    def test_missing_asset_and_size_divergence_fail(self):
        missing = copy.deepcopy(self.fixture.release)
        missing["assets"].pop(0)
        with self.assertRaises(ContractError):
            compare_manifest_to_release(
                self.fixture.manifest, missing, downloader=self.fixture.bytes
            )
        size = copy.deepcopy(self.fixture.release)
        size["assets"][0]["size"] += 1
        with self.assertRaisesRegex(ContractError, "divergem"):
            compare_manifest_to_release(
                self.fixture.manifest, size, downloader=self.fixture.bytes
            )

    def test_remote_digest_divergence_fails(self):
        release = copy.deepcopy(self.fixture.release)
        release["assets"][0]["digest"] = "sha256:" + ("f" * 64)
        with self.assertRaisesRegex(ContractError, "divergem"):
            compare_manifest_to_release(
                self.fixture.manifest,
                release,
                downloader=self.fixture.bytes,
            )

    def test_missing_digest_downloads_and_validates(self):
        release = copy.deepcopy(self.fixture.release)
        release["assets"][0]["digest"] = None
        compare_manifest_to_release(
            self.fixture.manifest, release, downloader=self.fixture.bytes
        )

    def test_download_hash_divergence_fails(self):
        release = copy.deepcopy(self.fixture.release)
        asset = release["assets"][0]
        asset["digest"] = None

        def corrupted(url: str, token: str | None) -> bytes:
            contents = self.fixture.bytes(url, token)
            if url == asset["browser_download_url"]:
                return b"x" * len(contents)
            return contents

        with self.assertRaisesRegex(ContractError, "divergem"):
            compare_manifest_to_release(
                self.fixture.manifest, release, downloader=corrupted
            )


class UpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = PipelineFixture()

    def older(self) -> dict:
        fixture = PipelineFixture(
            tag="nte-auto-20260728-120100-aaaaaaaaaaaa",
            published_at="2026-07-28T12:01:00Z",
            source_hash="a" * 64,
        )
        return fixture.manifest

    def newer(self) -> dict:
        fixture = PipelineFixture(
            tag="nte-auto-20260730-120100-bbbbbbbbbbbb",
            published_at="2026-07-30T12:01:00Z",
            source_hash="b" * 64,
        )
        return fixture.manifest

    def test_newer_updates_atomically(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "manifest.json"
            output.write_bytes(canonical_bytes(self.older()))
            result = atomic_apply_candidate(
                output, self.fixture.manifest, mode="dispatch"
            )
            self.assertTrue(result.changed)
            self.assertEqual(
                parse_public_manifest(output.read_bytes())[
                    "translationVersion"
                ],
                TAG,
            )
            self.assertFalse(Path(str(output) + ".nte-new").exists())

    def test_equal_identical_is_idempotent(self):
        self.assertEqual(
            compare_candidate(self.fixture.manifest, self.fixture.manifest),
            "already-current",
        )

    def test_same_version_different_content_fails(self):
        changed = copy.deepcopy(self.fixture.manifest)
        changed["files"][0]["sha256"] = "f" * 64
        with self.assertRaisesRegex(RegressionError, "imutabilidade"):
            compare_candidate(self.fixture.manifest, changed)

    def test_older_and_equal_date_different_version_are_blocked(self):
        with self.assertRaisesRegex(RegressionError, "downgrade"):
            compare_candidate(self.fixture.manifest, self.older())
        equal_date = copy.deepcopy(self.fixture.manifest)
        equal_date["translationVersion"] = (
            "nte-auto-20260729-120100-ffffffffffff"
        )
        equal_date["sourceHash"] = "f" * 64
        with self.assertRaisesRegex(RegressionError, "datas iguais"):
            compare_candidate(self.fixture.manifest, equal_date)

    def test_invalid_current_is_diagnostic_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "manifest.json"
            output.write_text("{invalid", encoding="utf-8")
            with self.assertRaisesRegex(ContractError, "JSON"):
                atomic_apply_candidate(
                    output, self.fixture.manifest, mode="dispatch"
                )
            self.assertEqual(output.read_text(encoding="utf-8"), "{invalid")

    def test_recovery_selects_newest_valid_release(self):
        older_fixture = PipelineFixture(
            tag="nte-auto-20260728-120100-aaaaaaaaaaaa",
            published_at="2026-07-28T12:01:00Z",
            source_hash="a" * 64,
            asset_id_offset=100,
        )
        downloads = {**older_fixture.downloads, **self.fixture.downloads}

        def bytes_for(url: str, _token: str | None) -> bytes:
            return downloads[url]

        candidate = candidate_from_recovery(
            releases=[older_fixture.release, self.fixture.release],
            byte_downloader=bytes_for,
        )
        self.assertEqual(candidate["translationVersion"], TAG)

    def test_recovery_ignores_invalid_draft_tool_and_does_not_regress(self):
        invalid = copy.deepcopy(self.fixture.release)
        invalid["assets"][0]["size"] = 0
        draft = copy.deepcopy(self.fixture.release)
        draft["draft"] = True
        tool = copy.deepcopy(self.fixture.release)
        tool["tag_name"] = "tools-ueextractor-1"
        self.assertIsNone(
            candidate_from_recovery(
                releases=[invalid, draft, tool],
                byte_downloader=self.fixture.bytes,
            )
        )
        with self.assertRaises(RegressionError):
            compare_candidate(self.fixture.manifest, self.older())

    def test_old_execution_cannot_overwrite_new_branch_state(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "manifest.json"
            output.write_bytes(canonical_bytes(self.newer()))
            with self.assertRaisesRegex(RegressionError, "downgrade"):
                atomic_apply_candidate(
                    output, self.fixture.manifest, mode="revalidation"
                )
            self.assertEqual(
                parse_public_manifest(output.read_bytes())[
                    "translationVersion"
                ],
                self.newer()["translationVersion"],
            )


class ContractIntegrationTests(unittest.TestCase):
    def test_complete_dispatch_cron_idempotency_and_downgrade_flow(self):
        fixture = PipelineFixture(game_build_id="build-fixture")
        candidate = candidate_from_dispatch(
            fixture.event,
            json_downloader=fixture.json,
            byte_downloader=fixture.bytes,
        )
        self.assertEqual(candidate, validate_public_manifest(fixture.manifest))
        recovery = candidate_from_recovery(
            releases=[fixture.release],
            byte_downloader=fixture.bytes,
        )
        self.assertEqual(recovery, candidate)
        self.assertEqual(
            compare_candidate(candidate, recovery), "already-current"
        )
        older = PipelineFixture(
            tag="nte-auto-20260728-120100-aaaaaaaaaaaa",
            published_at="2026-07-28T12:01:00Z",
            source_hash="a" * 64,
        )
        with self.assertRaises(RegressionError):
            compare_candidate(candidate, older.manifest)
        tool = copy.deepcopy(fixture.release)
        tool["tag_name"] = "tools-ueextractor-1.0.8"
        selected = candidate_from_recovery(
            releases=[tool, fixture.release],
            byte_downloader=fixture.bytes,
        )
        self.assertEqual(selected, candidate)

    def test_summary_is_safe_and_contains_no_token(self):
        fixture = PipelineFixture()
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "manifest.json"
            older = PipelineFixture(
                tag="nte-auto-20260728-120100-aaaaaaaaaaaa",
                published_at="2026-07-28T12:01:00Z",
                source_hash="a" * 64,
            )
            output.write_bytes(canonical_bytes(older.manifest))
            result = atomic_apply_candidate(
                output, fixture.manifest, mode="dispatch"
            )
        summary = safe_summary(result)
        self.assertIn("dispatch", summary)
        self.assertIn(SOURCE_HASH[:12], summary)
        self.assertNotIn("GH_TOKEN", summary)
        self.assertNotIn("github_pat_", summary)


if __name__ == "__main__":
    unittest.main()
