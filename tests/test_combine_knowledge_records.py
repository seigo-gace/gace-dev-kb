#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "combine_knowledge_records.py"
spec = importlib.util.spec_from_file_location("combine_knowledge_records", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def record(repository: str, commit: str, record_type: str = "change") -> dict[str, str]:
    return {
        "type": record_type,
        "repository": repository,
        "commit": commit,
        "summary": f"summary {commit}",
        "cause": "",
        "fix": "",
        "validation": "",
        "source": f"git:{repository}@{commit}",
    }


def write_jsonl(path: Path, rows: list[dict[str, str]]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )


class CombineKnowledgeRecordsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_combines_two_repositories_and_deduplicates(self) -> None:
        one = self.root / "one.jsonl"
        two = self.root / "two.jsonl"
        write_jsonl(one, [record("org/one", "aaa"), record("org/one", "bbb")])
        write_jsonl(two, [record("org/two", "ccc"), record("org/two", "ccc")])

        rows = module.combine([one, two])
        self.assertEqual(len(rows), 3)
        self.assertEqual({row["repository"] for row in rows}, {"org/one", "org/two"})

    def test_rejects_single_repository_result(self) -> None:
        one = self.root / "one.jsonl"
        two = self.root / "two.jsonl"
        write_jsonl(one, [record("org/one", "aaa")])
        write_jsonl(two, [record("org/one", "bbb")])

        with self.assertRaisesRegex(ValueError, "at least two repositories"):
            module.combine([one, two])

    def test_missing_contract_field_fails(self) -> None:
        one = self.root / "one.jsonl"
        two = self.root / "two.jsonl"
        broken = record("org/one", "aaa")
        broken.pop("validation")
        write_jsonl(one, [broken])
        write_jsonl(two, [record("org/two", "bbb")])

        with self.assertRaisesRegex(ValueError, "missing required keys"):
            module.combine([one, two])

    def test_conflicting_admission_is_not_silently_discarded(self) -> None:
        one = self.root / "one.jsonl"
        two = self.root / "two.jsonl"
        original = record("org/one", "aaa")
        changed = {**original, "cause": "different admitted evidence"}
        write_jsonl(one, [original])
        write_jsonl(two, [changed, record("org/two", "bbb")])
        with self.assertRaisesRegex(ValueError, "conflicting knowledge evidence"):
            module.combine([one, two])


if __name__ == "__main__":
    unittest.main(verbosity=2)
