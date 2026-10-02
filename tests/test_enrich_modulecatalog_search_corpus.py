#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from enrich_modulecatalog_search_corpus import enrich  # noqa: E402


class ModuleCatalogSearchCorpusEnrichmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.metadata = self.root / "knowledge-metadata.jsonl"
        self.corpus = self.root / "records"
        self.corpus.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def row(
        asset_id: str,
        *,
        suffix: str = "overview",
        kind: str = "discovery",
        depends_on=None,
        relationships=None,
        cases=None,
        source_paths=None,
    ):
        return {
            "knowledge_id": f"{asset_id}::{suffix}",
            "parent_asset_id": asset_id,
            "knowledge_kind": kind,
            "name": f"{asset_id}-{suffix}",
            "classification": {
                "languages": ["JavaScript"],
                "runtimes": ["Node.js 22+"],
                "tags": ["skill"],
            },
            "verification": {"status": "verified"},
            "lifecycle": {"status": "active"},
            "composition": {"depends_on": depends_on or []},
            "relationships": relationships or [],
            "cases": cases or [],
            "source_paths": source_paths or [],
        }

    def write_fixture(self, rows):
        self.metadata.write_text(
            "\n".join(json.dumps(row) for row in rows) + "\n",
            encoding="utf-8",
        )
        for index, row in enumerate(rows, 1):
            (self.corpus / f"{index:04d}-{row['parent_asset_id']}-{row['knowledge_kind']}.md").write_text(
                f"# {row['parent_asset_id']}\n\n## Search Metadata\n\n"
                f"- Knowledge ID: {row['knowledge_id']}\n",
                encoding="utf-8",
            )

    def test_dependency_projects_to_tag_and_related_document(self):
        rows = [
            self.row("asset-a", depends_on=["asset-b"]),
            self.row("asset-b"),
        ]
        self.write_fixture(rows)
        self.assertEqual(enrich(self.metadata, self.corpus), 2)

        source = (self.corpus / "0001-asset-a-discovery.md").read_text(encoding="utf-8")
        self.assertIn('"depends-on-asset-b"', source)
        self.assertIn("related:\n  - \"0002-asset-b-discovery.md\"", source)

        target = (self.corpus / "0002-asset-b-discovery.md").read_text(encoding="utf-8")
        self.assertNotIn("depends-on-asset-a", target)

    def test_cross_unit_relationship_projects_to_related_document(self):
        relationship = {
            "relationship_id": "asset-a::related::asset-b",
            "from": "asset-a::overview",
            "relation": "related_to",
            "to": "asset-b::overview",
        }
        rows = [
            self.row("asset-a", relationships=[relationship]),
            self.row("asset-b"),
        ]
        self.write_fixture(rows)
        self.assertEqual(enrich(self.metadata, self.corpus), 2)

        source = (self.corpus / "0001-asset-a-discovery.md").read_text(encoding="utf-8")
        self.assertIn('"relation-related_to"', source)
        self.assertIn('"asset-a::related::asset-b"', source)
        self.assertIn("related:\n  - \"0002-asset-b-discovery.md\"", source)

    def test_explicit_contains_projects_discovery_to_child_document(self):
        contains = {
            "relationship_id": "asset-a::contains::asset-a::logic",
            "from": "asset-a",
            "relation": "contains",
            "to": "asset-a::logic",
        }
        rows = [
            self.row("asset-a"),
            self.row(
                "asset-a",
                suffix="logic",
                kind="logic",
                relationships=[contains],
            ),
        ]
        self.write_fixture(rows)
        self.assertEqual(enrich(self.metadata, self.corpus), 2)

        discovery = (self.corpus / "0001-asset-a-discovery.md").read_text(encoding="utf-8")
        child = (self.corpus / "0002-asset-a-logic.md").read_text(encoding="utf-8")
        self.assertIn("related:\n  - \"0002-asset-a-logic.md\"", discovery)
        self.assertIn('"relation-contains"', child)

    def test_full_sidecar_projects_asset_level_future_relationship(self):
        rows = [self.row("asset-a"), self.row("asset-b")]
        self.write_fixture(rows)
        relationship = {
            "schema_version": 1,
            "relationship_id": "asset-a::alternative_to::asset-b",
            "from": "asset-a",
            "relation": "alternative_to",
            "to": "asset-b",
            "verified": True,
        }
        (self.root / "relationships.jsonl").write_text(
            json.dumps(relationship) + "\n", encoding="utf-8"
        )

        self.assertEqual(enrich(self.metadata, self.corpus), 2)
        source = (self.corpus / "0001-asset-a-discovery.md").read_text(encoding="utf-8")
        target = (self.corpus / "0002-asset-b-discovery.md").read_text(encoding="utf-8")
        self.assertIn('"relation-alternative_to"', source)
        self.assertIn('"relationship-id-asset-a-alternative_to-asset-b"', source)
        self.assertIn('"asset-a::alternative_to::asset-b"', source)
        self.assertIn("related:\n  - \"0002-asset-b-discovery.md\"", source)
        self.assertIn('"relation-alternative_to"', target)

    def test_full_case_sidecar_projects_raw_case_id_to_matching_test_unit(self):
        rows = [
            self.row("asset-a"),
            self.row(
                "asset-a",
                suffix="normal-test",
                kind="test_case",
                source_paths=["tests/normal/example.test.cjs"],
            ),
        ]
        self.write_fixture(rows)
        case = {
            "schema_version": 1,
            "case_id": "asset-a::case::normal::example.test.cjs",
            "parent_asset_id": "asset-a",
            "case_type": "normal",
            "result": "PASS",
            "source_test": "tests/normal/example.test.cjs",
        }
        (self.root / "cases.jsonl").write_text(json.dumps(case) + "\n", encoding="utf-8")

        self.assertEqual(enrich(self.metadata, self.corpus), 2)
        discovery = (self.corpus / "0001-asset-a-discovery.md").read_text(encoding="utf-8")
        test_doc = (self.corpus / "0002-asset-a-test_case.md").read_text(encoding="utf-8")
        self.assertNotIn(case["case_id"], discovery)
        self.assertIn(case["case_id"], test_doc)
        self.assertIn('"case-type-normal"', test_doc)
        self.assertIn('"case-result-pass"', test_doc)

    def test_unmatched_case_falls_back_to_parent_discovery_document(self):
        rows = [self.row("asset-a")]
        self.write_fixture(rows)
        case = {
            "schema_version": 1,
            "case_id": "asset-a::case::user::external",
            "parent_asset_id": "asset-a",
            "case_type": "user",
            "result": "PASS",
            "source_test": "tests/user/not-a-unit.test.cjs",
        }
        (self.root / "cases.jsonl").write_text(json.dumps(case) + "\n", encoding="utf-8")
        self.assertEqual(enrich(self.metadata, self.corpus), 1)
        discovery = (self.corpus / "0001-asset-a-discovery.md").read_text(encoding="utf-8")
        self.assertIn(case["case_id"], discovery)

    def test_does_not_infer_contains_without_producer_relationship(self):
        rows = [
            self.row("asset-a"),
            self.row("asset-a", suffix="logic", kind="logic"),
        ]
        self.write_fixture(rows)
        self.assertEqual(enrich(self.metadata, self.corpus), 2)
        discovery = (self.corpus / "0001-asset-a-discovery.md").read_text(encoding="utf-8")
        self.assertNotIn("related:", discovery)


if __name__ == "__main__":
    unittest.main(verbosity=2)
