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


def record(
    repository: str,
    commit: str,
    record_type: str = "change",
    source_suffix: str | None = None,
) -> dict[str, str]:
    source = f"git:{repository}@{commit}"
    if source_suffix:
        source += source_suffix
    return {
        "type": record_type,
        "repository": repository,
        "commit": commit,
        "summary": f"summary {commit}{source_suffix or ''}",
        "cause": "",
        "fix": "",
        "validation": "",
        "source": source,
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

    def test_preserves_distinct_sources_at_same_commit(self) -> None:
        one = self.root / "one.jsonl"
        two = self.root / "two.jsonl"
        write_jsonl(one, [record("org/one", "aaa")])
        write_jsonl(
            two,
            [
                record("org/two", "shared", "implementation", "::skillOne"),
                record("org/two", "shared", "implementation", "::skillTwo"),
            ],
        )

        rows = module.combine([one, two])
        self.assertEqual(len(rows), 3)
        skill_rows = [row for row in rows if row["repository"] == "org/two"]
        self.assertEqual(len(skill_rows), 2)
        self.assertNotEqual(skill_rows[0]["source"], skill_rows[1]["source"])

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
