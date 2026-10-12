"""Content-only publication retains the existing five-file installer contract."""
import copy
import hashlib
import tempfile
import unittest
from pathlib import Path

from manifest_sync import (CONTENT_ASSET, CONTENT_RELEASE_ASSETS, MANIFEST_ASSET,
                           ContractError, atomic_apply_candidate, candidate_from_dispatch,
                           candidate_from_recovery, canonical_bytes, compare_manifest_to_release,
                           parse_public_manifest, validate_public_manifest)
from test_generate_manifest import PipelineFixture, SOURCE_HASH


class ContentReleaseTests(unittest.TestCase):
    def setUp(self):
        self.prior = PipelineFixture()
        self.new = PipelineFixture(tag="nte-auto-20260729-121100-0123456789ab",
                                   published_at="2026-07-29T12:11:00Z", asset_id_offset=100)
        self.new.release["assets"] = [a for a in self.new.release["assets"] if a["name"] in CONTENT_RELEASE_ASSETS]
        self.new.manifest["runtimeReference"] = {
            "version": 1, "tag": self.prior.tag,
            "manifestSha256": hashlib.sha256(self.prior.manifest_bytes).hexdigest()}
        self.new.manifest["files"] = [copy.deepcopy(next(f for f in self.prior.manifest["files"] if f["name"] == n["name"]))
                                       if n["name"] != CONTENT_ASSET else n for n in self.new.manifest["files"]]
        self.seal()

    def seal(self):
        raw = canonical_bytes(self.new.manifest)
        asset = next(a for a in self.new.release["assets"] if a["name"] == MANIFEST_ASSET)
        asset["size"] = len(raw)
        asset["digest"] = "sha256:" + hashlib.sha256(raw).hexdigest()
        self.new.downloads[asset["url"]] = raw
        self.new.payload["manifestSha256"] = hashlib.sha256(raw).hexdigest()

    def json(self, url, token):
        return (self.prior if url.endswith(self.prior.tag) else self.new).json(url, token)

    def bytes(self, url, token):
        return (self.prior if url in self.prior.downloads else self.new).bytes(url, token)

    def candidate(self):
        self.seal()
        return candidate_from_dispatch(self.new.event, json_downloader=self.json, byte_downloader=self.bytes)

    def test_new_dispatch_keeps_exact_five_installable_files_and_four_immutable_dependencies(self):
        candidate = self.candidate()
        self.assertEqual(candidate, self.new.manifest)
        self.assertEqual(len(candidate["files"]), 5)
        self.assertEqual(len(self.new.release["assets"]), 3)
        before = {f["name"]: f for f in self.prior.manifest["files"]}
        for f in candidate["files"]:
            if f["name"] != CONTENT_ASSET:
                self.assertEqual(f, before[f["name"]])

    def test_recovery_and_atomic_commit_preserve_reference_and_exact_replay(self):
        c = candidate_from_recovery(releases=[self.new.release, self.prior.release], json_downloader=self.json, byte_downloader=self.bytes)
        self.assertEqual(c, self.new.manifest)
        with tempfile.TemporaryDirectory() as t:
            path = Path(t) / "manifest.json"
            path.write_bytes(self.prior.manifest_bytes)
            atomic_apply_candidate(path, c, mode="recovery")
            self.assertEqual(parse_public_manifest(path.read_bytes()), c)
            atomic_apply_candidate(path, c, mode="recovery")
            self.assertEqual(parse_public_manifest(path.read_bytes()), c)

    def test_three_assets_without_explicit_reference_are_refused(self):
        self.new.manifest.pop("runtimeReference")
        self.new.manifest["files"] = copy.deepcopy(PipelineFixture(tag=self.new.tag, published_at=self.new.published_at).manifest["files"])
        with self.assertRaises(ContractError): self.candidate()

    def test_reference_digest_change_is_refused(self):
        self.new.manifest["runtimeReference"]["manifestSha256"] = "0" * 64
        with self.assertRaises(ContractError): self.candidate()

    def test_dependency_text_cannot_change_its_hash_or_size(self):
        for field, value in (("sha256", "0" * 64), ("size", 9999)):
            with self.subTest(field=field):
                original = copy.deepcopy(self.new.manifest)
                self.new.manifest["files"][0][field] = value
                with self.assertRaises(ContractError): self.candidate()
                self.new.manifest = original

    def test_dependencies_cannot_point_to_arbitrary_repository_or_new_release(self):
        old = self.new.manifest["files"][0]["url"]
        for url in (old.replace("MauricioIkeda", "untrusted"), old.replace(self.prior.tag, self.new.tag)):
            self.new.manifest["files"][0]["url"] = url
            with self.assertRaises(ContractError): validate_public_manifest(self.new.manifest)

    def test_reference_cannot_point_to_current_or_future_publication(self):
        for tag in (self.new.tag, "nte-auto-20260730-121100-0123456789ab"):
            self.new.manifest["runtimeReference"]["tag"] = tag
            with self.assertRaises(ContractError): validate_public_manifest(self.new.manifest)

    def test_unknown_reference_versions_fields_and_booleans_are_refused(self):
        for change in ({"version": 2}, {"version": True}, {"repository": "untrusted/repo"}):
            original = copy.deepcopy(self.new.manifest)
            self.new.manifest["runtimeReference"].update(change)
            with self.assertRaises(ContractError): validate_public_manifest(self.new.manifest)
            self.new.manifest = original

    def test_changed_game_build_or_host_cannot_reuse_legacy_runtime(self):
        self.new.manifest["gameBuildId"] = "different-game-build"
        self.new.payload["gameBuildId"] = "different-game-build"
        with self.assertRaises(ContractError): self.candidate()

    def test_reference_to_draft_is_refused(self):
        self.prior.release["draft"] = True
        with self.assertRaises(ContractError): self.candidate()

    def test_reference_asset_mutation_is_refused(self):
        self.prior.release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaises(ContractError): self.candidate()

    def test_dependency_release_must_be_complete_not_a_recursive_content_release(self):
        self.prior.release["assets"] = [a for a in self.prior.release["assets"] if a["name"] in CONTENT_RELEASE_ASSETS]
        with self.assertRaises(ContractError): self.candidate()

    def test_full_release_with_runtime_reference_is_refused(self):
        self.new.release["assets"] = PipelineFixture(tag=self.new.tag, published_at=self.new.published_at).release["assets"]
        with self.assertRaises(ContractError): compare_manifest_to_release(self.new.manifest, self.new.release, json_downloader=self.json, downloader=self.bytes)

    def test_content_asset_must_come_from_new_publication(self):
        f = next(f for f in self.new.manifest["files"] if f["name"] == CONTENT_ASSET)
        f["url"] = f["url"].replace(self.new.tag, self.prior.tag)
        with self.assertRaises(ContractError): validate_public_manifest(self.new.manifest)


if __name__ == "__main__": unittest.main()
