#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
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

    def test_replaces_all_modulecatalog_asset_projections_and_preserves_history(self) -> None:
        current = [
            record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="git:history"),
            record(
                type_="implementation",
                repository="seigo-gace/modular-catalog",
                commit="legacy",
                source="modulecatalog:seigo-gace/modular-catalog@legacy#assets/debugai-pack/source/index.js::skillA",
            ),
            record(
                type_="reusable_asset",
                repository="seigo-gace/modular-catalog",
                commit="old",
                source="modulecatalog:seigo-gace/modular-catalog@old#assets/asset-a::unit-a",
            ),
            # Ordinary repository-history knowledge about ModuleCatalog is not an
            # accepted asset projection and must survive snapshot replacement.
            record(
                type_="fix",
                repository="seigo-gace/modular-catalog",
                commit="hist",
                source="git:seigo-gace/modular-catalog@hist",
            ),
        ]
        replacement = [
            record(
                type_="reusable_asset",
                repository="seigo-gace/modular-catalog",
                commit="new",
                source="modulecatalog:seigo-gace/modular-catalog@new#assets/asset-a::unit-a",
            ),
            record(
                type_="reusable_asset",
                repository="seigo-gace/modular-catalog",
                commit="new",
                source="modulecatalog:seigo-gace/modular-catalog@new#assets/asset-b::unit-b",
            ),
        ]

        combined, removed, base_count = module.replace_snapshot(current, replacement)

        self.assertEqual(removed, 2)
        self.assertEqual(base_count, 2)
        self.assertEqual(len(combined), 4)
        sources = {row["source"] for row in combined}
        self.assertIn("git:history", sources)
        self.assertIn("git:seigo-gace/modular-catalog@hist", sources)
        self.assertFalse(any("debugai-pack" in source for source in sources))
        self.assertFalse(any("@old#assets/asset-a" in source for source in sources))
        self.assertTrue(any("@new#assets/asset-a" in source for source in sources))

    def test_same_snapshot_is_idempotent(self) -> None:
        replacement = [
            record(
                type_="reusable_asset",
                repository="seigo-gace/modular-catalog",
                commit="same",
                source="modulecatalog:seigo-gace/modular-catalog@same#assets/asset-a::unit-a",
            ),
        ]
        current = [
            record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="git:history"),
            *replacement,
        ]

        combined, removed, base_count = module.replace_snapshot(current, replacement)

        self.assertEqual(removed, 1)
        self.assertEqual(base_count, 1)
        self.assertEqual(len(combined), 2)
        self.assertEqual(sum(1 for row in combined if "asset-a::unit-a" in row["source"]), 1)

    def test_rejects_non_reusable_replacement(self) -> None:
        current = [record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="git:history")]
        replacement = [
            record(
                type_="implementation",
                repository="seigo-gace/modular-catalog",
                commit="new",
                source="modulecatalog:seigo-gace/modular-catalog@new#assets/wrong",
            )
        ]
        with self.assertRaisesRegex(RuntimeError, "REPLACEMENT_RECORD_NOT_MODULECATALOG_REUSABLE"):
            module.replace_snapshot(current, replacement)

    def test_rejects_replacement_without_modulecatalog_source_scheme(self) -> None:
        current = [record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="git:history")]
        replacement = [
            record(
                type_="reusable_asset",
                repository="seigo-gace/modular-catalog",
                commit="new",
                source="git:seigo-gace/modular-catalog@new",
            )
        ]
        with self.assertRaisesRegex(RuntimeError, "REPLACEMENT_RECORD_NOT_MODULECATALOG_REUSABLE"):
            module.replace_snapshot(current, replacement)

    def test_rejects_duplicate_replacement_identity(self) -> None:
        current = [record(type_="implementation", repository="seigo-gace/gace-dev-kb", commit="h1", source="git:history")]
        row = record(
            type_="reusable_asset",
            repository="seigo-gace/modular-catalog",
            commit="new",
            source="modulecatalog:seigo-gace/modular-catalog@new#assets/asset-a::unit-a",
        )
        with self.assertRaisesRegex(RuntimeError, "REPLACEMENT_RECORD_DUPLICATE"):
            module.replace_snapshot(current, [row, dict(row)])


if __name__ == "__main__":
    unittest.main(verbosity=2)
