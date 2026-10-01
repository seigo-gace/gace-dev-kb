#!/usr/bin/env python3
"""Import one verified ModuleCatalog asset as searchable G-ACE skill knowledge.

The importer is deliberately conservative:
- it executes no asset source code,
- verifies the asset manifest before accepting content,
- requires explicit normal/user PASS evidence,
- preserves the G-ACE eight-field knowledge contract,
- emits one Markdown corpus document per exported named skill.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path


REQUIRED_ASSET_FILES = (
    "README.md",
    "design.md",
    "logic.md",
    "architecture.md",
    "evidence.json",
    "manifest.json",
    "meta.json",
    "source/index.js",
)
EXPORT_RE = re.compile(r"module\.exports\s*=\s*\{(?P<body>[^}]*)\}\s*;?", re.DOTALL)
FUNCTION_RE = re.compile(r"(?m)^function\s+(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)\s*\(")
CAMEL_RE = re.compile(r"(?<=[a-z0-9])(?=[A-Z])")


@dataclass(frozen=True)
class KnowledgeRecord:
    type: str
    repository: str
    commit: str
    summary: str
    cause: str
    fix: str
    validation: str
    source: str


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
        raise RuntimeError(
            f"git {' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}"
        )
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_manifest(asset_dir: Path, manifest: dict) -> None:
    if manifest.get("algorithm") != "sha256":
        raise RuntimeError("ASSET_MANIFEST_ALGORITHM_NOT_SHA256")

    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        raise RuntimeError("ASSET_MANIFEST_FILES_MISSING")

    listed: set[str] = set()
    for item in files:
        if not isinstance(item, dict):
            raise RuntimeError("ASSET_MANIFEST_FILE_ENTRY_INVALID")

        rel = str(item.get("path") or "").replace("\\", "/").strip("/")
        if not rel:
            raise RuntimeError("ASSET_MANIFEST_PATH_EMPTY")
        if rel in listed:
            raise RuntimeError(f"ASSET_MANIFEST_DUPLICATE_PATH={rel}")
        listed.add(rel)

        path = (asset_dir / rel).resolve()
        try:
            path.relative_to(asset_dir.resolve())
        except ValueError as exc:
            raise RuntimeError(f"ASSET_MANIFEST_PATH_ESCAPE={rel}") from exc

        if not path.is_file():
            raise RuntimeError(f"ASSET_MANIFEST_FILE_MISSING={rel}")

        expected_size = item.get("size")
        if expected_size is not None and path.stat().st_size != int(expected_size):
            raise RuntimeError(
                f"ASSET_MANIFEST_SIZE_MISMATCH={rel} "
                f"expected={expected_size} actual={path.stat().st_size}"
            )

        expected_hash = str(item.get("sha256") or "").lower()
        actual_hash = sha256_file(path)
        if expected_hash != actual_hash:
            raise RuntimeError(
                f"ASSET_MANIFEST_SHA256_MISMATCH={rel} "
                f"expected={expected_hash} actual={actual_hash}"
            )

    for rel in REQUIRED_ASSET_FILES:
        if rel == "manifest.json":
            continue
        if rel not in listed:
            raise RuntimeError(f"ASSET_REQUIRED_FILE_NOT_MANIFESTED={rel}")


def require_passed_evidence(evidence: dict) -> None:
    for key in ("normal", "user"):
        section = evidence.get(key)
        if not isinstance(section, dict) or section.get("passed") is not True:
            raise RuntimeError(f"ASSET_EVIDENCE_NOT_PASSED={key}")


def exported_skill_names(source: str) -> list[str]:
    match = EXPORT_RE.search(source)
    if not match:
        raise RuntimeError("ASSET_MODULE_EXPORTS_MISSING")

    names: list[str] = []
    for token in match.group("body").split(","):
        name = token.strip()
        if not name:
            continue
        if not re.fullmatch(r"[A-Za-z_$][A-Za-z0-9_$]*", name):
            raise RuntimeError(f"ASSET_EXPORT_UNSUPPORTED={name}")
        names.append(name)

    if not names:
        raise RuntimeError("ASSET_EXPORTS_EMPTY")
    if len(set(names)) != len(names):
        raise RuntimeError("ASSET_EXPORTS_DUPLICATE")

    declarations = {match.group("name") for match in FUNCTION_RE.finditer(source)}
    missing = [name for name in names if name not in declarations]
    if missing:
        raise RuntimeError(
            "ASSET_EXPORTED_FUNCTION_DECLARATION_MISSING=" + ",".join(missing)
        )
    return names


def extract_top_level_functions(source: str) -> dict[str, str]:
    matches = list(FUNCTION_RE.finditer(source))
    functions: dict[str, str] = {}
    for index, match in enumerate(matches):
        start = match.start()
        end = (
            matches[index + 1].start()
            if index + 1 < len(matches)
            else source.find("module.exports", match.end())
        )
        if end < 0:
            end = len(source)
        functions[match.group("name")] = source[start:end].strip()
    return functions


def humanize_symbol(name: str) -> str:
    return " ".join(CAMEL_RE.sub(" ", name).split())


def validation_text(meta: dict, evidence: dict) -> str:
    normal = evidence.get("normal") or {}
    user = evidence.get("user") or {}
    parts = [
        "ModuleCatalog evidence normal.passed=true",
        "user.passed=true",
    ]
    verified_at = str(meta.get("verifiedAt") or "")
    if verified_at:
        parts.append(f"verifiedAt={verified_at}")

    normal_expected = "; ".join(str(x) for x in normal.get("expectedResults") or [])
    user_expected = "; ".join(str(x) for x in user.get("expectedResults") or [])
    if normal_expected:
        parts.append(f"normal={normal_expected}")
    if user_expected:
        parts.append(f"user={user_expected}")
    return "; ".join(parts)


def markdown_for_skill(
    record: KnowledgeRecord,
    *,
    asset_id: str,
    asset_meta: dict,
    skill_name: str,
    function_source: str,
    readme: str,
    design: str,
    logic: str,
    architecture: str,
    evidence: dict,
) -> str:
    layers = ", ".join(str(x) for x in asset_meta.get("layers") or [])
    tags = ", ".join(str(x) for x in asset_meta.get("tags") or [])
    constraints = "\n".join(
        f"- {item}" for item in asset_meta.get("constraints") or []
    ) or "- (none recorded)"
    evidence_text = json.dumps(evidence, ensure_ascii=False, indent=2)

    return f"""# {record.summary}

## G-ACE Knowledge Metadata

- Type: `{record.type}`
- Repository: `{record.repository}`
- Commit: `{record.commit}`
- Source: `{record.source}`

## Summary

{record.summary}

## Cause

{record.cause or "(not recorded)"}

## Fix

{record.fix or "(not recorded)"}

## Validation

{record.validation}

## ModuleCatalog Asset Metadata

- Asset ID: `{asset_id}`
- Asset Name: `{asset_meta.get("name", asset_id)}`
- Asset Version: `{asset_meta.get("version", "")}`
- Layers: `{layers}`
- Tags: `{tags}`

### Constraints

{constraints}

## Skill Symbol

`{skill_name}`

```javascript
{function_source}
```

## Asset README

{readme.strip()}

## Asset Design

{design.strip()}

## Asset Logic

{logic.strip()}

## Asset Architecture

{architecture.strip()}

## Source Evidence

```json
{evidence_text}
```
"""


def build(
    catalog_root: Path,
    asset_id: str,
    output_root: Path,
    expected_skill_count: int | None,
) -> tuple[list[KnowledgeRecord], Path]:
    catalog_root = catalog_root.resolve()
    asset_dir = (catalog_root / "assets" / asset_id).resolve()
    if not asset_dir.is_dir():
        raise RuntimeError(f"ASSET_DIRECTORY_MISSING={asset_dir}")

    for rel in REQUIRED_ASSET_FILES:
        if not (asset_dir / rel).is_file():
            raise RuntimeError(f"ASSET_REQUIRED_FILE_MISSING={rel}")

    meta = json.loads((asset_dir / "meta.json").read_text(encoding="utf-8"))
    evidence = json.loads((asset_dir / "evidence.json").read_text(encoding="utf-8"))
    manifest = json.loads((asset_dir / "manifest.json").read_text(encoding="utf-8"))

    verify_manifest(asset_dir, manifest)
    require_passed_evidence(evidence)

    source = (asset_dir / "source/index.js").read_text(encoding="utf-8")
    skills = exported_skill_names(source)
    if expected_skill_count is not None and len(skills) != expected_skill_count:
        raise RuntimeError(
            f"ASSET_SKILL_COUNT_MISMATCH expected={expected_skill_count} actual={len(skills)}"
        )

    functions = extract_top_level_functions(source)
    catalog_commit = git(catalog_root, "rev-parse", "HEAD")
    repository = "seigo-gace/modular-catalog"

    readme = (asset_dir / "README.md").read_text(encoding="utf-8")
    design = (asset_dir / "design.md").read_text(encoding="utf-8")
    logic = (asset_dir / "logic.md").read_text(encoding="utf-8")
    architecture = (asset_dir / "architecture.md").read_text(encoding="utf-8")

    output_root = output_root.resolve()
    corpus = output_root / "records"
    corpus.mkdir(parents=True, exist_ok=True)
    for path in corpus.glob("*.md"):
        path.unlink()

    validation = validation_text(meta, evidence)
    records: list[KnowledgeRecord] = []
    for index, skill_name in enumerate(skills, start=1):
        record = KnowledgeRecord(
            type="implementation",
            repository=repository,
            commit=catalog_commit,
            summary=f"{humanize_symbol(skill_name)} reusable DebugAI skill",
            cause="",
            fix="",
            validation=validation,
            source=(
                f"modulecatalog:{repository}@{catalog_commit}"
                f"#assets/{asset_id}/source/index.js::{skill_name}"
            ),
        )
        records.append(record)
        (corpus / f"{index:02d}-{skill_name}.md").write_text(
            markdown_for_skill(
                record,
                asset_id=asset_id,
                asset_meta=meta,
                skill_name=skill_name,
                function_source=functions[skill_name],
                readme=readme,
                design=design,
                logic=logic,
                architecture=architecture,
                evidence=evidence,
            ),
            encoding="utf-8",
            newline="\n",
        )

    jsonl = output_root / "knowledge-records.jsonl"
    with jsonl.open("w", encoding="utf-8", newline="\n") as handle:
        for record in records:
            handle.write(
                json.dumps(asdict(record), ensure_ascii=False, separators=(",", ":"))
                + "\n"
            )

    return records, corpus


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import verified ModuleCatalog exported skills into a trial G-ACE KB corpus"
    )
    parser.add_argument("--catalog-root", type=Path, required=True)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--expected-skill-count", type=int)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    records, corpus = build(
        args.catalog_root,
        args.asset_id,
        args.output_root,
        args.expected_skill_count,
    )
    print(
        f"GACE_MODULECATALOG_SKILL_IMPORT=PASS "
        f"ASSET={args.asset_id} SKILLS={len(records)} CORPUS={corpus}"
    )
    for record in records:
        print(f"SKILL={record.summary} SOURCE={record.source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
