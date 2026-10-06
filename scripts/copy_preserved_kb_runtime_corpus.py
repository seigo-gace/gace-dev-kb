#!/usr/bin/env python3
"""Copy the preserved part of the current KB corpus without flattening rich data.

ModuleCatalog is a replaceable single-current snapshot. Every existing
ModuleCatalog asset projection is excluded, including the legacy verified-skill
trial whose filenames predate the current reusable prefix. Everything else is
copied byte-for-byte so other rich accepted Knowledge is not reduced to the
legacy eight-field envelope during a Catalog snapshot replacement.
"""
from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path

RUNTIME_PREFIX = "accepted-modulecatalog-reusable-"
LEGACY_SOURCE_RE = re.compile(
    r"^- Source:\s*`modulecatalog:seigo-gace/modular-catalog@",
    re.MULTILINE,
)


def is_modulecatalog_projection(path: Path) -> bool:
    if path.name.startswith(RUNTIME_PREFIX):
        return True
    text = path.read_text(encoding="utf-8-sig")
    return bool(LEGACY_SOURCE_RE.search(text))


def copy_preserved(current: Path, output: Path, expected_count: int | None = None) -> tuple[int, int]:
    current = current.resolve()
    output = output.resolve()
    if not current.is_dir():
        raise RuntimeError(f"CURRENT_CORPUS_MISSING={current}")

    files = sorted(current.glob("*.md"))
    if not files:
        raise RuntimeError(f"CURRENT_CORPUS_EMPTY={current}")

    preserved = [path for path in files if not is_modulecatalog_projection(path)]
    removed = len(files) - len(preserved)
    if expected_count is not None and len(preserved) != expected_count:
        raise RuntimeError(
            f"PRESERVED_CORPUS_COUNT_MISMATCH expected={expected_count} "
            f"actual={len(preserved)} removed={removed} current={len(files)}"
        )

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    for path in preserved:
        shutil.copy2(path, output / path.name)

    print(
        "GACE_PRESERVED_RUNTIME_CORPUS=PASS "
        f"CURRENT={len(files)} PRESERVED={len(preserved)} REMOVED_MODULECATALOG={removed} "
        f"OUTPUT={output}"
    )
    return len(preserved), removed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-count", type=int)
    args = parser.parse_args()
    copy_preserved(args.current, args.output, args.expected_count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
