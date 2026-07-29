#!/usr/bin/env python3
"""Safely synchronize the launcher manifest with a translation release."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

from manifest_sync import (
    ContractError,
    RegressionError,
    SyncResult,
    atomic_apply_candidate,
    candidate_from_dispatch,
    candidate_from_recovery,
    load_current_manifest,
    no_release_result,
    parse_public_manifest,
    safe_summary,
    validate_public_manifest,
    write_json_atomic,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        choices=("dispatch", "recovery", "apply-candidate", "verify"),
        required=True,
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/manifest/translation_manifest.json"),
    )
    parser.add_argument(
        "--event-file",
        type=Path,
        help="GitHub event JSON; required in dispatch mode.",
    )
    parser.add_argument(
        "--candidate",
        type=Path,
        help="Validated candidate JSON; required in apply-candidate mode.",
    )
    parser.add_argument("--result", type=Path)
    parser.add_argument("--summary", type=Path)
    return parser.parse_args()


def _read_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError(f"{label}: JSON inválido em {path}.") from error


def run(args: argparse.Namespace) -> SyncResult:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if args.mode == "dispatch":
        if args.event_file is None:
            raise ContractError("dispatch: --event-file é obrigatório.")
        candidate = candidate_from_dispatch(
            _read_json(args.event_file, "evento"), token=token
        )
        return atomic_apply_candidate(args.output, candidate, mode="dispatch")
    if args.mode == "recovery":
        candidate = candidate_from_recovery(token=token)
        if candidate is None:
            return no_release_result(args.output)
        return atomic_apply_candidate(args.output, candidate, mode="recovery")
    if args.mode == "apply-candidate":
        if args.candidate is None:
            raise ContractError(
                "apply-candidate: --candidate é obrigatório."
            )
        candidate = validate_public_manifest(
            _read_json(args.candidate, "candidato")
        )
        return atomic_apply_candidate(
            args.output, candidate, mode="revalidation"
        )
    parse_public_manifest(args.output.read_bytes())
    current = load_current_manifest(args.output)
    return SyncResult(
        mode="verify",
        repository="MauricioIkeda/nte-ptbr-releases",
        tag=str(current["translationVersion"]),
        published_at=str(current["publishedAt"]),
        source_hash=current.get("sourceHash"),
        game_build_id=current.get("gameBuildId"),
        file_count=len(current["files"]),
        previous_version=str(current["translationVersion"]),
        decision="valid",
        changed=False,
    )


def main() -> int:
    args = parse_args()
    try:
        result = run(args)
        if args.result is not None:
            write_json_atomic(args.result, result.to_dict())
        if args.summary is not None:
            args.summary.parent.mkdir(parents=True, exist_ok=True)
            args.summary.write_text(
                safe_summary(result), encoding="utf-8", newline="\n"
            )
        print(
            f"Manifest sync: mode={result.mode} decision={result.decision} "
            f"tag={result.tag or '-'}"
        )
        return 0
    except ContractError as error:
        print(f"Manifest sync failed: {error}", file=sys.stderr)
        if args.summary is not None:
            safe_error = str(error).replace("`", "'")
            decision = (
                "downgrade bloqueado"
                if isinstance(error, RegressionError)
                else "inválido"
            )
            args.summary.parent.mkdir(parents=True, exist_ok=True)
            args.summary.write_text(
                "## Sincronização do manifesto de tradução\n\n"
                f"- Modo: `{args.mode}`\n"
                f"- Decisão: **{decision}**\n"
                f"- Motivo: `{safe_error}`\n",
                encoding="utf-8",
                newline="\n",
            )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
