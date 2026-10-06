#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from copy_preserved_kb_runtime_corpus import copy_preserved  # noqa: E402
from replace_modulecatalog_reusable_snapshot import replace_snapshot  # noqa: E402


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


class ModuleCatalogSnapshotTransitionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.current_corpus = self.root / "current-records"
        self.staging_corpus = self.root / "staging-records"
        self.current_corpus.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def test_94_base_plus_legacy_13_becomes_94_base_plus_720_current(self):
        base = [
            record(
                type_="fix",
                repository="seigo-gace/gace-dev-kb",
                commit=f"base-{index:03d}",
                source=f"git:history:{index:03d}",
            )
            for index in range(94)
        ]
        legacy = [
            record(
                type_="implementation",
                repository="seigo-gace/modular-catalog",
                commit="legacy",
                source=(
                    "modulecatalog:seigo-gace/modular-catalog@legacy"
                    f"#assets/debugai-pack/source/index.js::skill{index:02d}"
                ),
            )
            for index in range(13)
        ]
        replacement = [
            record(
                type_="reusable_asset",
                repository="seigo-gace/modular-catalog",
                commit="new",
                source=(
                    "modulecatalog:seigo-gace/modular-catalog@new"
                    f"#assets/asset-{index:03d}::unit-{index:03d}"
                ),
            )
            for index in range(720)
        ]

        current = base + legacy
        combined, removed, base_count = replace_snapshot(current, replacement)
        self.assertEqual(len(current), 107)
        self.assertEqual(removed, 13)
        self.assertEqual(base_count, 94)
        self.assertEqual(len(combined), 814)
        self.assertFalse(any(row["commit"] == "legacy" for row in combined))
        self.assertEqual(sum(row["commit"] == "new" for row in combined), 720)

        # The pre-existing runtime corpus follows the same 94 + 13 shape. Base
        # documents include a marker that proves rich content is byte-preserved.
        for index, row in enumerate(base, start=1):
            (self.current_corpus / f"{index:04d}-base.md").write_text(
                f"# Base {index}\n\n- Source: `{row['source']}`\n\nRICH-{index:03d}\n",
                encoding="utf-8",
            )
        for index, row in enumerate(legacy, start=1):
            (self.current_corpus / f"accepted-debugai-{index:02d}.md").write_text(
                f"# Legacy {index}\n\n- Source: `{row['source']}`\n",
                encoding="utf-8",
            )

        preserved, removed_corpus = copy_preserved(
            self.current_corpus,
            self.staging_corpus,
            expected_count=94,
        )
        self.assertEqual(preserved, 94)
        self.assertEqual(removed_corpus, 13)
        self.assertEqual(len(list(self.staging_corpus.glob("*.md"))), 94)
        self.assertIn(
            "RICH-001",
            (self.staging_corpus / "0001-base.md").read_text(encoding="utf-8"),
        )
        self.assertFalse(any("accepted-debugai" in path.name for path in self.staging_corpus.glob("*.md")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
