#!/usr/bin/env python3
"""Verify the active prefixed ModuleCatalog runtime corpus byte-for-byte.

The Current reusable snapshot keeps the accepted/enriched Markdown with its
original filenames. The live MVS corpus keeps the same documents under a
Catalog-commit prefix and rewrites only frontmatter ``related:`` targets to the
same prefix. This verifier deterministically reproduces that runtime transform
in memory and requires the actual live files to match exactly.
"""
from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

from runtime_corpus_integrity import build_manifest

RELATED_ITEM = re.compile(r'^(\s*-\s*")([^"]+\.md)("\s*)$')


def transform_runtime_text(text: str, prefix: str) -> str:
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise RuntimeError("RUNTIME_PROJECTION_SOURCE_FRONTMATTER_MISSING")

    in_related = False
    for index, line in enumerate(lines[1:], start=1):
        if line == "---":
            break
        if line == "related:":
            in_related = True
            continue
        if in_related and line and not line.startswith((" ", "\t")):
            in_related = False
        if not in_related:
            continue
        match = RELATED_ITEM.match(line)
        if not match:
            continue
        target = match.group(2)
        if not target.startswith(prefix):
            target = prefix + target
            lines[index] = f"{match.group(1)}{target}{match.group(3)}"

    return "\n".join(lines) + "\n"


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def verify_projection(
    source_corpus: Path,
    runtime_corpus: Path,
    prefix: str,
    expected_count: int | None = None,
) -> dict:
    source_corpus = source_corpus.resolve()
    runtime_corpus = runtime_corpus.resolve()
    if not source_corpus.is_dir():
        raise RuntimeError(f"RUNTIME_PROJECTION_SOURCE_DIR_MISSING={source_corpus}")
    if not runtime_corpus.is_dir():
        raise RuntimeError(f"RUNTIME_PROJECTION_RUNTIME_DIR_MISSING={runtime_corpus}")
    if not prefix or any(sep in prefix for sep in ("/", "\\")):
        raise RuntimeError(f"RUNTIME_PROJECTION_PREFIX_INVALID={prefix}")

    sources = sorted(path for path in source_corpus.glob("*.md") if path.is_file())
    if expected_count is not None and len(sources) != expected_count:
        raise RuntimeError(
            f"RUNTIME_PROJECTION_SOURCE_COUNT_MISMATCH expected={expected_count} actual={len(sources)}"
        )
    if not sources:
        raise RuntimeError("RUNTIME_PROJECTION_SOURCE_EMPTY")

    runtime_files = sorted(
        path for path in runtime_corpus.glob(f"{prefix}*.md") if path.is_file()
    )
    if len(runtime_files) != len(sources):
        raise RuntimeError(
            f"RUNTIME_PROJECTION_RUNTIME_COUNT_MISMATCH expected={len(sources)} actual={len(runtime_files)}"
        )

    expected_names = {prefix + path.name for path in sources}
    actual_names = {path.name for path in runtime_files}
    missing = sorted(expected_names - actual_names)
    extra = sorted(actual_names - expected_names)
    if missing or extra:
        raise RuntimeError(
            "RUNTIME_PROJECTION_FILENAME_MISMATCH "
            f"missing={','.join(missing)} extra={','.join(extra)}"
        )

    verified = 0
    for source in sources:
        runtime = runtime_corpus / f"{prefix}{source.name}"
        expected_text = transform_runtime_text(
            source.read_text(encoding="utf-8-sig"),
            prefix,
        )
        expected_bytes = expected_text.encode("utf-8")
        actual_bytes = runtime.read_bytes()
        if actual_bytes != expected_bytes:
            raise RuntimeError(
                "RUNTIME_PROJECTION_CONTENT_MISMATCH "
                f"file={runtime.name} expectedSha256={sha256(expected_bytes)} "
                f"actualSha256={sha256(actual_bytes)}"
            )
        verified += 1

    manifest = build_manifest(runtime_corpus, prefix, expected_count=len(sources))
    print(
        "GACE_MODULECATALOG_RUNTIME_PROJECTION=PASS "
        f"FILES={verified} SHA256={manifest['aggregateSha256']} PREFIX={prefix}"
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-corpus", type=Path, required=True)
    parser.add_argument("--runtime-corpus", type=Path, required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--expected-count", type=int)
    args = parser.parse_args()
    verify_projection(
        args.source_corpus,
        args.runtime_corpus,
        args.prefix,
        args.expected_count,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
