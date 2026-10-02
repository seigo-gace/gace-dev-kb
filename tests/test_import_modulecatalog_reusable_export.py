#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "import_modulecatalog_reusable_export.py"
SPEC = importlib.util.spec_from_file_location("import_modulecatalog_reusable_export", MODULE_PATH)
module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class ModuleCatalogReusableExportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="gace-reusable-export-test-"))
        self.export_root = self.tmp / "export"
        self.output_root = self.tmp / "output"
        self.commit = "a" * 40
        self.export_root.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def asset(self, asset_id: str, *, verified: bool = True, kind: str = "capability"):
        return {
            "schema_version": 1,
            "identity": {
                "asset_id": asset_id,
                "name": asset_id.replace("-", " ").title(),
                "version": "1.0.0",
                "asset_kind": kind,
                "symbol": None,
            },
            "classification": {
                "domains": [],
                "layers": ["Part"],
                "languages": ["JavaScript"],
                "runtimes": ["Node.js 22+"],
                "tags": ["fixture"],
            },
            "discovery": {
                "summary": f"Reusable {asset_id} summary",
                "purpose": f"Reuse {asset_id}",
                "responsibility": f"Provide {asset_id}",
                "capabilities": [],
                "keywords": [asset_id, "reusable"],
                "semantic_terms": [],
            },
            "applicability": {
                "use_when": [],
                "do_not_use_when": [],
                "preconditions": [],
                "required_context": [],
                "failure_conditions": [],
            },
            "contract": {
                "status": "unknown",
                "inputs": [],
                "outputs": [],
                "required_fields": [],
                "optional_fields": [],
                "error_behavior": None,
                "side_effects": None,
                "mutation_authority": None,
            },
            "composition": {
                "depends_on": [],
                "requires": [],
                "recommended_before": [],
                "recommended_after": [],
                "complements": [],
                "alternative_to": [],
                "conflicts_with": [],
                "supersedes": [],
            },
            "implementation": {
                "languages": ["JavaScript"],
                "runtimes": ["Node.js 22+"],
                "entrypoints": ["source/index.js"],
                "source_files": ["source/index.js"],
                "dependencies": [],
            },
            "verification": {
                "status": "verified" if verified else "unknown",
                "normal_test": {"passed": True},
                "user_test": {"passed": True},
                "verified_at": "2026-10-01T00:00:00Z",
                "validation_boundary": "fixture verification only",
                "known_unverified": [],
            },
            "provenance": {
                "origin": {"repository": "local://fixture", "commit": "origin-1"},
                "catalog": {
                    "repository": "seigo-gace/modular-catalog",
                    "commit": self.commit,
                    "asset_path": f"assets/{asset_id}",
                    "asset_id": asset_id,
                },
            },
            "lifecycle": {
                "status": "verified",
                "introduced_version": "1.0.0",
                "deprecated_at": None,
                "superseded_by": None,
            },
            "integrity": {
                "asset_hash": f"asset-hash-{asset_id}",
                "meta_hash": f"meta-hash-{asset_id}",
                "manifest_algorithm": "sha256",
                "files": [],
            },
            "derivation": {"canonical_sources": ["meta.json"], "derived_fields": []},
        }

    def unit(self, asset_id: str, kind: str = "logic"):
        return {
            "schema_version": 1,
            "knowledge_id": f"{asset_id}::{kind}",
            "parent_asset_id": asset_id,
            "knowledge_kind": kind,
            "title": f"{asset_id} {kind}",
            "content": f"Reusable {kind} content for {asset_id}",
            "source_paths": [f"{kind}.md"],
            "content_status": "recorded",
            "derivation": {
                "type": "canonical-projection",
                "derived_from": [f"{kind}.md"],
                "verified": True,
            },
        }

    def case(self, asset_id: str):
        return {
            "schema_version": 1,
            "case_id": f"{asset_id}::case::normal::fixture.test.cjs",
            "parent_asset_id": asset_id,
            "case_type": "normal",
            "scenario": None,
            "input": None,
            "expected": ["all assertions pass"],
            "actual": None,
            "result": "PASS",
            "source_test": "tests/normal/fixture.test.cjs",
            "test_content": "assert.equal(1, 1)",
            "extraction_status": "source-reference-only",
            "derivation": {
                "type": "canonical-projection",
                "derived_from": ["tests/normal/fixture.test.cjs", "evidence.json#/normal"],
                "verified": True,
            },
        }

    def write_asset_bundle(self, asset_id: str, *, verified: bool = True, kind: str = "logic"):
        asset_dir = self.export_root / "assets" / asset_id
        asset_dir.mkdir(parents=True)
        asset = self.asset(asset_id, verified=verified)
        unit = self.unit(asset_id, kind)
        relationship = {
            "schema_version": 1,
            "relationship_id": f"{asset_id}::contains::{unit['knowledge_id']}",
            "from": asset_id,
            "relation": "contains",
            "to": unit["knowledge_id"],
            "verified": True,
            "derivation": {"type": "canonical-projection", "derived_from": unit["source_paths"]},
        }
        case = self.case(asset_id)

        (asset_dir / "asset.json").write_text(json.dumps(asset, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        (asset_dir / "knowledge-units.jsonl").write_text(json.dumps(unit, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
        (asset_dir / "relationships.jsonl").write_text(json.dumps(relationship, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
        (asset_dir / "cases.jsonl").write_text(json.dumps(case, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")

        files = []
        for rel in ("asset.json", "knowledge-units.jsonl", "relationships.jsonl", "cases.jsonl"):
            path = asset_dir / rel
            files.append({"path": rel, "size": path.stat().st_size, "sha256": sha256_bytes(path.read_bytes())})
        bundle_hash = sha256_bytes(canonical_json(files).encode("utf-8"))
        manifest = {
            "schema_version": 1,
            "format": "gace.reusable-asset.v1",
            "asset_id": asset_id,
            "catalog": {
                "repository": "seigo-gace/modular-catalog",
                "commit": self.commit,
                "asset_path": f"assets/{asset_id}",
            },
            "source_asset_hash": asset["integrity"]["asset_hash"],
            "bundle_hash": bundle_hash,
            "algorithm": "sha256",
            "files": files,
        }
        (asset_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        return {
            "id": asset_id,
            "assetHash": asset["integrity"]["asset_hash"],
            "bundleHash": bundle_hash,
            "knowledgeUnits": 1,
            "relationships": 1,
            "cases": 1,
        }

    def write_export(self, entries):
        manifest = {
            "schema_version": 1,
            "format": "gace.reusable-asset.v1",
            "catalog": {"repository": "seigo-gace/modular-catalog", "commit": self.commit},
            "generatedAt": "2026-10-01T00:00:00.000Z",
            "assetCount": len(entries),
            "assets": entries,
        }
        (self.export_root / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    def test_imports_actual_single_asset_export(self):
        entry = self.write_asset_bundle("asset-a", kind="logic")
        self.write_export([entry])
        records, metadata, corpus, asset_count = module.import_export(
            self.export_root,
            self.output_root,
            expected_catalog_commit=self.commit,
            expected_asset_count=1,
            expected_record_count=1,
        )
        self.assertEqual(asset_count, 1)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].type, "reusable_asset")
        self.assertEqual(metadata[0]["knowledge_kind"], "logic")
        self.assertEqual(metadata[0]["parent_asset_id"], "asset-a")
        self.assertEqual(metadata[0]["identity"], self.asset("asset-a")["identity"])
        self.assertEqual(metadata[0]["verification"]["status"], "verified")
        self.assertIn("files", metadata[0]["integrity"])
        self.assertEqual(metadata[0]["integrity"]["files"], [])
        self.assertEqual(metadata[0]["integrity"]["bundle_hash"], entry["bundleHash"])
        text = next(corpus.glob("*.md")).read_text(encoding="utf-8")
        self.assertIn("Reusable logic content for asset-a", text)
        self.assertIn("Knowledge Kind: logic", text)
        self.assertTrue((self.output_root / "knowledge-records.jsonl").is_file())
        self.assertTrue((self.output_root / "knowledge-metadata.jsonl").is_file())

    def test_imports_multi_asset_export(self):
        a = self.write_asset_bundle("asset-a", kind="logic")
        b = self.write_asset_bundle("asset-b", kind="architecture")
        self.write_export([a, b])
        records, metadata, _, asset_count = module.import_export(
            self.export_root,
            self.output_root,
            expected_catalog_commit=self.commit,
            expected_asset_count=2,
            expected_record_count=2,
        )
        self.assertEqual(asset_count, 2)
        self.assertEqual(len(records), 2)
        self.assertEqual({row["knowledge_kind"] for row in metadata}, {"logic", "architecture"})

    def test_rejects_bundle_file_tamper(self):
        entry = self.write_asset_bundle("asset-a")
        self.write_export([entry])
        path = self.export_root / "assets" / "asset-a" / "knowledge-units.jsonl"
        path.write_text(path.read_text(encoding="utf-8") + "{}\n", encoding="utf-8", newline="\n")
        with self.assertRaisesRegex(RuntimeError, "BUNDLE_MANIFEST_(SIZE|SHA256)_MISMATCH"):
            module.import_export(self.export_root, self.output_root)

    def test_rejects_unverified_asset(self):
        entry = self.write_asset_bundle("asset-a", verified=False)
        self.write_export([entry])
        with self.assertRaisesRegex(RuntimeError, "ASSET_NOT_VERIFIED"):
            module.import_export(self.export_root, self.output_root)

    def test_rejects_catalog_commit_mismatch(self):
        entry = self.write_asset_bundle("asset-a")
        self.write_export([entry])
        with self.assertRaisesRegex(RuntimeError, "TOP_MANIFEST_COMMIT_MISMATCH"):
            module.import_export(
                self.export_root,
                self.output_root,
                expected_catalog_commit="b" * 40,
            )

    def test_rejects_unknown_relationship_target(self):
        entry = self.write_asset_bundle("asset-a")
        rel_path = self.export_root / "assets" / "asset-a" / "relationships.jsonl"
        rel = json.loads(rel_path.read_text(encoding="utf-8"))
        rel["to"] = "missing-node"
        rel_path.write_text(json.dumps(rel) + "\n", encoding="utf-8", newline="\n")
        asset_dir = rel_path.parent
        manifest = json.loads((asset_dir / "manifest.json").read_text(encoding="utf-8"))
        files = []
        for item in manifest["files"]:
            p = asset_dir / item["path"]
            files.append({"path": item["path"], "size": p.stat().st_size, "sha256": sha256_bytes(p.read_bytes())})
        manifest["files"] = files
        manifest["bundle_hash"] = sha256_bytes(canonical_json(files).encode("utf-8"))
        (asset_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
        entry["bundleHash"] = manifest["bundle_hash"]
        self.write_export([entry])
        with self.assertRaisesRegex(RuntimeError, "RELATIONSHIP_TARGET_UNKNOWN"):
            module.import_export(self.export_root, self.output_root)


if __name__ == "__main__":
    unittest.main(verbosity=2)
