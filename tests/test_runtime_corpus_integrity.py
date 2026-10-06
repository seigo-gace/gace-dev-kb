#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from runtime_corpus_integrity import build_manifest  # noqa: E402


class RuntimeCorpusIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.records = self.root / "records"
        self.records.mkdir()
        self.prefix = "accepted-modulecatalog-reusable-aaaaaaaaaaaa-"

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name: str, content: str):
        (self.records / name).write_text(content, encoding="utf-8", newline="\n")

    def test_hashes_only_prefixed_runtime_files_deterministically(self):
        self.write(self.prefix + "0002-b.md", "beta\n")
        self.write(self.prefix + "0001-a.md", "alpha\n")
        self.write("repository-history.md", "unrelated\n")

        first = build_manifest(self.records, self.prefix, expected_count=2)
        second = build_manifest(self.records, self.prefix, expected_count=2)
        self.assertEqual(first, second)
        self.assertEqual(first["fileCount"], 2)
        self.assertEqual([row["name"] for row in first["files"]], [
            self.prefix + "0001-a.md",
            self.prefix + "0002-b.md",
        ])
        self.assertEqual(len(first["aggregateSha256"]), 64)

    def test_detects_runtime_markdown_drift(self):
        name = self.prefix + "0001-a.md"
        self.write(name, "alpha\n")
        before = build_manifest(self.records, self.prefix, expected_count=1)
        self.write(name, "tampered\n")
        after = build_manifest(self.records, self.prefix, expected_count=1)
        self.assertNotEqual(before["aggregateSha256"], after["aggregateSha256"])

    def test_rejects_wrong_expected_count(self):
        self.write(self.prefix + "0001-a.md", "alpha\n")
        with self.assertRaisesRegex(RuntimeError, "RUNTIME_CORPUS_FILE_COUNT_MISMATCH"):
            build_manifest(self.records, self.prefix, expected_count=2)

    def test_rejects_empty_matching_runtime_set(self):
        self.write("repository-history.md", "unrelated\n")
        with self.assertRaisesRegex(RuntimeError, "RUNTIME_CORPUS_EMPTY"):
            build_manifest(self.records, self.prefix)


if __name__ == "__main__":
    unittest.main(verbosity=2)
