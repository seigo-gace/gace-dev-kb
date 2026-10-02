#!/usr/bin/env python3
"""Replace the active ModuleCatalog reusable-asset snapshot in formal G-ACE records.

ModuleCatalog is the source of truth for reusable development assets. The active KB
must therefore keep exactly one current ModuleCatalog asset projection. Repository
history and non-ModuleCatalog knowledge are preserved, while every older
ModuleCatalog asset projection produced through the `modulecatalog:` source scheme
is replaced regardless of the legacy record `type` that created it.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

REQUIRED_KEYS = (
    "type",
    "repository",
    "commit",
    "summary",
    "cause",
    "fix",
    "validation",
    "source",
)
REUSABLE_TYPE = "reusable_asset"
MODULECATALOG_REPOSITORY = "seigo-gace/modular-catalog"
MODULECATALOG_SOURCE_PREFIX = "modulecatalog:"


def load(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            value: Any = json.loads(line)
            if not isinstance(value, dict):
                raise RuntimeError(f"KNOWLEDGE_RECORD_NOT_OBJECT file={path} line={line_number}")
            missing = [key for key in REQUIRED_KEYS if key not in value]
            if missing:
                raise RuntimeError(
                    f"KNOWLEDGE_RECORD_FIELD_MISSING file={path} line={line_number} fields={','.join(missing)}"
                )
            rows.append({key: str(value.get(key, "")) for key in REQUIRED_KEYS})
    if not rows:
        raise RuntimeError(f"KNOWLEDGE_RECORD_INPUT_EMPTY={path}")
    return rows


def is_replacement_record(row: dict[str, str]) -> bool:
    return (
        row["type"] == REUSABLE_TYPE
        and row["repository"] == MODULECATALOG_REPOSITORY
        and row["source"].startswith(MODULECATALOG_SOURCE_PREFIX)
    )


def is_modulecatalog_asset_projection(row: dict[str, str]) -> bool:
    """True for any old/new asset projection emitted from ModuleCatalog.

    Earlier trials used `type=implementation`; the general intake uses
    `type=reusable_asset`. The source scheme is the stable boundary that separates
    accepted ModuleCatalog asset projections from ordinary Git history knowledge.
    """

    return (
        row["repository"] == MODULECATALOG_REPOSITORY
        and row["source"].startswith(MODULECATALOG_SOURCE_PREFIX)
    )


def identity(row: dict[str, str]) -> tuple[str, str, str, str]:
    return row["repository"], row["commit"], row["type"], row["source"]


def replace_snapshot(
    current: list[dict[str, str]], replacement: list[dict[str, str]]
) -> tuple[list[dict[str, str]], int, int]:
    for row in replacement:
        if not is_replacement_record(row):
            raise RuntimeError(
                "REPLACEMENT_RECORD_NOT_MODULECATALOG_REUSABLE=" + row.get("source", "")
            )

    replacement_seen: set[tuple[str, str, str, str]] = set()
    replacement_unique: list[dict[str, str]] = []
    for row in replacement:
        key = identity(row)
        if key in replacement_seen:
            raise RuntimeError("REPLACEMENT_RECORD_DUPLICATE=" + row["source"])
        replacement_seen.add(key)
        replacement_unique.append(row)

    base = [row for row in current if not is_modulecatalog_asset_projection(row)]
    removed = len(current) - len(base)

    base_seen = {identity(row) for row in base}
    overlap = [row["source"] for row in replacement_unique if identity(row) in base_seen]
    if overlap:
        raise RuntimeError("REPLACEMENT_COLLIDES_WITH_BASE=" + overlap[0])

    combined = base + replacement_unique
    return combined, removed, len(base)


def write(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    temp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--replacement", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--base-output", type=Path)
    parser.add_argument("--expected-replacement-count", type=int)
    args = parser.parse_args()

    current = load(args.current.resolve())
    replacement = load(args.replacement.resolve())
    if (
        args.expected_replacement_count is not None
        and len(replacement) != args.expected_replacement_count
    ):
        raise RuntimeError(
            f"REPLACEMENT_COUNT_MISMATCH expected={args.expected_replacement_count} actual={len(replacement)}"
        )

    combined, removed, base_count = replace_snapshot(current, replacement)
    output = args.output.resolve()
    write(output, combined)
    if args.base_output:
        base_rows = [row for row in current if not is_modulecatalog_asset_projection(row)]
        write(args.base_output.resolve(), base_rows)
    print(
        "GACE_REUSABLE_SNAPSHOT_REPLACE=PASS "
        f"BASE={base_count} REMOVED={removed} ADDED={len(replacement)} TOTAL={len(combined)} "
        f"OUTPUT={output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
