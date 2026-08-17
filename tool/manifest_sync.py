"""Secure synchronization contract for NTE translation manifests."""

from __future__ import annotations

import hashlib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping

AUTHORIZED_REPOSITORY = "MauricioIkeda/nte-ptbr-releases"
MANIFEST_ASSET = "translation_manifest.json"
BUILD_MANIFEST_ASSET = "build-manifest.json"
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_API_RESPONSE_BYTES = 16 * 1024 * 1024
MAX_FALLBACK_ASSET_BYTES = 2 * 1024 * 1024 * 1024
MAX_GAME_BUILD_ID = 200
MAX_RELEASES = 300
API_VERSION = "2022-11-28"
USER_AGENT = "NTE-Launcher-Traducao-PTBR-Manifest-Updater/2.0"

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
TAG_PATTERN = re.compile(
    r"^nte-auto-(\d{8})-(\d{6})-([0-9a-f]{12})$"
)
UTC_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"
)
CONTROL_PATTERN = re.compile(r"[\x00-\x1f\x7f]")

DESTINATIONS = {
    "UniversalSigBypasser.asi": (
        "Client/WindowsNoEditor/HT/Binaries/Win64/"
        "UniversalSigBypasser.asi"
    ),
    "version.dll": (
        "Client/WindowsNoEditor/HT/Binaries/Win64/version.dll"
    ),
    "pakchunk999-Windows_999_P.pak": (
        "Client/WindowsNoEditor/HT/Content/Paks/"
        "pakchunk999-Windows_999_P.pak"
    ),
    "pakchunk999-Windows_999_P.utoc": (
        "Client/WindowsNoEditor/HT/Content/Paks/"
        "pakchunk999-Windows_999_P.utoc"
    ),
    "pakchunk999-Windows_999_P.ucas": (
        "Client/WindowsNoEditor/HT/Content/Paks/"
        "pakchunk999-Windows_999_P.ucas"
    ),
}
RELEASE_ASSETS = frozenset(
    (*DESTINATIONS, BUILD_MANIFEST_ASSET, MANIFEST_ASSET)
)

ByteDownloader = Callable[[str, str | None], bytes]
JsonDownloader = Callable[[str, str | None], Any]


class ContractError(ValueError):
    """The remote publication does not satisfy the trusted contract."""


class RegressionError(ContractError):
    """The candidate would violate manifest monotonicity."""


@dataclass(frozen=True)
class SyncResult:
    mode: str
    repository: str
    tag: str | None
    published_at: str | None
    source_hash: str | None
    game_build_id: str | None
    file_count: int
    previous_version: str | None
    decision: str
    changed: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "mode": self.mode,
            "repository": self.repository,
            "tag": self.tag,
            "publishedAt": self.published_at,
            "sourceHash": self.source_hash,
            "gameBuildId": self.game_build_id,
            "fileCount": self.file_count,
            "previousVersion": self.previous_version,
            "decision": self.decision,
            "changed": self.changed,
        }


def _require_object(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{label}: era esperado um objeto JSON.")
    return value


def _require_string(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise ContractError(f"{label}: era esperada uma string.")
    if not value or value != value.strip() or CONTROL_PATTERN.search(value):
        raise ContractError(f"{label}: string vazia ou insegura.")
    return value


def _require_int(value: Any, label: str) -> int:
    if type(value) is not int:
        raise ContractError(f"{label}: era esperado um número inteiro.")
    return value


def normalize_sha256(value: Any, label: str) -> str:
    text = _require_string(value, label).lower()
    if not SHA256_PATTERN.fullmatch(text):
        raise ContractError(f"{label}: SHA-256 inválido.")
    return text


def parse_utc(value: Any, label: str) -> datetime:
    text = _require_string(value, label)
    if not UTC_PATTERN.fullmatch(text):
        raise ContractError(f"{label}: data UTC inválida; use sufixo Z.")
    try:
        parsed = datetime.fromisoformat(text[:-1] + "+00:00")
    except ValueError as error:
        raise ContractError(f"{label}: data UTC inválida.") from error
    return parsed.astimezone(timezone.utc)


def validate_tag(value: Any) -> str:
    tag = _require_string(value, "tag")
    if len(tag) > 64 or TAG_PATTERN.fullmatch(tag) is None:
        raise ContractError(
            "tag: esperado nte-auto-YYYYMMDD-HHMMSS-<12 hex>."
        )
    return tag


def _validate_tag_timestamp(tag: str, published_at: str) -> None:
    match = TAG_PATTERN.fullmatch(tag)
    assert match is not None
    embedded = datetime.strptime(
        match.group(1) + match.group(2), "%Y%m%d%H%M%S"
    ).replace(tzinfo=timezone.utc)
    published = parse_utc(published_at, "publishedAt")
    if embedded != published.replace(microsecond=0):
        raise ContractError(
            "tag: data e horário não correspondem a publishedAt."
        )


def validate_game_build_id(value: Any) -> str | None:
    if value is None:
        return None
    text = _require_string(value, "gameBuildId")
    if len(text) > MAX_GAME_BUILD_ID:
        raise ContractError("gameBuildId: limite de tamanho excedido.")
    return text


def validate_localization(value: Any) -> dict[str, Any]:
    data = _require_object(value, "localization")
    expected_fields = {
        "sourceCulture",
        "installationCulture",
        "targetLanguage",
        "hostCompatible",
        "hostLocresSha256",
    }
    if set(data) != expected_fields:
        raise ContractError("localization: campos inesperados ou ausentes.")
    source = _require_string(data.get("sourceCulture"), "localization.sourceCulture")
    installation = _require_string(
        data.get("installationCulture"), "localization.installationCulture"
    )
    target = _require_string(data.get("targetLanguage"), "localization.targetLanguage")
    if source != "en" or installation != "fr" or target != "pt-BR":
        raise ContractError("localization: contrato de culturas não autorizado.")
    if data.get("hostCompatible") is not True:
        raise ContractError("localization.hostCompatible: esperado true.")
    return {
        "sourceCulture": source,
        "installationCulture": installation,
        "targetLanguage": target,
        "hostCompatible": True,
        "hostLocresSha256": normalize_sha256(
            data.get("hostLocresSha256"), "localization.hostLocresSha256"
        ),
    }


def validate_dispatch_payload(payload: Any) -> dict[str, Any]:
    data = _require_object(payload, "client_payload")
    repository = _require_string(data.get("repository"), "repository")
    if repository != AUTHORIZED_REPOSITORY:
        raise ContractError("repository: repositório não autorizado.")
    tag = validate_tag(data.get("tag"))
    manifest_asset = _require_string(
        data.get("manifestAsset"), "manifestAsset"
    )
    if manifest_asset != MANIFEST_ASSET:
        raise ContractError("manifestAsset: asset não autorizado.")
    manifest_sha = normalize_sha256(
        data.get("manifestSha256"), "manifestSha256"
    )
    published_at = _require_string(data.get("publishedAt"), "publishedAt")
    parse_utc(published_at, "publishedAt")
    source_hash = normalize_sha256(data.get("sourceHash"), "sourceHash")
    match = TAG_PATTERN.fullmatch(tag)
    assert match is not None
    if match.group(3) != source_hash[:12]:
        raise ContractError("sourceHash: prefixo não corresponde à tag.")
    _validate_tag_timestamp(tag, published_at)
    game_build_id = validate_game_build_id(data.get("gameBuildId"))
    return {
        "repository": repository,
        "tag": tag,
        "manifestAsset": manifest_asset,
        "manifestSha256": manifest_sha,
        "publishedAt": published_at,
        "gameBuildId": game_build_id,
        "sourceHash": source_hash,
    }


def request_bytes(
    url: str,
    token: str | None = None,
    *,
    accept: str = "application/vnd.github+json",
    max_bytes: int = MAX_API_RESPONSE_BYTES,
) -> bytes:
    headers = {
        "Accept": accept,
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read(max_bytes + 1)
            if len(raw) > max_bytes:
                raise ContractError(
                    f"GitHub retornou mais de {max_bytes} bytes."
                )
            return raw
    except urllib.error.HTTPError as error:
        body = error.read(500).decode("utf-8", errors="replace")
        raise ContractError(
            f"GitHub retornou HTTP {error.code} para recurso autorizado: "
            f"{body}"
        ) from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ContractError(
            "GitHub ficou indisponível durante uma consulta autorizada."
        ) from error


def request_json(url: str, token: str | None = None) -> Any:
    raw = request_bytes(url, token)
    try:
        return json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError("GitHub retornou JSON inválido.") from error


def request_asset_bytes(url: str, token: str | None = None) -> bytes:
    return request_bytes(
        url,
        token,
        accept="application/octet-stream",
        max_bytes=MAX_MANIFEST_BYTES,
    )


def request_asset_sha256(
    url: str,
    expected_size: int,
    token: str | None = None,
) -> str:
    if expected_size <= 0 or expected_size > MAX_FALLBACK_ASSET_BYTES:
        raise ContractError("asset: tamanho excede o limite de fallback.")
    headers = {
        "Accept": "application/octet-stream",
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": API_VERSION,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    digest = hashlib.sha256()
    downloaded = 0
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            while True:
                chunk = response.read(min(1024 * 1024, expected_size + 1))
                if not chunk:
                    break
                downloaded += len(chunk)
                if (
                    downloaded > expected_size
                    or downloaded > MAX_FALLBACK_ASSET_BYTES
                ):
                    raise ContractError(
                        "asset: download excedeu o tamanho declarado."
                    )
                digest.update(chunk)
    except ContractError:
        raise
    except urllib.error.HTTPError as error:
        raise ContractError(
            f"GitHub retornou HTTP {error.code} ao baixar asset."
        ) from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ContractError(
            "GitHub ficou indisponível durante o download do asset."
        ) from error
    if downloaded != expected_size:
        raise ContractError("asset: download possui tamanho divergente.")
    return digest.hexdigest()


def fetch_release_by_tag(
    repository: str,
    tag: str,
    token: str | None = None,
    *,
    downloader: JsonDownloader = request_json,
) -> Mapping[str, Any]:
    if repository != AUTHORIZED_REPOSITORY:
        raise ContractError("repository: repositório não autorizado.")
    validate_tag(tag)
    encoded = urllib.parse.quote(tag, safe="")
    url = (
        f"https://api.github.com/repos/{repository}/releases/tags/{encoded}"
    )
    try:
        return _require_object(downloader(url, token), "release")
    except ContractError:
        raise
    except Exception as error:
        raise ContractError(f"release {tag}: não foi encontrada.") from error


def _validate_api_asset_url(url: Any, asset_id: Any) -> str:
    text = _require_string(url, "asset.url")
    parsed = urllib.parse.urlsplit(text)
    expected_path = (
        f"/repos/{AUTHORIZED_REPOSITORY}/releases/assets/{asset_id}"
    )
    if (
        parsed.scheme != "https"
        or parsed.hostname != "api.github.com"
        or parsed.port is not None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path != expected_path
        or parsed.query
        or parsed.fragment
    ):
        raise ContractError("asset.url: URL da API não autorizada.")
    return text


def _release_assets(release: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    raw_assets = release.get("assets")
    if not isinstance(raw_assets, list):
        raise ContractError("release.assets: era esperada uma lista.")
    assets: dict[str, Mapping[str, Any]] = {}
    exact_names: set[str] = set()
    for index, raw in enumerate(raw_assets):
        asset = _require_object(raw, f"release.assets[{index}]")
        name = _require_string(asset.get("name"), f"asset[{index}].name")
        folded = name.casefold()
        if folded in assets:
            raise ContractError(f"release: asset duplicado: {name}.")
        assets[folded] = asset
        exact_names.add(name)
    if exact_names != RELEASE_ASSETS:
        missing = sorted(RELEASE_ASSETS - exact_names)
        unexpected = sorted(exact_names - RELEASE_ASSETS)
        raise ContractError(
            "release: lista de assets divergente; "
            f"ausentes={missing}, inesperados={unexpected}."
        )
    return assets


def validate_release(
    release: Any,
    *,
    expected_tag: str | None = None,
) -> tuple[Mapping[str, Any], dict[str, Mapping[str, Any]]]:
    data = _require_object(release, "release")
    tag = validate_tag(data.get("tag_name"))
    if expected_tag is not None and tag != expected_tag:
        raise ContractError(
            f"release {tag}: tag diverge da solicitada {expected_tag}."
        )
    if type(data.get("draft")) is not bool or data["draft"]:
        raise ContractError(f"release {tag}: draft não é aceita.")
    if type(data.get("prerelease")) is not bool or data["prerelease"]:
        raise ContractError(f"release {tag}: prerelease não é aceita.")
    parse_utc(data.get("published_at"), "release.published_at")
    assets = _release_assets(data)
    for name, asset in assets.items():
        size = _require_int(asset.get("size"), f"asset {name}.size")
        if size <= 0:
            raise ContractError(f"asset {name}: tamanho inválido.")
        asset_id = _require_int(asset.get("id"), f"asset {name}.id")
        if asset_id <= 0:
            raise ContractError(f"asset {name}: id inválido.")
        _validate_api_asset_url(asset.get("url"), asset_id)
    return data, assets


def download_manifest_asset(
    release: Mapping[str, Any],
    *,
    expected_sha256: str | None,
    token: str | None = None,
    downloader: ByteDownloader = request_asset_bytes,
) -> bytes:
    data, assets = validate_release(
        release, expected_tag=str(release.get("tag_name", ""))
    )
    tag = str(data["tag_name"])
    asset = assets[MANIFEST_ASSET.casefold()]
    size = _require_int(asset["size"], "manifest.size")
    if size > MAX_MANIFEST_BYTES:
        raise ContractError(
            f"release {tag}: manifesto excede {MAX_MANIFEST_BYTES} bytes."
        )
    raw = downloader(str(asset["url"]), token)
    if not isinstance(raw, bytes):
        raise ContractError(f"release {tag}: manifesto não foi baixado em bytes.")
    if len(raw) != size or len(raw) > MAX_MANIFEST_BYTES:
        raise ContractError(
            f"release {tag}: tamanho baixado do manifesto diverge."
        )
    actual = hashlib.sha256(raw).hexdigest()
    remote_digest = asset.get("digest")
    if isinstance(remote_digest, str) and remote_digest:
        if not remote_digest.startswith("sha256:"):
            raise ContractError(
                f"release {tag}: digest remoto do manifesto é inválido."
            )
        if normalize_sha256(
            remote_digest[7:], "manifest asset digest"
        ) != actual:
            raise ContractError(
                f"release {tag}: digest remoto do manifesto diverge."
            )
    elif remote_digest not in (None, ""):
        raise ContractError(
            f"release {tag}: digest remoto do manifesto possui tipo inválido."
        )
    if expected_sha256 is not None:
        expected = normalize_sha256(expected_sha256, "manifestSha256")
        if actual != expected:
            raise ContractError(
                f"release {tag}: SHA-256 bruto do manifesto diverge."
            )
    return raw


def _validate_asset_download_url(url: Any, tag: str, name: str) -> str:
    text = _require_string(url, f"files[{name}].url")
    parsed = urllib.parse.urlsplit(text)
    expected_path = (
        f"/{AUTHORIZED_REPOSITORY}/releases/download/{tag}/{name}"
    )
    if (
        parsed.scheme != "https"
        or parsed.hostname != "github.com"
        or parsed.port is not None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path != expected_path
        or parsed.query
        or parsed.fragment
    ):
        raise ContractError(
            f"files[{name}].url: repositório, tag ou host inesperado."
        )
    return text


def validate_public_manifest(
    value: Any,
    *,
    require_source_identity: bool = True,
) -> dict[str, Any]:
    data = _require_object(value, "manifesto")
    if "source" in data:
        raise ContractError(
            "manifesto.source: objeto aninhado não pertence ao schema 1."
        )
    if _require_int(data.get("schemaVersion"), "schemaVersion") != 1:
        raise ContractError("schemaVersion: somente schema 1 é aceito.")
    tag = _require_string(
        data.get("translationVersion"), "translationVersion"
    )
    if require_source_identity:
        tag = validate_tag(tag)
    published_at = _require_string(data.get("publishedAt"), "publishedAt")
    parse_utc(published_at, "publishedAt")
    source_hash: str | None = None
    if "sourceHash" in data and data["sourceHash"] is not None:
        source_hash = normalize_sha256(data["sourceHash"], "sourceHash")
    elif require_source_identity:
        raise ContractError("sourceHash: campo obrigatório ausente.")
    game_build_id = validate_game_build_id(data.get("gameBuildId"))
    localization = (
        validate_localization(data["localization"])
        if "localization" in data
        else None
    )
    if require_source_identity:
        assert source_hash is not None
        match = TAG_PATTERN.fullmatch(tag)
        assert match is not None
        if match.group(3) != source_hash[:12]:
            raise ContractError("sourceHash: prefixo não corresponde à tag.")
        _validate_tag_timestamp(tag, published_at)

    raw_files = data.get("files")
    if not isinstance(raw_files, list) or not raw_files:
        raise ContractError("files: lista não vazia obrigatória.")
    if len(raw_files) != len(DESTINATIONS):
        raise ContractError("files: devem existir exatamente cinco arquivos.")
    files: list[dict[str, Any]] = []
    names: set[str] = set()
    destinations: set[str] = set()
    for index, raw in enumerate(raw_files):
        entry = _require_object(raw, f"files[{index}]")
        name = _require_string(entry.get("name"), f"files[{index}].name")
        folded_name = name.casefold()
        if folded_name in names:
            raise ContractError(f"files: nome duplicado: {name}.")
        names.add(folded_name)
        if name not in DESTINATIONS:
            raise ContractError(f"files: nome inesperado: {name}.")
        destination = _require_string(
            entry.get("relativeDestination"),
            f"files[{name}].relativeDestination",
        ).replace("\\", "/")
        if destination != DESTINATIONS[name]:
            raise ContractError(f"files[{name}]: destino não autorizado.")
        if (
            destination.startswith("/")
            or ":" in destination
            or any(
                part in {"", ".", ".."} for part in destination.split("/")
            )
        ):
            raise ContractError(f"files[{name}]: caminho relativo inseguro.")
        folded_destination = destination.casefold()
        if folded_destination in destinations:
            raise ContractError(f"files: destino duplicado: {destination}.")
        destinations.add(folded_destination)
        size = _require_int(entry.get("size"), f"files[{name}].size")
        if size <= 0:
            raise ContractError(f"files[{name}]: tamanho inválido.")
        digest = normalize_sha256(entry.get("sha256"), f"files[{name}].sha256")
        url = _validate_asset_download_url(entry.get("url"), tag, name)
        files.append(
            {
                "name": name,
                "relativeDestination": destination,
                "url": url,
                "size": size,
                "sha256": digest,
            }
        )
    if names != {name.casefold() for name in DESTINATIONS}:
        raise ContractError("files: arquivo obrigatório ausente.")
    result: dict[str, Any] = {
        "schemaVersion": 1,
        "translationVersion": tag,
        "publishedAt": published_at,
    }
    if "gameBuildId" in data or require_source_identity:
        result["gameBuildId"] = game_build_id
    if source_hash is not None:
        result["sourceHash"] = source_hash
    if localization is not None:
        result["localization"] = localization
    result["files"] = files
    return result


def parse_public_manifest(
    raw: bytes,
    *,
    require_source_identity: bool = True,
) -> dict[str, Any]:
    if not isinstance(raw, bytes):
        raise ContractError("manifesto: conteúdo deve ser bytes.")
    if not raw or len(raw) > MAX_MANIFEST_BYTES:
        raise ContractError("manifesto: tamanho vazio ou acima do limite.")
    try:
        decoded = raw.decode("utf-8")
        value = json.loads(decoded)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError("manifesto: JSON UTF-8 inválido.") from error
    return validate_public_manifest(
        value, require_source_identity=require_source_identity
    )


def compare_manifest_to_payload(
    manifest: Mapping[str, Any], payload: Mapping[str, Any]
) -> None:
    pairs = (
        ("translationVersion", "tag"),
        ("publishedAt", "publishedAt"),
        ("sourceHash", "sourceHash"),
        ("gameBuildId", "gameBuildId"),
    )
    for manifest_key, payload_key in pairs:
        if manifest.get(manifest_key) != payload.get(payload_key):
            raise ContractError(
                f"manifesto.{manifest_key}: diverge do payload."
            )


def _asset_digest(
    asset: Mapping[str, Any],
    *,
    name: str,
    token: str | None,
    downloader: ByteDownloader,
) -> str:
    digest_value = asset.get("digest")
    if isinstance(digest_value, str) and digest_value:
        if not digest_value.startswith("sha256:"):
            raise ContractError(f"asset {name}: digest remoto inválido.")
        return normalize_sha256(digest_value[7:], f"asset {name}.digest")
    if digest_value not in (None, ""):
        raise ContractError(f"asset {name}: digest remoto possui tipo inválido.")
    expected_size = _require_int(asset.get("size"), f"asset {name}.size")
    url = _validate_asset_download_url(
        asset.get("browser_download_url"),
        validate_tag(asset.get("_validated_tag")),
        name,
    )
    if downloader is request_asset_bytes:
        return request_asset_sha256(url, expected_size)
    contents = downloader(url, None)
    if not isinstance(contents, bytes) or len(contents) != expected_size:
        raise ContractError(f"asset {name}: download possui tamanho divergente.")
    return hashlib.sha256(contents).hexdigest()


def reconstruct_manifest_from_release(
    release: Mapping[str, Any],
    manifest: Mapping[str, Any],
    *,
    token: str | None = None,
    downloader: ByteDownloader = request_asset_bytes,
) -> dict[str, Any]:
    data, assets = validate_release(
        release, expected_tag=str(manifest["translationVersion"])
    )
    tag = str(data["tag_name"])
    reconstructed_files: list[dict[str, Any]] = []
    for name, destination in DESTINATIONS.items():
        asset = dict(assets[name.casefold()])
        asset["_validated_tag"] = tag
        size = _require_int(asset["size"], f"asset {name}.size")
        url = _validate_asset_download_url(
            asset.get("browser_download_url"), tag, name
        )
        digest = _asset_digest(
            asset,
            name=name,
            token=token,
            downloader=downloader,
        )
        reconstructed_files.append(
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
        "translationVersion": manifest["translationVersion"],
        "publishedAt": manifest["publishedAt"],
        "gameBuildId": manifest.get("gameBuildId"),
        "sourceHash": manifest["sourceHash"],
        **(
            {"localization": manifest["localization"]}
            if "localization" in manifest
            else {}
        ),
        "files": reconstructed_files,
    }


def compare_manifest_to_release(
    manifest: Mapping[str, Any],
    release: Mapping[str, Any],
    *,
    token: str | None = None,
    downloader: ByteDownloader = request_asset_bytes,
) -> None:
    reconstructed = reconstruct_manifest_from_release(
        release, manifest, token=token, downloader=downloader
    )
    actual = {entry["name"]: entry for entry in manifest["files"]}
    expected = {entry["name"]: entry for entry in reconstructed["files"]}
    if actual != expected:
        differing = sorted(
            name for name in expected if actual.get(name) != expected[name]
        )
        raise ContractError(
            "manifesto: metadados divergem dos assets da release: "
            + ", ".join(differing)
        )


def canonical_bytes(manifest: Mapping[str, Any]) -> bytes:
    return (
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    ).encode("utf-8")


def load_current_manifest(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise ContractError(f"manifesto atual ausente: {path}.")
    return parse_public_manifest(
        path.read_bytes(), require_source_identity=False
    )


def compare_candidate(
    current: Mapping[str, Any],
    candidate: Mapping[str, Any],
) -> str:
    current_date = parse_utc(current.get("publishedAt"), "current.publishedAt")
    candidate_date = parse_utc(
        candidate.get("publishedAt"), "candidate.publishedAt"
    )
    current_version = _require_string(
        current.get("translationVersion"), "current.translationVersion"
    )
    candidate_version = _require_string(
        candidate.get("translationVersion"), "candidate.translationVersion"
    )
    if candidate_date < current_date:
        raise RegressionError(
            f"downgrade bloqueado: {candidate_version} é anterior a "
            f"{current_version}."
        )
    if candidate_date == current_date:
        if candidate_version != current_version:
            raise RegressionError(
                "regressão bloqueada: datas iguais com versões diferentes."
            )
        if canonical_bytes(current) == canonical_bytes(candidate):
            return "already-current"
        if "localization" not in current and "localization" in candidate:
            candidate_without_localization = dict(candidate)
            candidate_without_localization.pop("localization", None)
            if canonical_bytes(current) == canonical_bytes(candidate_without_localization):
                return "metadata-enriched"
        raise RegressionError(
            "imutabilidade violada: mesma versão possui conteúdo diferente."
        )
    if candidate_version == current_version:
        raise RegressionError(
            "imutabilidade violada: mesma versão possui data diferente."
        )
    return "updated"


def atomic_apply_candidate(
    output: Path,
    candidate: Mapping[str, Any],
    *,
    mode: str,
) -> SyncResult:
    normalized_candidate = validate_public_manifest(candidate)
    current = load_current_manifest(output)
    decision = compare_candidate(current, normalized_candidate)
    changed = decision in {"updated", "metadata-enriched"}
    if changed:
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(output.name + ".nte-new")
        temporary.write_bytes(canonical_bytes(normalized_candidate))
        reread = parse_public_manifest(temporary.read_bytes())
        if reread != normalized_candidate:
            temporary.unlink(missing_ok=True)
            raise ContractError("escrita atômica: releitura do manifesto diverge.")
        os.replace(temporary, output)
        final = parse_public_manifest(output.read_bytes())
        if final != normalized_candidate:
            raise ContractError("escrita atômica: manifesto final diverge.")
    return SyncResult(
        mode=mode,
        repository=AUTHORIZED_REPOSITORY,
        tag=str(normalized_candidate["translationVersion"]),
        published_at=str(normalized_candidate["publishedAt"]),
        source_hash=str(normalized_candidate["sourceHash"]),
        game_build_id=normalized_candidate.get("gameBuildId"),
        file_count=len(normalized_candidate["files"]),
        previous_version=str(current["translationVersion"]),
        decision=decision,
        changed=changed,
    )


def candidate_from_dispatch(
    event: Any,
    *,
    token: str | None = None,
    json_downloader: JsonDownloader = request_json,
    byte_downloader: ByteDownloader = request_asset_bytes,
) -> dict[str, Any]:
    event_data = _require_object(event, "evento")
    payload = validate_dispatch_payload(event_data.get("client_payload"))
    release = fetch_release_by_tag(
        payload["repository"],
        payload["tag"],
        token,
        downloader=json_downloader,
    )
    validate_release(release, expected_tag=payload["tag"])
    raw = download_manifest_asset(
        release,
        expected_sha256=payload["manifestSha256"],
        token=token,
        downloader=byte_downloader,
    )
    manifest = parse_public_manifest(raw)
    compare_manifest_to_payload(manifest, payload)
    compare_manifest_to_release(
        manifest, release, token=token, downloader=byte_downloader
    )
    return manifest


def _release_pages(
    token: str | None,
    downloader: JsonDownloader,
) -> Iterable[Mapping[str, Any]]:
    yielded = 0
    for page in range(1, (MAX_RELEASES // 100) + 1):
        url = (
            f"https://api.github.com/repos/{AUTHORIZED_REPOSITORY}/releases"
            f"?per_page=100&page={page}"
        )
        raw = downloader(url, token)
        if not isinstance(raw, list):
            raise ContractError("recuperação: lista de releases inválida.")
        if not raw:
            break
        for item in raw:
            yielded += 1
            if yielded > MAX_RELEASES:
                return
            yield _require_object(item, "release listada")
        if len(raw) < 100:
            break


def candidate_from_recovery(
    *,
    token: str | None = None,
    json_downloader: JsonDownloader = request_json,
    byte_downloader: ByteDownloader = request_asset_bytes,
    releases: Iterable[Mapping[str, Any]] | None = None,
) -> dict[str, Any] | None:
    candidates: list[dict[str, Any]] = []
    source = releases if releases is not None else _release_pages(
        token, json_downloader
    )
    for release in source:
        tag = release.get("tag_name")
        if not isinstance(tag, str) or TAG_PATTERN.fullmatch(tag) is None:
            continue
        if release.get("draft") is not False or release.get("prerelease") is not False:
            continue
        try:
            validate_release(release, expected_tag=tag)
            raw = download_manifest_asset(
                release,
                expected_sha256=None,
                token=token,
                downloader=byte_downloader,
            )
            manifest = parse_public_manifest(raw)
            if manifest["translationVersion"] != tag:
                raise ContractError(
                    f"release {tag}: manifesto pertence a outra tag."
                )
            compare_manifest_to_release(
                manifest, release, token=token, downloader=byte_downloader
            )
            candidates.append(manifest)
        except ContractError as error:
            print(f"Ignorando release inválida {tag}: {error}")
    if not candidates:
        return None
    candidates.sort(
        key=lambda item: parse_utc(item["publishedAt"], "publishedAt"),
        reverse=True,
    )
    if len(candidates) > 1:
        first_date = parse_utc(candidates[0]["publishedAt"], "publishedAt")
        second_date = parse_utc(candidates[1]["publishedAt"], "publishedAt")
        if (
            first_date == second_date
            and candidates[0]["translationVersion"]
            != candidates[1]["translationVersion"]
        ):
            raise ContractError(
                "recuperação: releases diferentes possuem publishedAt igual."
            )
    return candidates[0]


def no_release_result(output: Path) -> SyncResult:
    current = load_current_manifest(output)
    return SyncResult(
        mode="recovery",
        repository=AUTHORIZED_REPOSITORY,
        tag=None,
        published_at=None,
        source_hash=None,
        game_build_id=None,
        file_count=0,
        previous_version=str(current["translationVersion"]),
        decision="no-valid-release",
        changed=False,
    )


def safe_summary(result: SyncResult) -> str:
    values = result.to_dict()
    for value in values.values():
        if isinstance(value, str) and CONTROL_PATTERN.search(value):
            raise ContractError("resumo: valor com caractere de controle.")
    source = (
        result.source_hash[:12] if result.source_hash else "não informado"
    )
    build = result.game_build_id or "não informado"
    previous = result.previous_version or "não informado"
    tag = result.tag or "nenhuma release válida"
    return (
        "## Sincronização do manifesto de tradução\n\n"
        f"- Modo: `{result.mode}`\n"
        f"- Repositório: `{result.repository}`\n"
        f"- Tag: `{tag}`\n"
        f"- `publishedAt`: `{result.published_at or 'não informado'}`\n"
        f"- `sourceHash`: `{source}`\n"
        f"- `gameBuildId`: `{build}`\n"
        f"- Arquivos instaláveis: `{result.file_count}`\n"
        f"- Manifesto anterior: `{previous}`\n"
        f"- Decisão: **{result.decision}**\n"
    )


def write_json_atomic(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".nte-new")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    os.replace(temporary, path)
