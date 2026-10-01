#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "replace_modulecatalog_reusable_snapshot.py"
SPEC = importlib.util.spec_from_file_location("replace_modulecatalog_reusable_snapshot", MODULE_PATH)
module = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)


def record(*, type_: str, repository: str, commit: str, source: str) -> dict[str, str]:
    return {
        "type": type_,
        "repository": repository,
        "commit": commit,
        "summary": source,
        "cause": "",
        "fix": "",
        "validation": "verified",
        "source": source,
    }


class ReusableSnapshotReplaceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_replaces_only_reusable_snapshot_and_preserves_other_knowledge(self) -> None:
        current = [
            record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="history"),
            record(type_="implementation", repository="seigo-gace/modular-catalog", commit="s1", source="old-skill"),
            record(type_="reusable_asset", repository="seigo-gace/modular-catalog", commit="old", source="asset-a-old"),
            record(type_="reusable_asset", repository="seigo-gace/modular-catalog", commit="old", source="asset-b-old"),
        ]
        replacement = [
            record(type_="reusable_asset", repository="seigo-gace/modular-catalog", commit="new", source="asset-a-new"),
            record(type_="reusable_asset", repository="seigo-gace/modular-catalog", commit="new", source="asset-b-new"),
        ]

        combined, removed, base_count = module.replace_snapshot(current, replacement)

        self.assertEqual(removed, 2)
        self.assertEqual(base_count, 2)
        self.assertEqual(len(combined), 4)
        self.assertIn("history", {row["source"] for row in combined})
        self.assertIn("old-skill", {row["source"] for row in combined})
        self.assertNotIn("asset-a-old", {row["source"] for row in combined})
        self.assertIn("asset-a-new", {row["source"] for row in combined})

    def test_same_snapshot_is_idempotent(self) -> None:
        replacement = [
            record(type_="reusable_asset", repository="seigo-gace/modular-catalog", commit="same", source="asset-a"),
        ]
        current = [
            record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="history"),
            *replacement,
        ]

        combined, removed, base_count = module.replace_snapshot(current, replacement)

        self.assertEqual(removed, 1)
        self.assertEqual(base_count, 1)
        self.assertEqual(len(combined), 2)
        self.assertEqual(sum(1 for row in combined if row["source"] == "asset-a"), 1)

    def test_rejects_non_reusable_replacement(self) -> None:
        current = [record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="history")]
        replacement = [record(type_="implementation", repository="seigo-gace/modular-catalog", commit="new", source="wrong")]
        with self.assertRaisesRegex(RuntimeError, "REPLACEMENT_RECORD_NOT_MODULECATALOG_REUSABLE"):
            module.replace_snapshot(current, replacement)

    def test_rejects_duplicate_replacement_identity(self) -> None:
        current = [record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="history")]
        row = record(type_="reusable_asset", repository="seigo-gace/modular-catalog", commit="new", source="asset-a")
        with self.assertRaisesRegex(RuntimeError, "REPLACEMENT_RECORD_DUPLICATE"):
            module.replace_snapshot(current, [row, dict(row)])


if __name__ == "__main__":
    unittest.main(verbosity=2)
