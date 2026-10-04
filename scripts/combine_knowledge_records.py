#!/usr/bin/env python3
"""Combine deterministic G-ACE knowledge JSONL files without inventing data."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


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


def load_file(path: Path) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            item = json.loads(line)
            missing = [key for key in REQUIRED_KEYS if key not in item]
            if missing:
                raise ValueError(
                    f"{path}:{line_number}: missing required keys: {', '.join(missing)}"
                )
            records.append({key: str(item.get(key, "")) for key in REQUIRED_KEYS})
    if not records:
        raise ValueError(f"knowledge record input is empty: {path}")
    return records


def combine(paths: list[Path]) -> list[dict[str, str]]:
    if len(paths) < 2:
        raise ValueError("at least two knowledge-record inputs are required")

    combined: list[dict[str, str]] = []
    seen: dict[tuple[str, str, str], dict[str, str]] = {}
    for path in paths:
        for record in load_file(path):
            key = (record["repository"], record["commit"], record["type"])
            if key in seen:
                if seen[key] != record:
                    raise ValueError("conflicting knowledge evidence for repository/commit/type")
                continue
            seen[key] = record
            combined.append(record)

    repositories = {record["repository"] for record in combined}
    if len(repositories) < 2:
        raise ValueError("combined corpus must contain at least two repositories")
    return combined


def write_jsonl(records: list[dict[str, str]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(output.suffix + ".tmp")
    with temp.open("w", encoding="utf-8", newline="\n") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
    temp.replace(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Combine multiple G-ACE knowledge JSONL exports deterministically"
    )
    parser.add_argument("--input", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    inputs = [path.resolve() for path in args.input]
    records = combine(inputs)
    output = args.output.resolve()
    write_jsonl(records, output)
    repositories = sorted({record["repository"] for record in records})
    print(
        f"GACE_KNOWLEDGE_COMBINE=PASS RECORDS={len(records)} "
        f"REPOSITORIES={len(repositories)} OUTPUT={output}"
    )
    print("REPOSITORY_SET=" + ",".join(repositories))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
