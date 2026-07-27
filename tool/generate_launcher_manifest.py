#!/usr/bin/env python3
"""Generate a deterministic static manifest for a launcher installer."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")


def build_manifest(
    *,
    version: str,
    installer: Path,
    repository: str,
    published_at: str,
    release_notes: str,
    mandatory: bool,
) -> dict:
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError(f"Invalid semantic version: {version!r}")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError(f"Invalid GitHub repository: {repository!r}")
    if not installer.is_file():
        raise FileNotFoundError(installer)
    parsed_date = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
    if parsed_date.tzinfo is None:
        raise ValueError("published_at must contain a timezone")

    contents = installer.read_bytes()
    filename = installer.name
    return {
        "schemaVersion": 1,
        "version": version,
        "publishedAt": parsed_date.astimezone(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "installer": {
            "url": (
                f"https://github.com/{repository}/releases/download/"
                f"v{version}/{filename}"
            ),
            "size": len(contents),
            "sha256": hashlib.sha256(contents).hexdigest(),
        },
        "releaseNotes": release_notes.strip(),
        "mandatory": mandatory,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--installer", required=True, type=Path)
    parser.add_argument(
        "--repository",
        default="MauricioIkeda/nte-launcher-traducao-ptbr",
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--published-at",
        default=datetime.now(timezone.utc).isoformat(),
    )
    parser.add_argument("--release-notes", default="")
    parser.add_argument("--mandatory", action="store_true")
    args = parser.parse_args()

    manifest = build_manifest(
        version=args.version,
        installer=args.installer,
        repository=args.repository,
        published_at=args.published_at,
        release_notes=args.release_notes,
        mandatory=args.mandatory,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(
        f"Launcher manifest generated for {args.version}: "
        f"{manifest['installer']['size']} bytes."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
