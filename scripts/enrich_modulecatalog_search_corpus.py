#!/usr/bin/env python3
"""Enrich accepted ModuleCatalog Markdown projection for the existing KB runtime.

The transported bundle remains canonical and untouched. This operates only on the
local derived Markdown corpus, adding deterministic YAML frontmatter that the
installed mcp-vector-search 4.1.14 runtime can use for search tags and
cross-document Knowledge Graph links.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

BASE_TAG = "gace-reusable-asset"


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if not rows:
        raise RuntimeError(f"METADATA_EMPTY={path}")
    return rows


def load_optional_jsonl(path: Path, label: str) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise RuntimeError(f"RUNTIME_{label}_OBJECT_REQUIRED={path}:{line_number}")
        rows.append(value)
    return rows


def safe_tag(value: Any) -> str:
    text = str(value or "unknown").strip().lower()
    text = re.sub(r"[^0-9a-z._-]+", "-", text).strip("-")
    return text or "unknown"


def q(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def runtime_relationships_for(
    row: dict[str, Any],
    global_relationships: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    knowledge_id = str(row.get("knowledge_id") or "")
    asset_id = str(row.get("parent_asset_id") or "")
    kind = str(row.get("knowledge_kind") or "")
    combined: list[dict[str, Any]] = []
    seen: set[str] = set()

    for rel in list(row.get("relationships") or []) + global_relationships:
        if not isinstance(rel, dict):
            continue
        source = str(rel.get("from") or "")
        target = str(rel.get("to") or "")
        relevant = source == knowledge_id or target == knowledge_id
        if kind == "discovery":
            relevant = relevant or source == asset_id or target == asset_id
        if not relevant:
            continue
        relation_id = str(rel.get("relationship_id") or "")
        dedupe_key = relation_id or json.dumps(rel, sort_keys=True, ensure_ascii=False)
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        combined.append(rel)
    return combined


def runtime_cases_for(
    row: dict[str, Any],
    global_cases: list[dict[str, Any]],
    source_owners: dict[tuple[str, str], set[str]],
) -> list[dict[str, Any]]:
    knowledge_id = str(row.get("knowledge_id") or "")
    asset_id = str(row.get("parent_asset_id") or "")
    kind = str(row.get("knowledge_kind") or "")
    combined: list[dict[str, Any]] = []
    seen: set[str] = set()

    for case in list(row.get("cases") or []) + global_cases:
        if not isinstance(case, dict):
            continue
        if str(case.get("parent_asset_id") or "") != asset_id:
            continue
        source_test = str(case.get("source_test") or "")
        owners = source_owners.get((asset_id, source_test), set()) if source_test else set()
        relevant = knowledge_id in owners
        if not owners and kind == "discovery":
            relevant = True
        if case in (row.get("cases") or []):
            relevant = True
        if not relevant:
            continue
        case_id = str(case.get("case_id") or "")
        dedupe_key = case_id or json.dumps(case, sort_keys=True, ensure_ascii=False)
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        combined.append(case)
    return combined


def frontmatter_for(row: dict[str, Any], related_files: list[str]) -> str:
    asset_id = str(row.get("parent_asset_id") or "")
    knowledge_id = str(row.get("knowledge_id") or "")
    kind = str(row.get("knowledge_kind") or "unknown")
    lifecycle = row.get("lifecycle") if isinstance(row.get("lifecycle"), dict) else {}
    verification = row.get("verification") if isinstance(row.get("verification"), dict) else {}
    classification = row.get("classification") if isinstance(row.get("classification"), dict) else {}
    composition = row.get("composition") if isinstance(row.get("composition"), dict) else {}
    if not asset_id or not knowledge_id:
        raise RuntimeError("CORPUS_FRONTMATTER_IDENTITY_MISSING")

    relationships = [value for value in (row.get("relationships") or []) if isinstance(value, dict)]
    cases = [value for value in (row.get("cases") or []) if isinstance(value, dict)]

    tags: list[str] = [
        BASE_TAG,
        f"asset-{safe_tag(asset_id)}",
        f"knowledge-kind-{safe_tag(kind)}",
        f"lifecycle-{safe_tag(lifecycle.get('status'))}",
        f"verification-{safe_tag(verification.get('status'))}",
    ]
    for value in classification.get("languages") or []:
        tags.append(f"language-{safe_tag(value)}")
    for value in classification.get("runtimes") or []:
        tags.append(f"runtime-{safe_tag(value)}")
    for value in classification.get("tags") or []:
        tags.append(f"catalog-tag-{safe_tag(value)}")

    relationship_ids: list[str] = []
    for rel in relationships:
        relation = str(rel.get("relation") or "").strip()
        relationship_id = str(rel.get("relationship_id") or "").strip()
        if relation:
            tags.append(f"relation-{safe_tag(relation)}")
        if relationship_id:
            relationship_ids.append(relationship_id)
            tags.append(f"relationship-id-{safe_tag(relationship_id)}")

    case_ids: list[str] = []
    for case in cases:
        case_id = str(case.get("case_id") or "").strip()
        case_type = str(case.get("case_type") or "").strip()
        result = str(case.get("result") or "").strip()
        if case_id:
            case_ids.append(case_id)
            tags.append(f"case-id-{safe_tag(case_id)}")
        if case_type:
            tags.append(f"case-type-{safe_tag(case_type)}")
        if result:
            tags.append(f"case-result-{safe_tag(result)}")

    if kind == "discovery":
        for dependency in composition.get("depends_on") or []:
            tags.append(f"depends-on-{safe_tag(dependency)}")

    tags = list(dict.fromkeys(tags))
    relationship_ids = list(dict.fromkeys(relationship_ids))
    case_ids = list(dict.fromkeys(case_ids))

    lines = [
        "---",
        f"title: {q(str(row.get('name') or knowledge_id))}",
        f"gace_knowledge_id: {q(knowledge_id)}",
        f"gace_parent_asset_id: {q(asset_id)}",
        f"gace_knowledge_kind: {q(kind)}",
    ]
    if relationship_ids:
        lines.append("gace_relationship_ids:")
        lines.extend(f"  - {q(value)}" for value in relationship_ids)
    if case_ids:
        lines.append("gace_case_ids:")
        lines.extend(f"  - {q(value)}" for value in case_ids)
    lines.append("tags:")
    lines.extend(f"  - {q(tag)}" for tag in tags)
    if related_files:
        lines.append("related:")
        lines.extend(f"  - {q(name)}" for name in related_files)
    lines.extend(["---", ""])
    return "\n".join(lines)


def enrich(metadata_path: Path, corpus_dir: Path) -> int:
    metadata_path = metadata_path.resolve()
    corpus_dir = corpus_dir.resolve()
    rows = load_jsonl(metadata_path)
    global_relationships = load_optional_jsonl(metadata_path.parent / "relationships.jsonl", "RELATIONSHIP")
    global_cases = load_optional_jsonl(metadata_path.parent / "cases.jsonl", "CASE")
    files = sorted(corpus_dir.glob("*.md"))
    if len(files) != len(rows):
        raise RuntimeError(
            f"CORPUS_METADATA_COUNT_MISMATCH metadata={len(rows)} corpus={len(files)}"
        )

    unit_to_file: dict[str, str] = {}
    asset_to_preferred_file: dict[str, str] = {}
    source_owners: dict[tuple[str, str], set[str]] = {}
    explicit_contains_targets: dict[str, set[str]] = {}

    for row, path in zip(rows, files, strict=True):
        knowledge_id = str(row.get("knowledge_id") or "")
        asset_id = str(row.get("parent_asset_id") or "")
        if not knowledge_id or not asset_id:
            raise RuntimeError("CORPUS_METADATA_IDENTITY_MISSING")
        text = path.read_text(encoding="utf-8")
        if f"- Knowledge ID: {knowledge_id}" not in text:
            raise RuntimeError(
                f"CORPUS_METADATA_ORDER_MISMATCH file={path.name} id={knowledge_id}"
            )
        if knowledge_id in unit_to_file:
            raise RuntimeError(f"CORPUS_KNOWLEDGE_ID_DUPLICATE={knowledge_id}")
        unit_to_file[knowledge_id] = path.name
        if asset_id not in asset_to_preferred_file or row.get("knowledge_kind") == "discovery":
            asset_to_preferred_file[asset_id] = path.name
        for source_path in row.get("source_paths") or []:
            source_owners.setdefault((asset_id, str(source_path)), set()).add(knowledge_id)

    runtime_rows: list[dict[str, Any]] = []
    for row in rows:
        runtime_row = dict(row)
        runtime_row["relationships"] = runtime_relationships_for(row, global_relationships)
        runtime_row["cases"] = runtime_cases_for(row, global_cases, source_owners)
        runtime_rows.append(runtime_row)
        asset_id = str(row.get("parent_asset_id") or "")
        knowledge_id = str(row.get("knowledge_id") or "")
        for rel in runtime_row["relationships"]:
            if (
                str(rel.get("relation") or "") == "contains"
                and str(rel.get("from") or "") == asset_id
                and str(rel.get("to") or "") == knowledge_id
            ):
                explicit_contains_targets.setdefault(asset_id, set()).add(knowledge_id)

    written = 0
    relation_link_docs = 0
    dependency_link_docs = 0
    containment_link_docs = 0
    case_docs = 0
    for row, path in zip(runtime_rows, files, strict=True):
        current = path.read_text(encoding="utf-8")
        if current.startswith("---\n"):
            raise RuntimeError(f"CORPUS_FRONTMATTER_ALREADY_PRESENT={path.name}")

        related: list[str] = []
        relationship_added = False
        for rel in row.get("relationships") or []:
            source = str(rel.get("from") or "")
            target = str(rel.get("to") or "")
            knowledge_id = str(row.get("knowledge_id") or "")
            asset_id = str(row.get("parent_asset_id") or "")
            candidates: list[str] = []
            if source in {knowledge_id, asset_id} and target:
                candidates.append(target)
            if target in {knowledge_id, asset_id} and source:
                candidates.append(source)
            for candidate in candidates:
                filename = unit_to_file.get(candidate) or asset_to_preferred_file.get(candidate)
                if filename and filename != path.name:
                    related.append(filename)
                    relationship_added = True

        dependency_added = False
        containment_added = False
        if str(row.get("knowledge_kind") or "") == "discovery":
            asset_id = str(row.get("parent_asset_id") or "")
            composition = row.get("composition") if isinstance(row.get("composition"), dict) else {}
            for dependency in composition.get("depends_on") or []:
                filename = asset_to_preferred_file.get(str(dependency))
                if filename and filename != path.name:
                    related.append(filename)
                    dependency_added = True

            for target_id in sorted(explicit_contains_targets.get(asset_id, set())):
                filename = unit_to_file.get(target_id)
                if filename and filename != path.name:
                    related.append(filename)
                    containment_added = True

        related = list(dict.fromkeys(related))
        path.write_text(
            frontmatter_for(row, related) + current,
            encoding="utf-8",
            newline="\n",
        )
        written += 1
        relation_link_docs += int(relationship_added)
        dependency_link_docs += int(dependency_added)
        containment_link_docs += int(containment_added)
        case_docs += int(bool(row.get("cases")))

    print(
        f"GACE_MODULECATALOG_CORPUS_ENRICH=PASS RECORDS={written} "
        f"TAG={BASE_TAG} RELATION_LINK_DOCS={relation_link_docs} "
        f"DEPENDENCY_LINK_DOCS={dependency_link_docs} "
        f"CONTAINMENT_LINK_DOCS={containment_link_docs} "
        f"CASE_DOCS={case_docs} RELATIONSHIP_SIDECAR={len(global_relationships)} "
        f"CASE_SIDECAR={len(global_cases)}"
    )
    return written


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    args = parser.parse_args()
    enrich(args.metadata, args.corpus)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
