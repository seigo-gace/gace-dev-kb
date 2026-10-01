#!/usr/bin/env python3
"""Render exported G-ACE knowledge records into a deterministic Markdown corpus."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import tempfile
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


def load_records(path: Path) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            item = json.loads(line)
            missing = [key for key in REQUIRED_KEYS if key not in item]
            if missing:
                raise ValueError(
                    f"line {line_number}: missing required keys: {', '.join(missing)}"
                )
            records.append({key: str(item.get(key, "")) for key in REQUIRED_KEYS})

    if not records:
        raise ValueError("knowledge record input is empty")
    return records


def slug(value: str) -> str:
    normalized = re.sub(r"[^0-9A-Za-z._-]+", "-", value.strip()).strip("-")
    return (normalized or "record")[:80]


def display(value: str) -> str:
    return value.strip() or "(not recorded)"


def render_record(record: dict[str, str]) -> str:
    return (
        f"# {display(record['summary'])}\n\n"
        f"- Type: `{display(record['type'])}`\n"
        f"- Repository: `{display(record['repository'])}`\n"
        f"- Commit: `{display(record['commit'])}`\n"
        f"- Source: `{display(record['source'])}`\n\n"
        f"## Summary\n\n{display(record['summary'])}\n\n"
        f"## Cause\n\n{display(record['cause'])}\n\n"
        f"## Fix\n\n{display(record['fix'])}\n\n"
        f"## Validation\n\n{display(record['validation'])}\n"
    )


def write_corpus(records: list[dict[str, str]], output_dir: Path) -> int:
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(prefix=f"{output_dir.name}.tmp-", dir=str(output_dir.parent))
    )

    try:
        for index, record in enumerate(records, start=1):
            commit = slug(record["commit"])[:12]
            record_type = slug(record["type"])
            filename = f"{index:04d}-{commit}-{record_type}.md"
            (temporary / filename).write_text(
                render_record(record), encoding="utf-8", newline="\n"
            )

        if output_dir.exists():
            shutil.rmtree(output_dir)
        temporary.replace(output_dir)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise

    return len(records)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render G-ACE knowledge JSONL into a Markdown search corpus"
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    records = load_records(args.input.resolve())
    count = write_corpus(records, args.output_dir.resolve())
    print(
        f"GACE_KNOWLEDGE_CORPUS=PASS RECORDS={count} "
        f"OUTPUT={args.output_dir.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
