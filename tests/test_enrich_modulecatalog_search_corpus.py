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
    def row(asset_id: str, *, depends_on=None, relationships=None):
        return {
            "knowledge_id": f"{asset_id}::overview",
            "parent_asset_id": asset_id,
            "knowledge_kind": "discovery",
            "name": asset_id,
            "classification": {
                "languages": ["JavaScript"],
                "runtimes": ["Node.js 22+"],
                "tags": ["skill"],
            },
            "verification": {"status": "verified"},
            "lifecycle": {"status": "active"},
            "composition": {"depends_on": depends_on or []},
            "relationships": relationships or [],
        }

    def write_fixture(self, rows):
        self.metadata.write_text(
            "\n".join(json.dumps(row) for row in rows) + "\n",
            encoding="utf-8",
        )
        for index, row in enumerate(rows, 1):
            (self.corpus / f"{index:04d}-{row['parent_asset_id']}.md").write_text(
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

        source = (self.corpus / "0001-asset-a.md").read_text(encoding="utf-8")
        self.assertIn('"depends-on-asset-b"', source)
        self.assertIn("related:\n  - \"0002-asset-b.md\"", source)

        target = (self.corpus / "0002-asset-b.md").read_text(encoding="utf-8")
        self.assertNotIn("depends-on-asset-a", target)

    def test_cross_unit_relationship_projects_to_tag_and_related_document(self):
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

        source = (self.corpus / "0001-asset-a.md").read_text(encoding="utf-8")
        self.assertIn('"relation-related_to"', source)
        self.assertIn("related:\n  - \"0002-asset-b.md\"", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
