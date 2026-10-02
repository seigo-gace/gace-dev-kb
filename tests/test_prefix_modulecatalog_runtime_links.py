#!/usr/bin/env python3
from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from prefix_modulecatalog_runtime_links import rewrite  # noqa: E402
from verify_modulecatalog_runtime_projection import verify_projection  # noqa: E402


class PrefixModuleCatalogRuntimeLinksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.corpus = Path(self.temp.name)
        self.prefix = "accepted-modulecatalog-reusable-123456789abc-"

    def tearDown(self):
        self.temp.cleanup()

    def write_doc(self, name: str, related: list[str]):
        lines = ["---", f'title: "{name}"', "related:"]
        lines.extend(f'  - "{target}"' for target in related)
        lines.extend(["---", "", f"# {name}", ""])
        (self.corpus / name).write_text("\n".join(lines), encoding="utf-8")

    def test_prefixes_related_targets_once(self):
        self.write_doc("0001-a.md", ["0002-b.md"])
        self.write_doc("0002-b.md", [])

        self.assertEqual(rewrite(self.corpus, self.prefix), 1)
        text = (self.corpus / "0001-a.md").read_text(encoding="utf-8")
        self.assertIn(f'  - "{self.prefix}0002-b.md"', text)

        self.assertEqual(rewrite(self.corpus, self.prefix), 1)
        text = (self.corpus / "0001-a.md").read_text(encoding="utf-8")
        self.assertEqual(text.count(self.prefix), 1)

    def test_leaves_non_related_frontmatter_untouched(self):
        path = self.corpus / "0001-a.md"
        path.write_text(
            '---\ntitle: "a"\ntags:\n  - "gace-reusable-asset"\n---\n\n# a\n',
            encoding="utf-8",
        )
        self.assertEqual(rewrite(self.corpus, self.prefix), 0)
        self.assertNotIn(self.prefix, path.read_text(encoding="utf-8"))

    def test_live_runtime_projection_matches_accepted_snapshot(self):
        source = self.corpus / "source"
        runtime = self.corpus / "runtime"
        source.mkdir()
        runtime.mkdir()
        (source / "0001-a.md").write_text(
            '---\ntitle: "a"\nrelated:\n  - "0002-b.md"\n---\n\n# a\n',
            encoding="utf-8",
            newline="\n",
        )
        (source / "0002-b.md").write_text(
            '---\ntitle: "b"\ntags:\n  - "gace-reusable-asset"\n---\n\n# b\n',
            encoding="utf-8",
            newline="\n",
        )

        staging = self.corpus / "staging"
        shutil.copytree(source, staging)
        self.assertEqual(rewrite(staging, self.prefix), 1)
        for path in staging.glob("*.md"):
            shutil.copyfile(path, runtime / f"{self.prefix}{path.name}")

        manifest = verify_projection(source, runtime, self.prefix, expected_count=2)
        self.assertEqual(manifest["fileCount"], 2)
        self.assertEqual(len(manifest["aggregateSha256"]), 64)

    def test_live_runtime_projection_detects_drift(self):
        source = self.corpus / "source-drift"
        runtime = self.corpus / "runtime-drift"
        source.mkdir()
        runtime.mkdir()
        (source / "0001-a.md").write_text(
            '---\ntitle: "a"\ntags:\n  - "gace-reusable-asset"\n---\n\n# a\n',
            encoding="utf-8",
            newline="\n",
        )
        (runtime / f"{self.prefix}0001-a.md").write_text(
            '---\ntitle: "a"\ntags:\n  - "gace-reusable-asset"\n---\n\n# tampered\n',
            encoding="utf-8",
            newline="\n",
        )

        with self.assertRaisesRegex(RuntimeError, "RUNTIME_PROJECTION_CONTENT_MISMATCH"):
            verify_projection(source, runtime, self.prefix, expected_count=1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
