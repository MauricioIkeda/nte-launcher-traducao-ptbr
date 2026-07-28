#!/usr/bin/env python3
"""Generate the launcher manifest from the latest public translation release."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable

API_VERSION = "2022-11-28"
USER_AGENT = "NTE-Launcher-Traducao-PTBR-Manifest-Updater/1.0"
SHA256_PATTERN = re.compile(r"^[a-f0-9]{64}$")

DESTINATIONS = {
    "UniversalSigBypasser.asi": (
        "Client/WindowsNoEditor/HT/Binaries/Win64/"
        "UniversalSigBypasser.asi"
    ),
    "version.dll": (
        "Client/WindowsNoEditor/HT/Binaries/Win64/version.dll"
    ),
    "pakchunk999-Windows_999_P.utoc": (
        "Client/WindowsNoEditor/HT/Content/Paks/"
        "pakchunk999-Windows_999_P.utoc"
    ),
    "pakchunk999-Windows_999_P.pak": (
        "Client/WindowsNoEditor/HT/Content/Paks/"
        "pakchunk999-Windows_999_P.pak"
    ),
    "pakchunk999-Windows_999_P.ucas": (
        "Client/WindowsNoEditor/HT/Content/Paks/"
        "pakchunk999-Windows_999_P.ucas"
    ),
}


def request_bytes(url: str, token: str | None = None) -> bytes:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"GitHub returned HTTP {error.code} for {url}: {body[:500]}"
        ) from error


def fetch_latest_release(repository: str, token: str | None) -> dict[str, Any]:
    url = f"https://api.github.com/repos/{repository}/releases/latest"
    return json.loads(request_bytes(url, token))


def sha256_for_asset(
    url: str,
    expected_size: int,
    downloader: Callable[[str, str | None], bytes],
) -> str:
    contents = downloader(url, None)
    if len(contents) != expected_size:
        raise ValueError(
            f"Downloaded asset has {len(contents)} bytes; "
            f"expected {expected_size}."
        )
    return hashlib.sha256(contents).hexdigest()


def build_manifest(
    release: dict[str, Any],
    repository: str,
    downloader: Callable[[str, str | None], bytes] = request_bytes,
) -> dict[str, Any]:
    tag = str(release.get("tag_name", "")).strip()
    published_at = str(release.get("published_at", "")).strip()
    if not tag or not re.fullmatch(r"[A-Za-z0-9._-]+", tag):
        raise ValueError(f"Unsafe or missing release tag: {tag!r}")
    if not published_at:
        raise ValueError("Release does not contain published_at.")

    assets = {
        str(asset.get("name")): asset
        for asset in release.get("assets", [])
        if isinstance(asset, dict)
    }
    missing = sorted(set(DESTINATIONS) - set(assets))
    if missing:
        raise ValueError(f"Release {tag} is missing assets: {', '.join(missing)}")

    manifest_files: list[dict[str, Any]] = []
    expected_prefix = (
        f"https://github.com/{repository}/releases/download/{tag}/"
    )
    for name, destination in DESTINATIONS.items():
        asset = assets[name]
        size = int(asset.get("size", 0))
        url = str(asset.get("browser_download_url", ""))
        if size <= 0:
            raise ValueError(f"Invalid size for {name}: {size}")
        if not url.startswith(expected_prefix) or not url.endswith(f"/{name}"):
            raise ValueError(f"Unexpected download URL for {name}: {url}")

        digest_value = asset.get("digest")
        digest = ""
        if isinstance(digest_value, str) and digest_value.startswith("sha256:"):
            digest = digest_value.removeprefix("sha256:").lower()
        if not SHA256_PATTERN.fullmatch(digest):
            print(
                f"No valid GitHub digest for {name}; downloading to hash it.",
                file=sys.stderr,
            )
            digest = sha256_for_asset(url, size, downloader)

        manifest_files.append(
            {
                "name": name,
                "relativeDestination": destination,
                "url": url,
                "size": size,
                "sha256": digest,
            }
        )

    return {
        "schemaVersion": 1,
        "translationVersion": tag,
        "publishedAt": published_at,
        "files": manifest_files,
    }


def write_if_changed(output: Path, manifest: dict[str, Any]) -> bool:
    serialized = json.dumps(
        manifest,
        ensure_ascii=False,
        indent=2,
    ) + "\n"
    if output.exists() and output.read_text(encoding="utf-8") == serialized:
        return False
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(serialized, encoding="utf-8", newline="\n")
    return True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repository",
        default="MauricioIkeda/nte-ptbr-releases",
        help="Public GitHub repository containing the translation releases.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/manifest/translation_manifest.json"),
    )
    parser.add_argument(
        "--release-json",
        type=Path,
        help="Use a local release response instead of calling GitHub.",
    )
    parser.add_argument(
        "--allow-missing-release",
        action="store_true",
        help="Exit successfully when the repository has no release yet.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.release_json:
        release = json.loads(args.release_json.read_text(encoding="utf-8"))
    else:
        try:
            release = fetch_latest_release(
                args.repository,
                os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"),
            )
        except Exception as error:
            if args.allow_missing_release and "404" in str(error):
                print("No translation release is available yet.")
                return 0
            raise

    manifest = build_manifest(release, args.repository)
    changed = write_if_changed(args.output, manifest)
    state = "updated" if changed else "already current"
    print(
        f"Manifest {state}: version {manifest['translationVersion']} "
        f"with {len(manifest['files'])} files."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
