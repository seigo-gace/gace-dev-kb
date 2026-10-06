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


class PreservedRuntimeCorpusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.current = self.root / "current"
        self.output = self.root / "output"
        self.current.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name: str, text: str) -> Path:
        path = self.current / name
        path.write_text(text, encoding="utf-8", newline="\n")
        return path

    def test_preserves_non_catalog_rich_docs_and_removes_all_catalog_generations(self):
        history = self.write(
            "0001-history.md",
            "# History\n\n- Source: `git:seigo-gace/gace-dev-kb@abc`\n\nRICH-HISTORY-BODY\n",
        )
        other_rich = self.write(
            "accepted-other-system-0001.md",
            "# Other Rich Asset\n\n- Source: `other:asset@1`\n\nDO-NOT-FLATTEN\n",
        )
        self.write(
            "accepted-debugai-code-repair-01.md",
            "# Legacy Catalog Trial\n\n- Source: `modulecatalog:seigo-gace/modular-catalog@old#assets/debugai::x`\n",
        )
        self.write(
            "accepted-modulecatalog-reusable-new-0001.md",
            "---\ntags:\n  - gace-reusable-asset\n---\n# Current Catalog\n",
        )

        preserved, removed = copy_preserved(self.current, self.output, expected_count=2)
        self.assertEqual(preserved, 2)
        self.assertEqual(removed, 2)
        self.assertEqual(
            (self.output / history.name).read_bytes(), history.read_bytes()
        )
        self.assertEqual(
            (self.output / other_rich.name).read_bytes(), other_rich.read_bytes()
        )
        self.assertFalse((self.output / "accepted-debugai-code-repair-01.md").exists())
        self.assertFalse((self.output / "accepted-modulecatalog-reusable-new-0001.md").exists())

    def test_count_mismatch_fails_closed_without_publishing_partial_output(self):
        self.write("0001-history.md", "# History\n")
        with self.assertRaisesRegex(RuntimeError, "PRESERVED_CORPUS_COUNT_MISMATCH"):
            copy_preserved(self.current, self.output, expected_count=2)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
