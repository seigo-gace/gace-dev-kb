#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


sys.dont_write_bytecode = True
REPO_ROOT = Path(__file__).resolve().parents[1]
RENDERER_PATH = REPO_ROOT / "scripts" / "render_knowledge_corpus.py"
spec = importlib.util.spec_from_file_location("render_knowledge_corpus", RENDERER_PATH)
assert spec and spec.loader
renderer = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = renderer
spec.loader.exec_module(renderer)


class RenderKnowledgeCorpusTests(unittest.TestCase):
    def test_renders_one_markdown_file_per_record(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "records.jsonl"
            output = root / "search" / "records"
            records = [
                {
                    "type": "fix",
                    "repository": "seigo-gace/gace-dev-kb",
                    "commit": "74e81717473b500642c565bfd228409d59151789",
                    "summary": "normalize Windows paths for Kuzu graph cleanup",
                    "cause": "Kuzu received Windows backslash paths",
                    "fix": "normalize paths before query construction",
                    "validation": "MVS_REAL_REGRESSION=PASS",
                    "source": "git:seigo-gace/gace-dev-kb@74e81717473b500642c565bfd228409d59151789",
                },
                {
                    "type": "implementation",
                    "repository": "seigo-gace/gace-dev-kb",
                    "commit": "4912a442fc44be5fd2bd8e8796af8bd807e954c8",
                    "summary": "add deterministic G-ACE repository knowledge adapter",
                    "cause": "",
                    "fix": "",
                    "validation": "",
                    "source": "git:seigo-gace/gace-dev-kb@4912a442fc44be5fd2bd8e8796af8bd807e954c8",
                },
            ]
            source.write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )

            loaded = renderer.load_records(source)
            count = renderer.write_corpus(loaded, output)

            self.assertEqual(count, 2)
            files = sorted(output.glob("*.md"))
            self.assertEqual(len(files), 2)
            first = files[0].read_text(encoding="utf-8")
            second = files[1].read_text(encoding="utf-8")
            self.assertIn("74e81717473b500642c565bfd228409d59151789", first)
            self.assertIn("Kuzu received Windows backslash paths", first)
            self.assertIn("MVS_REAL_REGRESSION=PASS", first)
            self.assertIn("4912a442fc44be5fd2bd8e8796af8bd807e954c8", second)
            self.assertIn("(not recorded)", second)

    def test_missing_contract_field_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "records.jsonl"
            source.write_text(json.dumps({"type": "fix"}) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "missing required keys"):
                renderer.load_records(source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
