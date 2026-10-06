#!/usr/bin/env python3
"""Hash the actual active ModuleCatalog runtime Markdown corpus deterministically."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def build_manifest(records_dir: Path, prefix: str, expected_count: int | None = None) -> dict[str, Any]:
    records_dir = records_dir.resolve()
    if not records_dir.is_dir():
        raise RuntimeError(f"RUNTIME_CORPUS_DIR_MISSING={records_dir}")
    if not prefix or any(sep in prefix for sep in ("/", "\\")):
        raise RuntimeError(f"RUNTIME_CORPUS_PREFIX_INVALID={prefix}")

    files = sorted(
        path for path in records_dir.glob(f"{prefix}*.md") if path.is_file()
    )
    if expected_count is not None and len(files) != expected_count:
        raise RuntimeError(
            f"RUNTIME_CORPUS_FILE_COUNT_MISMATCH expected={expected_count} actual={len(files)}"
        )
    if not files:
        raise RuntimeError(f"RUNTIME_CORPUS_EMPTY prefix={prefix}")

    entries: list[dict[str, Any]] = []
    for path in files:
        data = path.read_bytes()
        entries.append(
            {
                "name": path.name,
                "size": len(data),
                "sha256": sha256_bytes(data),
            }
        )

    aggregate = sha256_bytes(canonical_json(entries))
    return {
        "schemaVersion": SCHEMA_VERSION,
        "prefix": prefix,
        "fileCount": len(entries),
        "aggregateSha256": aggregate,
        "files": entries,
    }


def write_atomic(path: Path, value: dict[str, Any]) -> None:
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    temp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--records-dir", type=Path, required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--expected-count", type=int)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    manifest = build_manifest(args.records_dir, args.prefix, args.expected_count)
    if args.output:
        write_atomic(args.output, manifest)
    print(
        "GACE_RUNTIME_CORPUS_INTEGRITY=PASS "
        f"FILES={manifest['fileCount']} SHA256={manifest['aggregateSha256']} "
        f"PREFIX={manifest['prefix']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
