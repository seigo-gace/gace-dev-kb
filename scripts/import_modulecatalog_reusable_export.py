#!/usr/bin/env python3
"""Import a pinned ModuleCatalog reusable-asset export into searchable G-ACE KB data."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

FORMAT = "gace.reusable-asset.v1"
CATALOG_REPOSITORY = "seigo-gace/modular-catalog"
REQUIRED_ASSET_SECTIONS = (
    "identity",
    "classification",
    "discovery",
    "applicability",
    "contract",
    "composition",
    "implementation",
    "verification",
    "provenance",
    "lifecycle",
    "integrity",
    "derivation",
)
REQUIRED_BUNDLE_FILES = (
    "asset.json",
    "knowledge-units.jsonl",
    "relationships.jsonl",
    "cases.jsonl",
)


@dataclass(frozen=True)
class KnowledgeRecord:
    type: str
    repository: str
    commit: str
    summary: str
    cause: str
    fix: str
    validation: str
    source: str


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON_OBJECT_REQUIRED={path}")
    return value


def read_jsonl(path: Path, empty_code: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise RuntimeError(f"JSONL_OBJECT_REQUIRED file={path} line={line_number}")
            rows.append(value)
    if not rows:
        raise RuntimeError(empty_code)
    return rows


def verify_bundle_manifest(
    asset_dir: Path,
    manifest: dict[str, Any],
    *,
    asset_id: str,
    catalog_commit: str,
    expected_asset_hash: str,
    expected_bundle_hash: str,
) -> None:
    if manifest.get("schema_version") != 1:
        raise RuntimeError(f"BUNDLE_MANIFEST_SCHEMA_UNSUPPORTED={asset_id}")
    if manifest.get("format") != FORMAT:
        raise RuntimeError(f"BUNDLE_FORMAT_UNSUPPORTED={asset_id}")
    if manifest.get("algorithm") != "sha256":
        raise RuntimeError(f"BUNDLE_MANIFEST_ALGORITHM_NOT_SHA256={asset_id}")
    if str(manifest.get("asset_id") or "") != asset_id:
        raise RuntimeError(f"BUNDLE_ASSET_ID_MISMATCH={asset_id}")

    catalog = manifest.get("catalog")
    if not isinstance(catalog, dict):
        raise RuntimeError(f"BUNDLE_CATALOG_PROVENANCE_MISSING={asset_id}")
    if str(catalog.get("repository") or "") != CATALOG_REPOSITORY:
        raise RuntimeError(f"BUNDLE_CATALOG_REPOSITORY_MISMATCH={asset_id}")
    if str(catalog.get("commit") or "") != catalog_commit:
        raise RuntimeError(f"BUNDLE_CATALOG_COMMIT_MISMATCH={asset_id}")
    if str(catalog.get("asset_path") or "") != f"assets/{asset_id}":
        raise RuntimeError(f"BUNDLE_CATALOG_ASSET_PATH_MISMATCH={asset_id}")

    source_asset_hash = str(manifest.get("source_asset_hash") or "")
    if source_asset_hash != expected_asset_hash:
        raise RuntimeError(f"BUNDLE_SOURCE_ASSET_HASH_MISMATCH={asset_id}")
    if str(manifest.get("bundle_hash") or "") != expected_bundle_hash:
        raise RuntimeError(f"BUNDLE_HASH_DECLARATION_MISMATCH={asset_id}")

    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        raise RuntimeError(f"BUNDLE_MANIFEST_FILES_MISSING={asset_id}")

    listed: set[str] = set()
    normalized_files: list[dict[str, Any]] = []
    for item in files:
        if not isinstance(item, dict):
            raise RuntimeError(f"BUNDLE_MANIFEST_FILE_ENTRY_INVALID={asset_id}")
        rel = str(item.get("path") or "").replace("\\", "/").strip("/")
        if not rel:
            raise RuntimeError(f"BUNDLE_MANIFEST_PATH_EMPTY={asset_id}")
        if rel in listed:
            raise RuntimeError(f"BUNDLE_MANIFEST_DUPLICATE_PATH={asset_id}:{rel}")
        listed.add(rel)
        path = (asset_dir / rel).resolve()
        try:
            path.relative_to(asset_dir.resolve())
        except ValueError as exc:
            raise RuntimeError(f"BUNDLE_MANIFEST_PATH_ESCAPE={asset_id}:{rel}") from exc
        if not path.is_file():
            raise RuntimeError(f"BUNDLE_MANIFEST_FILE_MISSING={asset_id}:{rel}")
        expected_size = int(item.get("size", -1))
        if expected_size < 0 or path.stat().st_size != expected_size:
            raise RuntimeError(f"BUNDLE_MANIFEST_SIZE_MISMATCH={asset_id}:{rel}")
        expected_hash = str(item.get("sha256") or "").lower()
        if sha256_file(path) != expected_hash:
            raise RuntimeError(f"BUNDLE_MANIFEST_SHA256_MISMATCH={asset_id}:{rel}")
        normalized_files.append({"path": rel, "size": expected_size, "sha256": expected_hash})

    for rel in REQUIRED_BUNDLE_FILES:
        if rel not in listed:
            raise RuntimeError(f"BUNDLE_REQUIRED_FILE_NOT_MANIFESTED={asset_id}:{rel}")

    actual_bundle_hash = sha256_bytes(canonical_json(normalized_files).encode("utf-8"))
    if actual_bundle_hash != expected_bundle_hash:
        raise RuntimeError(f"BUNDLE_HASH_MISMATCH={asset_id}")


def validate_asset(asset: dict[str, Any], asset_id: str, catalog_commit: str) -> None:
    if asset.get("schema_version") != 1:
        raise RuntimeError(f"ASSET_SCHEMA_UNSUPPORTED={asset_id}")
    missing = [key for key in REQUIRED_ASSET_SECTIONS if not isinstance(asset.get(key), dict)]
    if missing:
        raise RuntimeError(f"ASSET_REQUIRED_SECTION_MISSING={asset_id}:{','.join(missing)}")

    identity = asset["identity"]
    if str(identity.get("asset_id") or "") != asset_id:
        raise RuntimeError(f"ASSET_ID_MISMATCH={asset_id}")
    for field in ("name", "version", "asset_kind"):
        if not str(identity.get(field) or "").strip():
            raise RuntimeError(f"ASSET_IDENTITY_FIELD_MISSING={asset_id}:{field}")

    verification = asset["verification"]
    if str(verification.get("status") or "") != "verified":
        raise RuntimeError(f"ASSET_NOT_VERIFIED={asset_id}:{verification.get('status')}")

    provenance = asset["provenance"]
    catalog = provenance.get("catalog")
    if not isinstance(catalog, dict):
        raise RuntimeError(f"ASSET_CATALOG_PROVENANCE_MISSING={asset_id}")
    if str(catalog.get("repository") or "") != CATALOG_REPOSITORY:
        raise RuntimeError(f"ASSET_CATALOG_REPOSITORY_MISMATCH={asset_id}")
    if str(catalog.get("commit") or "") != catalog_commit:
        raise RuntimeError(f"ASSET_CATALOG_COMMIT_MISMATCH={asset_id}")
    if str(catalog.get("asset_id") or "") != asset_id:
        raise RuntimeError(f"ASSET_CATALOG_ID_MISMATCH={asset_id}")
    if str(catalog.get("asset_path") or "") != f"assets/{asset_id}":
        raise RuntimeError(f"ASSET_CATALOG_PATH_MISMATCH={asset_id}")


def validate_unit(unit: dict[str, Any], asset_id: str) -> None:
    required = (
        "schema_version",
        "knowledge_id",
        "parent_asset_id",
        "knowledge_kind",
        "title",
        "content",
        "source_paths",
        "content_status",
        "derivation",
    )
    missing = [key for key in required if key not in unit]
    if missing:
        raise RuntimeError(f"KNOWLEDGE_UNIT_FIELD_MISSING={asset_id}:{','.join(missing)}")
    if unit.get("schema_version") != 1:
        raise RuntimeError(f"KNOWLEDGE_UNIT_SCHEMA_UNSUPPORTED={asset_id}")
    knowledge_id = str(unit.get("knowledge_id") or "")
    if not knowledge_id:
        raise RuntimeError(f"KNOWLEDGE_UNIT_ID_MISSING={asset_id}")
    if str(unit.get("parent_asset_id") or "") != asset_id:
        raise RuntimeError(f"KNOWLEDGE_UNIT_PARENT_MISMATCH={knowledge_id}")
    if not str(unit.get("knowledge_kind") or "").strip():
        raise RuntimeError(f"KNOWLEDGE_UNIT_KIND_MISSING={knowledge_id}")
    if not str(unit.get("title") or "").strip():
        raise RuntimeError(f"KNOWLEDGE_UNIT_TITLE_MISSING={knowledge_id}")
    if not isinstance(unit.get("source_paths"), list) or not unit["source_paths"]:
        raise RuntimeError(f"KNOWLEDGE_UNIT_SOURCE_PATHS_MISSING={knowledge_id}")
    derivation = unit.get("derivation")
    if not isinstance(derivation, dict):
        raise RuntimeError(f"KNOWLEDGE_UNIT_DERIVATION_MISSING={knowledge_id}")
    if not isinstance(derivation.get("derived_from"), list) or not derivation["derived_from"]:
        raise RuntimeError(f"KNOWLEDGE_UNIT_DERIVED_FROM_MISSING={knowledge_id}")


def validate_case(case: dict[str, Any], asset_id: str) -> None:
    if case.get("schema_version") != 1:
        raise RuntimeError(f"CASE_SCHEMA_UNSUPPORTED={asset_id}")
    case_id = str(case.get("case_id") or "")
    if not case_id:
        raise RuntimeError(f"CASE_ID_MISSING={asset_id}")
    if str(case.get("parent_asset_id") or "") != asset_id:
        raise RuntimeError(f"CASE_PARENT_MISMATCH={case_id}")
    if not str(case.get("source_test") or "").strip():
        raise RuntimeError(f"CASE_SOURCE_TEST_MISSING={case_id}")


def validate_relationship(rel: dict[str, Any], asset_id: str) -> None:
    if rel.get("schema_version") != 1:
        raise RuntimeError(f"RELATIONSHIP_SCHEMA_UNSUPPORTED={asset_id}")
    for field in ("relationship_id", "from", "relation", "to"):
        if not str(rel.get(field) or "").strip():
            raise RuntimeError(f"RELATIONSHIP_FIELD_MISSING={asset_id}:{field}")


def verification_text(asset: dict[str, Any]) -> str:
    verification = asset["verification"]
    parts = ["status=verified"]
    if verification.get("verified_at"):
        parts.append(f"verifiedAt={verification['verified_at']}")
    if verification.get("validation_boundary"):
        parts.append(f"boundary={verification['validation_boundary']}")
    for key, label in (("normal_test", "normal"), ("user_test", "user")):
        section = verification.get(key)
        if isinstance(section, dict) and "passed" in section:
            parts.append(f"{label}.passed={str(bool(section['passed'])).lower()}")
    return "; ".join(parts)


def data_class(unit: dict[str, Any]) -> str:
    kind = str((unit.get("derivation") or {}).get("type") or "")
    return "derived" if "derived" in kind and "canonical" not in kind else "canonical"


def list_text(value: Any) -> str:
    if not isinstance(value, list):
        return ""
    return " | ".join(str(item) for item in value if str(item).strip())


def append_search_line(lines: list[str], label: str, value: Any) -> None:
    if value is None:
        return
    if isinstance(value, list):
        text = list_text(value)
    elif isinstance(value, bool):
        text = str(value).lower()
    else:
        text = str(value).strip()
    if text:
        lines.append(f"- {label}: {text}")


def render_markdown(
    *,
    asset: dict[str, Any],
    unit: dict[str, Any],
    cases: list[dict[str, Any]],
    relationships: list[dict[str, Any]],
    record: KnowledgeRecord,
) -> str:
    identity = asset["identity"]
    classification = asset["classification"]
    discovery = asset["discovery"]
    applicability = asset["applicability"]
    contract = asset["contract"]
    composition = asset["composition"]
    lifecycle = asset["lifecycle"]
    verification = asset["verification"]
    provenance = asset["provenance"]
    integrity = asset["integrity"]

    lines = [
        f"# {unit['title']}",
        "",
        "## Search Metadata",
        "",
    ]
    append_search_line(lines, "Knowledge ID", unit["knowledge_id"])
    append_search_line(lines, "Parent Asset", identity.get("asset_id"))
    append_search_line(lines, "Asset Name", identity.get("name"))
    append_search_line(lines, "Asset Version", identity.get("version"))
    append_search_line(lines, "Asset Kind", identity.get("asset_kind"))
    append_search_line(lines, "Symbol", identity.get("symbol"))
    append_search_line(lines, "Knowledge Kind", unit.get("knowledge_kind"))
    append_search_line(lines, "Data Class", data_class(unit))
    append_search_line(lines, "Lifecycle", lifecycle.get("status"))
    append_search_line(lines, "Verification", verification.get("status"))
    append_search_line(lines, "Summary", discovery.get("summary"))
    append_search_line(lines, "Purpose", discovery.get("purpose"))
    append_search_line(lines, "Responsibility", discovery.get("responsibility"))
    append_search_line(lines, "Capabilities", discovery.get("capabilities"))
    append_search_line(lines, "Keywords", discovery.get("keywords"))
    append_search_line(lines, "Semantic Terms", discovery.get("semantic_terms"))
    append_search_line(lines, "Domains", classification.get("domains"))
    append_search_line(lines, "Layers", classification.get("layers"))
    append_search_line(lines, "Languages", classification.get("languages"))
    append_search_line(lines, "Runtimes", classification.get("runtimes"))
    append_search_line(lines, "Tags", classification.get("tags"))
    append_search_line(lines, "Use When", applicability.get("use_when"))
    append_search_line(lines, "Do Not Use When", applicability.get("do_not_use_when"))
    append_search_line(lines, "Preconditions", applicability.get("preconditions"))
    append_search_line(lines, "Required Context", applicability.get("required_context"))
    append_search_line(lines, "Failure Conditions", applicability.get("failure_conditions"))
    append_search_line(lines, "Contract Status", contract.get("status"))
    append_search_line(lines, "Inputs", contract.get("inputs"))
    append_search_line(lines, "Outputs", contract.get("outputs"))
    append_search_line(lines, "Required Fields", contract.get("required_fields"))
    append_search_line(lines, "Optional Fields", contract.get("optional_fields"))
    append_search_line(lines, "Error Behavior", contract.get("error_behavior"))
    append_search_line(lines, "Side Effects", contract.get("side_effects"))
    append_search_line(lines, "Mutation Authority", contract.get("mutation_authority"))
    append_search_line(lines, "Depends On", composition.get("depends_on"))
    append_search_line(lines, "Requires", composition.get("requires"))
    append_search_line(lines, "Recommended Before", composition.get("recommended_before"))
    append_search_line(lines, "Recommended After", composition.get("recommended_after"))
    append_search_line(lines, "Complements", composition.get("complements"))
    append_search_line(lines, "Alternative To", composition.get("alternative_to"))
    append_search_line(lines, "Conflicts With", composition.get("conflicts_with"))
    append_search_line(lines, "Supersedes", composition.get("supersedes"))
    append_search_line(lines, "Source Paths", unit.get("source_paths"))
    append_search_line(lines, "Catalog Commit", record.commit)
    append_search_line(lines, "Asset Hash", integrity.get("asset_hash"))

    lines.extend(
        [
            "",
            "## Knowledge Content",
            "",
            str(unit.get("content") or "(not recorded)"),
            "",
            "## Verification Boundary",
            "",
            record.validation,
            "",
            "## Provenance",
            "",
            "```json",
            json.dumps(provenance, ensure_ascii=False, indent=2, sort_keys=True),
            "```",
            "",
        ]
    )
    if cases:
        lines.extend(
            [
                "## Reusable Cases",
                "",
                "```json",
                json.dumps(cases, ensure_ascii=False, indent=2, sort_keys=True),
                "```",
                "",
            ]
        )
    if relationships:
        lines.extend(
            [
                "## Relationships",
                "",
                "```json",
                json.dumps(relationships, ensure_ascii=False, indent=2, sort_keys=True),
                "```",
                "",
            ]
        )
    return "\n".join(lines)


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


def import_export(
    export_root: Path,
    output_root: Path,
    *,
    expected_catalog_commit: str | None = None,
    expected_asset_count: int | None = None,
    expected_record_count: int | None = None,
) -> tuple[list[KnowledgeRecord], list[dict[str, Any]], Path, int]:
    export_root = export_root.resolve()
    top_manifest = read_json(export_root / "manifest.json")
    if top_manifest.get("schema_version") != 1 or top_manifest.get("format") != FORMAT:
        raise RuntimeError("TOP_MANIFEST_FORMAT_UNSUPPORTED")
    top_catalog = top_manifest.get("catalog")
    if not isinstance(top_catalog, dict):
        raise RuntimeError("TOP_MANIFEST_CATALOG_MISSING")
    if str(top_catalog.get("repository") or "") != CATALOG_REPOSITORY:
        raise RuntimeError("TOP_MANIFEST_CATALOG_REPOSITORY_MISMATCH")
    catalog_commit = str(top_catalog.get("commit") or "")
    if not catalog_commit:
        raise RuntimeError("TOP_MANIFEST_CATALOG_COMMIT_MISSING")
    if expected_catalog_commit and catalog_commit != expected_catalog_commit:
        raise RuntimeError(
            f"TOP_MANIFEST_COMMIT_MISMATCH expected={expected_catalog_commit} actual={catalog_commit}"
        )

    items = top_manifest.get("assets")
    if not isinstance(items, list) or not items:
        raise RuntimeError("TOP_MANIFEST_ASSETS_EMPTY")
    declared_asset_count = int(top_manifest.get("assetCount", -1))
    if declared_asset_count != len(items):
        raise RuntimeError(
            f"TOP_MANIFEST_ASSET_COUNT_MISMATCH declared={declared_asset_count} actual={len(items)}"
        )
    if expected_asset_count is not None and len(items) != expected_asset_count:
        raise RuntimeError(
            f"EXPORT_ASSET_COUNT_MISMATCH expected={expected_asset_count} actual={len(items)}"
        )

    asset_ids = [str(item.get("id") or "") for item in items if isinstance(item, dict)]
    if any(not asset_id for asset_id in asset_ids) or len(asset_ids) != len(items):
        raise RuntimeError("TOP_MANIFEST_ASSET_ID_INVALID")
    if len(set(asset_ids)) != len(asset_ids):
        raise RuntimeError("TOP_MANIFEST_ASSET_ID_DUPLICATE")

    assets_root = export_root / "assets"
    actual_dirs = sorted(path.name for path in assets_root.iterdir() if path.is_dir())
    if actual_dirs != sorted(asset_ids):
        raise RuntimeError("EXPORT_ASSET_DIRECTORY_SET_MISMATCH")

    records: list[KnowledgeRecord] = []
    metadata: list[dict[str, Any]] = []
    corpus_rows: list[tuple[str, str]] = []
    all_unit_ids: set[str] = set()
    all_relationships: list[dict[str, Any]] = []

    for item in items:
        asset_id = str(item["id"])
        asset_dir = assets_root / asset_id
        expected_asset_hash = str(item.get("assetHash") or "")
        expected_bundle_hash = str(item.get("bundleHash") or "")
        manifest = read_json(asset_dir / "manifest.json")
        verify_bundle_manifest(
            asset_dir,
            manifest,
            asset_id=asset_id,
            catalog_commit=catalog_commit,
            expected_asset_hash=expected_asset_hash,
            expected_bundle_hash=expected_bundle_hash,
        )
        asset = read_json(asset_dir / "asset.json")
        validate_asset(asset, asset_id, catalog_commit)
        if str(asset["integrity"].get("asset_hash") or "") != expected_asset_hash:
            raise RuntimeError(f"ASSET_INTEGRITY_HASH_MISMATCH={asset_id}")

        units = read_jsonl(asset_dir / "knowledge-units.jsonl", f"KNOWLEDGE_UNITS_EMPTY={asset_id}")
        relationships = read_jsonl(
            asset_dir / "relationships.jsonl", f"RELATIONSHIPS_EMPTY={asset_id}"
        )
        cases = read_jsonl(asset_dir / "cases.jsonl", f"CASES_EMPTY={asset_id}")
        if len(units) != int(item.get("knowledgeUnits", -1)):
            raise RuntimeError(f"KNOWLEDGE_UNIT_COUNT_MISMATCH={asset_id}")
        if len(relationships) != int(item.get("relationships", -1)):
            raise RuntimeError(f"RELATIONSHIP_COUNT_MISMATCH={asset_id}")
        if len(cases) != int(item.get("cases", -1)):
            raise RuntimeError(f"CASE_COUNT_MISMATCH={asset_id}")

        unit_ids: set[str] = set()
        for unit in units:
            validate_unit(unit, asset_id)
            unit_id = str(unit["knowledge_id"])
            if unit_id in unit_ids or unit_id in all_unit_ids:
                raise RuntimeError(f"KNOWLEDGE_UNIT_ID_DUPLICATE={unit_id}")
            unit_ids.add(unit_id)
            all_unit_ids.add(unit_id)

        case_ids: set[str] = set()
        cases_by_source: dict[str, list[dict[str, Any]]] = {}
        for case in cases:
            validate_case(case, asset_id)
            case_id = str(case["case_id"])
            if case_id in case_ids:
                raise RuntimeError(f"CASE_ID_DUPLICATE={case_id}")
            case_ids.add(case_id)
            cases_by_source.setdefault(str(case["source_test"]), []).append(case)

        relationship_ids: set[str] = set()
        for relationship in relationships:
            validate_relationship(relationship, asset_id)
            relationship_id = str(relationship["relationship_id"])
            if relationship_id in relationship_ids:
                raise RuntimeError(f"RELATIONSHIP_ID_DUPLICATE={relationship_id}")
            relationship_ids.add(relationship_id)
            all_relationships.append(relationship)

        identity = asset["identity"]
        discovery = asset["discovery"]
        verification = verification_text(asset)
        for unit in units:
            unit_id = str(unit["knowledge_id"])
            kind = str(unit["knowledge_kind"])
            summary = " | ".join(
                part
                for part in (
                    str(discovery.get("summary") or "").strip(),
                    str(unit.get("title") or "").strip(),
                    kind,
                )
                if part
            )
            source = (
                f"modulecatalog:{CATALOG_REPOSITORY}@{catalog_commit}"
                f"#assets/{asset_id}::{unit_id}"
            )
            record = KnowledgeRecord(
                type="reusable_asset",
                repository=CATALOG_REPOSITORY,
                commit=catalog_commit,
                summary=summary,
                cause="",
                fix="",
                validation=verification,
                source=source,
            )
            records.append(record)

            matching_cases: list[dict[str, Any]] = []
            for source_path in unit.get("source_paths") or []:
                matching_cases.extend(cases_by_source.get(str(source_path), []))
            matching_relationships = [
                rel
                for rel in relationships
                if str(rel.get("from")) in {asset_id, unit_id}
                and (str(rel.get("to")) == unit_id or str(rel.get("from")) == unit_id)
            ]
            meta = {
                "schema_version": 1,
                "knowledge_id": unit_id,
                "parent_asset_id": asset_id,
                "identity": asset["identity"],
                "asset_kind": identity.get("asset_kind"),
                "knowledge_kind": kind,
                "name": unit.get("title"),
                "summary": summary,
                "version": identity.get("version"),
                "data_class": data_class(unit),
                "classification": asset["classification"],
                "discovery": asset["discovery"],
                "applicability": asset["applicability"],
                "contract": asset["contract"],
                "composition": asset["composition"],
                "implementation": asset["implementation"],
                "cases": matching_cases,
                "relationships": matching_relationships,
                "verification": asset["verification"],
                "provenance": asset["provenance"],
                "lifecycle": asset["lifecycle"],
                "integrity": {**asset["integrity"], "bundle_hash": expected_bundle_hash},
                "asset_derivation": asset["derivation"],
                "unit_derivation": unit["derivation"],
                "source_paths": unit.get("source_paths"),
                "content_status": unit.get("content_status"),
                "content": unit.get("content"),
                "_gace": asdict(record),
            }
            metadata.append(meta)
            corpus_rows.append(
                (
                    unit_id,
                    render_markdown(
                        asset=asset,
                        unit=unit,
                        cases=matching_cases,
                        relationships=matching_relationships,
                        record=record,
                    ),
                )
            )

    allowed_nodes = set(asset_ids) | all_unit_ids
    relationship_ids: set[str] = set()
    for rel in all_relationships:
        relationship_id = str(rel["relationship_id"])
        if relationship_id in relationship_ids:
            raise RuntimeError(f"RELATIONSHIP_ID_GLOBAL_DUPLICATE={relationship_id}")
        relationship_ids.add(relationship_id)
        if str(rel["from"]) not in allowed_nodes or str(rel["to"]) not in allowed_nodes:
            raise RuntimeError(f"RELATIONSHIP_TARGET_UNKNOWN={relationship_id}")

    expected_total = sum(int(item.get("knowledgeUnits", 0)) for item in items)
    if len(records) != expected_total:
        raise RuntimeError(
            f"EXPORT_KNOWLEDGE_COUNT_MISMATCH expected={expected_total} actual={len(records)}"
        )
    if expected_record_count is not None and len(records) != expected_record_count:
        raise RuntimeError(
            f"RECORD_COUNT_MISMATCH expected={expected_record_count} actual={len(records)}"
        )

    output_root = output_root.resolve()
    corpus = output_root / "records"
    corpus.mkdir(parents=True, exist_ok=True)
    for path in corpus.glob("*.md"):
        path.unlink()
    for index, (unit_id, markdown) in enumerate(corpus_rows, start=1):
        safe_id = re.sub(r"[^0-9A-Za-z._-]+", "-", unit_id).strip("-") or "knowledge"
        (corpus / f"{index:04d}-{safe_id[:120]}.md").write_text(
            markdown, encoding="utf-8", newline="\n"
        )

    write_jsonl(output_root / "knowledge-records.jsonl", [asdict(row) for row in records])
    write_jsonl(output_root / "knowledge-metadata.jsonl", metadata)
    return records, metadata, corpus, len(items)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--export-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--expected-catalog-commit")
    parser.add_argument("--expected-asset-count", type=int)
    parser.add_argument("--expected-record-count", type=int)
    args = parser.parse_args()
    records, metadata, corpus, asset_count = import_export(
        args.export_root,
        args.output_root,
        expected_catalog_commit=args.expected_catalog_commit,
        expected_asset_count=args.expected_asset_count,
        expected_record_count=args.expected_record_count,
    )
    kinds = sorted({str(row.get("knowledge_kind")) for row in metadata})
    print(
        f"GACE_MODULECATALOG_REUSABLE_IMPORT=PASS ASSETS={asset_count} "
        f"RECORDS={len(records)} KNOWLEDGE_KINDS={','.join(kinds)} CORPUS={corpus}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
