#!/usr/bin/env python3
"""Accept a transported ModuleCatalog KB export at the G-ACE KB boundary.

This is the operational producer/consumer boundary. ModuleCatalog owns creation,
search-ready enrichment, verification and transport. G-ACE KB starts here: it
verifies the delivered bundle, builds the local searchable projection, and emits
an acceptance receipt for the downstream activation/indexing pipeline.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from enrich_modulecatalog_search_corpus import enrich as enrich_search_corpus
from import_modulecatalog_reusable_export import FORMAT, CATALOG_REPOSITORY, import_export


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON_OBJECT_REQUIRED={path}")
    return value


def write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    temp.replace(path)


def derive_counts(manifest: dict[str, Any]) -> tuple[str, int, int, int, int]:
    if manifest.get("schema_version") != 1 or manifest.get("format") != FORMAT:
        raise RuntimeError("DELIVERY_MANIFEST_FORMAT_UNSUPPORTED")
    catalog = manifest.get("catalog")
    if not isinstance(catalog, dict):
        raise RuntimeError("DELIVERY_CATALOG_MISSING")
    if str(catalog.get("repository") or "") != CATALOG_REPOSITORY:
        raise RuntimeError("DELIVERY_CATALOG_REPOSITORY_MISMATCH")
    commit = str(catalog.get("commit") or "")
    if len(commit) != 40:
        raise RuntimeError(f"DELIVERY_CATALOG_COMMIT_INVALID={commit}")
    assets = manifest.get("assets")
    if not isinstance(assets, list) or not assets:
        raise RuntimeError("DELIVERY_ASSETS_EMPTY")
    asset_count = int(manifest.get("assetCount", -1))
    if asset_count != len(assets):
        raise RuntimeError(
            f"DELIVERY_ASSET_COUNT_MISMATCH declared={asset_count} actual={len(assets)}"
        )
    record_count = 0
    relationship_count = 0
    case_count = 0
    for item in assets:
        if not isinstance(item, dict):
            raise RuntimeError("DELIVERY_ASSET_ENTRY_INVALID")
        record_count += int(item.get("knowledgeUnits", -1))
        relationship_count += int(item.get("relationships", -1))
        case_count += int(item.get("cases", -1))
    if min(record_count, relationship_count, case_count) < 0:
        raise RuntimeError("DELIVERY_DECLARED_COUNT_INVALID")
    return commit, asset_count, record_count, relationship_count, case_count


def receipt_payload(
    *,
    status: str,
    commit: str,
    asset_count: int,
    record_count: int,
    relationship_count: int,
    case_count: int,
    manifest_hash: str,
    accepted_root: Path,
    records_hash: str | None = None,
    metadata_hash: str | None = None,
    corpus_count: int | None = None,
    prior: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "schemaVersion": 1,
        "status": status,
        "catalogRepository": CATALOG_REPOSITORY,
        "catalogCommit": commit,
        "assetCount": asset_count,
        "knowledgeUnitCount": record_count,
        "relationshipCount": relationship_count,
        "caseCount": case_count,
        "deliveryManifestSha256": manifest_hash,
        "acceptedRoot": str(accepted_root),
        "acceptedAtUtc": datetime.now(timezone.utc).isoformat(),
    }
    if records_hash:
        payload["knowledgeRecordsSha256"] = records_hash
    if metadata_hash:
        payload["knowledgeMetadataSha256"] = metadata_hash
    if corpus_count is not None:
        payload["corpusCount"] = corpus_count
    if prior and prior.get("status") == "ACTIVE":
        for key, value in prior.items():
            if key not in {"acceptedAtUtc"}:
                payload[key] = value
        payload["status"] = "ACTIVE"
    return payload


def accept_delivery(
    delivery_root: Path,
    accepted_root: Path,
    receipt_path: Path,
) -> dict[str, Any]:
    delivery_root = delivery_root.resolve()
    accepted_root = accepted_root.resolve()
    receipt_path = receipt_path.resolve()
    manifest_path = delivery_root / "manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"DELIVERY_MANIFEST_MISSING={manifest_path}")

    manifest = read_json(manifest_path)
    commit, asset_count, record_count, relationship_count, case_count = derive_counts(manifest)
    manifest_hash = sha256_file(manifest_path)

    prior_receipt: dict[str, Any] | None = None
    if receipt_path.is_file():
        prior_receipt = read_json(receipt_path)
        if (
            str(prior_receipt.get("catalogCommit") or "") == commit
            and str(prior_receipt.get("deliveryManifestSha256") or "") == manifest_hash
            and prior_receipt.get("status") == "ACTIVE"
        ):
            print(
                "GACE_MODULECATALOG_DELIVERY_ACCEPT=PASS IDEMPOTENT=YES "
                f"STATUS=ACTIVE COMMIT={commit} ASSETS={asset_count} RECORDS={record_count}"
            )
            return prior_receipt

    if accepted_root.exists():
        state_path = accepted_root / "state.json"
        if not state_path.is_file():
            raise RuntimeError(f"ACCEPTED_ROOT_CONFLICT_NO_STATE={accepted_root}")
        state = read_json(state_path)
        if (
            str(state.get("catalogCommit") or "") != commit
            or str(state.get("deliveryManifestSha256") or "") != manifest_hash
        ):
            raise RuntimeError(f"ACCEPTED_ROOT_CONFLICT={accepted_root}")
        receipt = receipt_payload(
            status="ACCEPTED",
            commit=commit,
            asset_count=asset_count,
            record_count=record_count,
            relationship_count=relationship_count,
            case_count=case_count,
            manifest_hash=manifest_hash,
            accepted_root=accepted_root,
            records_hash=str(state.get("knowledgeRecordsSha256") or ""),
            metadata_hash=str(state.get("knowledgeMetadataSha256") or ""),
            corpus_count=int(state.get("corpusCount", record_count)),
            prior=prior_receipt,
        )
        write_json_atomic(receipt_path, receipt)
        print(
            "GACE_MODULECATALOG_DELIVERY_ACCEPT=PASS IDEMPOTENT=YES "
            f"STATUS={receipt['status']} COMMIT={commit} ASSETS={asset_count} RECORDS={record_count}"
        )
        return receipt

    accepted_root.parent.mkdir(parents=True, exist_ok=True)
    temp_parent = accepted_root.parent
    temp_dir = Path(tempfile.mkdtemp(prefix=f".{accepted_root.name}.accept-", dir=temp_parent))
    try:
        projection = temp_dir / "projection"
        records, metadata, corpus, imported_asset_count = import_export(
            delivery_root,
            projection,
            expected_catalog_commit=commit,
            expected_asset_count=asset_count,
            expected_record_count=record_count,
        )
        if imported_asset_count != asset_count or len(records) != record_count or len(metadata) != record_count:
            raise RuntimeError("DELIVERY_IMPORT_CARDINALITY_MISMATCH")

        records_path = projection / "knowledge-records.jsonl"
        metadata_path = projection / "knowledge-metadata.jsonl"
        enriched_count = enrich_search_corpus(metadata_path, corpus)
        if enriched_count != record_count:
            raise RuntimeError(
                f"DELIVERY_CORPUS_ENRICH_COUNT_MISMATCH expected={record_count} actual={enriched_count}"
            )

        corpus_count = len(list(corpus.glob("*.md")))
        if corpus_count != record_count:
            raise RuntimeError(
                f"DELIVERY_CORPUS_COUNT_MISMATCH expected={record_count} actual={corpus_count}"
            )

        state = {
            "schemaVersion": 1,
            "status": "ACCEPTED",
            "catalogRepository": CATALOG_REPOSITORY,
            "catalogCommit": commit,
            "assetCount": asset_count,
            "knowledgeUnitCount": record_count,
            "relationshipCount": relationship_count,
            "caseCount": case_count,
            "corpusCount": corpus_count,
            "corpusRuntimeEnrichment": "mvs-4.1.14-frontmatter-v1",
            "deliveryManifestSha256": manifest_hash,
            "knowledgeRecordsSha256": sha256_file(records_path),
            "knowledgeMetadataSha256": sha256_file(metadata_path),
            "acceptedAtUtc": datetime.now(timezone.utc).isoformat(),
        }
        write_json_atomic(temp_dir / "state.json", state)
        shutil.copy2(manifest_path, temp_dir / "delivery-manifest.json")
        temp_dir.replace(accepted_root)
    except BaseException:
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise

    state = read_json(accepted_root / "state.json")
    receipt = receipt_payload(
        status="ACCEPTED",
        commit=commit,
        asset_count=asset_count,
        record_count=record_count,
        relationship_count=relationship_count,
        case_count=case_count,
        manifest_hash=manifest_hash,
        accepted_root=accepted_root,
        records_hash=str(state["knowledgeRecordsSha256"]),
        metadata_hash=str(state["knowledgeMetadataSha256"]),
        corpus_count=int(state["corpusCount"]),
        prior=prior_receipt,
    )
    write_json_atomic(receipt_path, receipt)
    print(
        "GACE_MODULECATALOG_DELIVERY_ACCEPT=PASS IDEMPOTENT=NO "
        f"STATUS={receipt['status']} COMMIT={commit} ASSETS={asset_count} "
        f"RECORDS={record_count} CASES={case_count}"
    )
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--delivery-root", type=Path, required=True)
    parser.add_argument("--accepted-root", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    accept_delivery(args.delivery_root, args.accepted_root, args.receipt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
