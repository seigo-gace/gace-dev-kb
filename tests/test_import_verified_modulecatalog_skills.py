from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "import_verified_modulecatalog_skills.py"
spec = importlib.util.spec_from_file_location("import_verified_modulecatalog_skills", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class ImportVerifiedModuleCatalogSkillsTests(unittest.TestCase):
    def make_fixture(self, *, normal: bool = True, user: bool = True):
        temp = tempfile.TemporaryDirectory()
        repo = Path(temp.name) / "catalog"
        repo.mkdir()
        subprocess.run(["git", "init", str(repo)], check=True, capture_output=True)
        subprocess.run(
            ["git", "-C", str(repo), "config", "user.email", "test@example.invalid"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(repo), "config", "user.name", "G-ACE Test"],
            check=True,
        )

        asset = repo / "assets" / "pack"
        (asset / "source").mkdir(parents=True)
        content = {
            "README.md": "# Pack\n",
            "design.md": "# Design\n",
            "logic.md": "# Logic\n",
            "architecture.md": "# Architecture\n",
            "evidence.json": json.dumps(
                {
                    "normal": {"passed": normal, "expectedResults": ["2/2 PASS"]},
                    "user": {"passed": user, "expectedResults": ["1/1 PASS"]},
                }
            ),
            "meta.json": json.dumps(
                {
                    "id": "pack",
                    "name": "Pack",
                    "version": "1",
                    "layers": ["Component"],
                    "tags": ["debugai"],
                    "constraints": ["candidate-only"],
                    "verifiedAt": "2026-10-01T00:00:00Z",
                }
            ),
            "source/index.js": (
                '"use strict";\n'
                "function oneSkill({x}={}){return x;}\n\n"
                "function twoSkill({y}={}){return y;}\n\n"
                "module.exports={oneSkill,twoSkill};\n"
            ),
        }

        for rel, text in content.items():
            path = asset / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

        manifest_files = []
        for rel in content:
            path = asset / rel
            manifest_files.append(
                {
                    "path": rel,
                    "size": path.stat().st_size,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                }
            )
        (asset / "manifest.json").write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "algorithm": "sha256",
                    "files": manifest_files,
                }
            ),
            encoding="utf-8",
        )

        subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
        subprocess.run(
            ["git", "-C", str(repo), "commit", "-m", "fixture"],
            check=True,
            capture_output=True,
        )
        return temp, repo, asset

    def test_imports_exported_skills(self) -> None:
        temp, repo, _ = self.make_fixture()
        try:
            output = Path(temp.name) / "out"
            records, corpus = module.build(repo, "pack", output, 2)
            self.assertEqual(len(records), 2)
            self.assertEqual(len(list(corpus.glob("*.md"))), 2)
            self.assertIn(
                "oneSkill",
                (corpus / "01-oneSkill.md").read_text(encoding="utf-8"),
            )
            self.assertEqual(records[0].repository, "seigo-gace/modular-catalog")
            self.assertIn("normal.passed=true", records[0].validation)
            self.assertIn("user.passed=true", records[0].validation)
        finally:
            temp.cleanup()

    def test_rejects_unpassed_evidence(self) -> None:
        temp, repo, _ = self.make_fixture(user=False)
        try:
            with self.assertRaisesRegex(RuntimeError, "ASSET_EVIDENCE_NOT_PASSED=user"):
                module.build(repo, "pack", Path(temp.name) / "out", 2)
        finally:
            temp.cleanup()

    def test_rejects_manifest_tamper(self) -> None:
        temp, repo, asset = self.make_fixture()
        try:
            (asset / "README.md").write_text("# tampered\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "ASSET_MANIFEST_"):
                module.build(repo, "pack", Path(temp.name) / "out", 2)
        finally:
            temp.cleanup()

    def test_rejects_wrong_skill_count(self) -> None:
        temp, repo, _ = self.make_fixture()
        try:
            with self.assertRaisesRegex(RuntimeError, "ASSET_SKILL_COUNT_MISMATCH"):
                module.build(repo, "pack", Path(temp.name) / "out", 13)
        finally:
            temp.cleanup()


if __name__ == "__main__":
    unittest.main(verbosity=2)
