#!/usr/bin/env python3
"""Enrich accepted ModuleCatalog Markdown projection for the existing KB runtime.

The transported bundle remains canonical and untouched. This operates only on the
local derived Markdown corpus, adding deterministic YAML frontmatter that the
installed mcp-vector-search 4.1.14 runtime can use for DocSection tags and
cross-document links in its Knowledge Graph.
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


def safe_tag(value: Any) -> str:
    text = str(value or "unknown").strip().lower()
    text = re.sub(r"[^0-9a-z._-]+", "-", text).strip("-")
    return text or "unknown"


def q(value: str) -> str:
    # JSON double-quoted strings are valid YAML scalars and avoid colon/hash issues.
    return json.dumps(value, ensure_ascii=False)


def frontmatter_for(row: dict[str, Any], related_files: list[str]) -> str:
    asset_id = str(row.get("parent_asset_id") or "")
    knowledge_id = str(row.get("knowledge_id") or "")
    kind = str(row.get("knowledge_kind") or "unknown")
    lifecycle = row.get("lifecycle") if isinstance(row.get("lifecycle"), dict) else {}
    verification = row.get("verification") if isinstance(row.get("verification"), dict) else {}
    classification = (
        row.get("classification") if isinstance(row.get("classification"), dict) else {}
    )
    composition = row.get("composition") if isinstance(row.get("composition"), dict) else {}
    if not asset_id or not knowledge_id:
        raise RuntimeError("CORPUS_FRONTMATTER_IDENTITY_MISSING")

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

    # Asset-level dependency semantics are canonical Catalog data. Project them
    # only on the discovery document so the existing MVS KG gets one stable
    # relationship-bearing node per Asset instead of duplicating the edge across
    # every code/design/test Knowledge Unit.
    if kind == "discovery":
        for dependency in composition.get("depends_on") or []:
            tags.append(f"depends-on-{safe_tag(dependency)}")

    tags = list(dict.fromkeys(tags))

    lines = [
        "---",
        f"title: {q(str(row.get('name') or knowledge_id))}",
        f"gace_knowledge_id: {q(knowledge_id)}",
        f"gace_parent_asset_id: {q(asset_id)}",
        f"gace_knowledge_kind: {q(kind)}",
        "tags:",
    ]
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
    files = sorted(corpus_dir.glob("*.md"))
    if len(files) != len(rows):
        raise RuntimeError(
            f"CORPUS_METADATA_COUNT_MISMATCH metadata={len(rows)} corpus={len(files)}"
        )

    unit_to_file: dict[str, str] = {}
    asset_to_preferred_file: dict[str, str] = {}
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

    written = 0
    relation_link_docs = 0
    dependency_link_docs = 0
    for row, path in zip(rows, files, strict=True):
        current = path.read_text(encoding="utf-8")
        if current.startswith("---\n"):
            raise RuntimeError(f"CORPUS_FRONTMATTER_ALREADY_PRESENT={path.name}")

        related: list[str] = []
        relationship_added = False
        for rel in row.get("relationships") or []:
            if not isinstance(rel, dict):
                continue
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
        if str(row.get("knowledge_kind") or "") == "discovery":
            composition = row.get("composition") if isinstance(row.get("composition"), dict) else {}
            for dependency in composition.get("depends_on") or []:
                filename = asset_to_preferred_file.get(str(dependency))
                if filename and filename != path.name:
                    related.append(filename)
                    dependency_added = True

        related = list(dict.fromkeys(related))
        path.write_text(
            frontmatter_for(row, related) + current,
            encoding="utf-8",
            newline="\n",
        )
        written += 1
        relation_link_docs += int(relationship_added)
        dependency_link_docs += int(dependency_added)

    print(
        f"GACE_MODULECATALOG_CORPUS_ENRICH=PASS RECORDS={written} "
        f"TAG={BASE_TAG} RELATION_LINK_DOCS={relation_link_docs} "
        f"DEPENDENCY_LINK_DOCS={dependency_link_docs}"
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
