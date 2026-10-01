#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


sys.dont_write_bytecode = True
REPO_ROOT = Path(__file__).resolve().parents[1]
ADAPTER_PATH = REPO_ROOT / "scripts" / "gace_knowledge_adapter.py"
spec = importlib.util.spec_from_file_location("gace_knowledge_adapter", ADAPTER_PATH)
assert spec and spec.loader
adapter = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = adapter
spec.loader.exec_module(adapter)


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed: {result.stderr}")
    return result.stdout


class KnowledgeAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name)
        git(self.repo, "init")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "G-ACE Test")
        git(self.repo, "remote", "add", "origin", "https://github.com/seigo-gace/example-repo.git")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def commit(self, subject: str, body: str = "") -> str:
        git(self.repo, "add", "-A")
        args = ["commit", "-m", subject]
        if body:
            args.extend(["-m", body])
        git(self.repo, *args)
        return git(self.repo, "rev-parse", "HEAD").strip()

    def test_fix_commit_maps_full_contract(self) -> None:
        (self.repo / "tests").mkdir()
        (self.repo / "tests" / "test_example.txt").write_text("ok\n", encoding="utf-8")
        sha = self.commit(
            "fix: normalize Windows graph paths",
            "Cause: Kuzu received Windows backslash paths\n"
            "Fix: normalize paths before query construction\n"
            "Validation: Windows regression gate PASS",
        )

        record = adapter.build_record(self.repo, sha, adapter.repository_name(self.repo))
        self.assertEqual(record.type, "fix")
        self.assertEqual(record.repository, "seigo-gace/example-repo")
        self.assertEqual(record.commit, sha)
        self.assertEqual(record.summary, "normalize Windows graph paths")
        self.assertEqual(record.cause, "Kuzu received Windows backslash paths")
        self.assertEqual(record.fix, "normalize paths before query construction")
        self.assertEqual(record.validation, "Windows regression gate PASS")
        self.assertEqual(record.source, f"git:seigo-gace/example-repo@{sha}")

    def test_design_commit_is_classified_from_path(self) -> None:
        docs = self.repo / "docs"
        docs.mkdir()
        (docs / "CURRENT_DESIGN.md").write_text("baseline\n", encoding="utf-8")
        sha = self.commit("update baseline")
        record = adapter.build_record(self.repo, sha, adapter.repository_name(self.repo))
        self.assertEqual(record.type, "design")

    def test_untracked_file_does_not_fail_clean_gate(self) -> None:
        (self.repo / "README.md").write_text("tracked\n", encoding="utf-8")
        self.commit("docs: add readme")
        (self.repo / ".gitignore").write_text("local-only\n", encoding="utf-8")
        adapter.assert_tracked_tree_clean(self.repo)

    def test_modified_tracked_file_fails_clean_gate(self) -> None:
        readme = self.repo / "README.md"
        readme.write_text("tracked\n", encoding="utf-8")
        self.commit("docs: add readme")
        readme.write_text("modified\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "TRACKED_WORKTREE_DIRTY"):
            adapter.assert_tracked_tree_clean(self.repo)

    def test_jsonl_export_preserves_contract_keys(self) -> None:
        (self.repo / "README.md").write_text("one\n", encoding="utf-8")
        sha1 = self.commit("feat: first capability")
        (self.repo / "README.md").write_text("two\n", encoding="utf-8")
        sha2 = self.commit("test: validate capability", "Validation: PASS")

        records = [
            adapter.build_record(self.repo, sha, adapter.repository_name(self.repo))
            for sha in (sha1, sha2)
        ]
        output = self.repo / "out" / "records.jsonl"
        count = adapter.write_jsonl(records, output)
        self.assertEqual(count, 2)
        rows = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(
            list(rows[0].keys()),
            ["type", "repository", "commit", "summary", "cause", "fix", "validation", "source"],
        )
        self.assertEqual(rows[1]["validation"], "PASS")

    def test_zero_max_count_retains_full_history_and_positive_limit_is_bounded(self) -> None:
        path = self.repo / "history.txt"
        shas: list[str] = []
        for index in range(3):
            path.write_text(f"{index}\n", encoding="utf-8")
            shas.append(self.commit(f"feat: history {index}"))

        self.assertEqual(adapter.list_commits(self.repo, "HEAD", 0), shas)
        self.assertEqual(adapter.list_commits(self.repo, "HEAD", 2), shas[-2:])
        with self.assertRaisesRegex(ValueError, "max_count must be >= 0"):
            adapter.list_commits(self.repo, "HEAD", -1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
