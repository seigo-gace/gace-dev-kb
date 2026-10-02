#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FIXTURE_SPEC = importlib.util.spec_from_file_location(
    "fixture_import_modulecatalog",
    ROOT / "tests" / "test_import_modulecatalog_reusable_export.py",
)
fixture_module = importlib.util.module_from_spec(FIXTURE_SPEC)
sys.modules[FIXTURE_SPEC.name] = fixture_module
FIXTURE_SPEC.loader.exec_module(fixture_module)

ACCEPT_SPEC = importlib.util.spec_from_file_location(
    "accept_modulecatalog_delivery",
    ROOT / "scripts" / "accept_modulecatalog_delivery.py",
)
accept_module = importlib.util.module_from_spec(ACCEPT_SPEC)
sys.path.insert(0, str(ROOT / "scripts"))
sys.modules[ACCEPT_SPEC.name] = accept_module
ACCEPT_SPEC.loader.exec_module(accept_module)


class AcceptModuleCatalogDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixture_module.ModuleCatalogReusableExportTests(
            methodName="test_imports_actual_single_asset_export"
        )
        self.fixture.setUp()
        entry = self.fixture.write_asset_bundle("asset-a", kind="logic")
        self.fixture.write_export([entry])
        self.accepted = self.fixture.tmp / "accepted" / self.fixture.commit
        self.receipt = self.fixture.tmp / "receipts" / f"{self.fixture.commit}.json"

    def tearDown(self):
        self.fixture.tearDown()

    def test_accepts_transport_and_builds_projection(self):
        receipt = accept_module.accept_delivery(
            self.fixture.export_root, self.accepted, self.receipt
        )
        self.assertEqual(receipt["status"], "ACCEPTED")
        self.assertEqual(receipt["assetCount"], 1)
        self.assertEqual(receipt["knowledgeUnitCount"], 1)
        state = json.loads((self.accepted / "state.json").read_text(encoding="utf-8"))
        self.assertEqual(state["catalogCommit"], self.fixture.commit)
        self.assertEqual(state["corpusCount"], 1)
        self.assertEqual(
            state["corpusRuntimeEnrichment"], "mvs-4.1.14-frontmatter-v1"
        )
        self.assertTrue((self.accepted / "projection" / "knowledge-records.jsonl").is_file())
        self.assertTrue((self.accepted / "projection" / "knowledge-metadata.jsonl").is_file())
        corpus_files = list((self.accepted / "projection" / "records").glob("*.md"))
        self.assertEqual(len(corpus_files), 1)
        corpus_text = corpus_files[0].read_text(encoding="utf-8")
        self.assertTrue(corpus_text.startswith("---\n"))
        self.assertIn('"gace-reusable-asset"', corpus_text)
        self.assertIn('"asset-asset-a"', corpus_text)
        self.assertIn('"knowledge-kind-logic"', corpus_text)

    def test_idempotent_accept_does_not_duplicate_projection(self):
        first = accept_module.accept_delivery(self.fixture.export_root, self.accepted, self.receipt)
        second = accept_module.accept_delivery(self.fixture.export_root, self.accepted, self.receipt)
        self.assertEqual(first["deliveryManifestSha256"], second["deliveryManifestSha256"])
        corpus_files = list((self.accepted / "projection" / "records").glob("*.md"))
        self.assertEqual(len(corpus_files), 1)
        self.assertEqual(corpus_files[0].read_text(encoding="utf-8").count("---\n"), 2)

    def test_active_receipt_is_not_downgraded(self):
        receipt = accept_module.accept_delivery(self.fixture.export_root, self.accepted, self.receipt)
        receipt["status"] = "ACTIVE"
        receipt["activatedAtUtc"] = "2026-10-01T00:00:00+00:00"
        self.receipt.write_text(json.dumps(receipt), encoding="utf-8")
        result = accept_module.accept_delivery(self.fixture.export_root, self.accepted, self.receipt)
        self.assertEqual(result["status"], "ACTIVE")
        self.assertEqual(result["activatedAtUtc"], "2026-10-01T00:00:00+00:00")

    def test_rejects_tampered_delivery_before_acceptance(self):
        target = self.fixture.export_root / "assets" / "asset-a" / "knowledge-units.jsonl"
        target.write_text(target.read_text(encoding="utf-8") + "{}\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "BUNDLE_MANIFEST_(SIZE|SHA256)_MISMATCH"):
            accept_module.accept_delivery(self.fixture.export_root, self.accepted, self.receipt)
        self.assertFalse(self.accepted.exists())
        self.assertFalse(self.receipt.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
