#!/usr/bin/env python3
"""Deterministic BM25 retention probe for generated G-ACE knowledge.

This probe validates the persisted BM25 index directly, without depending on
human-oriented CLI rendering. It requires that a unique commit id is tokenized,
retrievable, and resolves to indexed chunk content containing that commit id.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import lancedb

from mcp_vector_search.core.bm25_backend import BM25Backend


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--search-root", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--limit", type=int, default=100)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    search_root = args.search_root.resolve()
    bm25_path = search_root / ".mcp-vector-search" / "bm25_index.pkl"
    lance_path = search_root / ".mcp-vector-search" / "lance"

    if not bm25_path.is_file():
        raise RuntimeError(f"BM25_INDEX_MISSING={bm25_path}")
    if not lance_path.is_dir():
        raise RuntimeError(f"LANCE_PATH_MISSING={lance_path}")

    backend = BM25Backend()
    backend.load(bm25_path)
    if not backend.is_built():
        raise RuntimeError("BM25_INDEX_NOT_BUILT")

    query_tokens = backend._tokenize(args.commit)
    commit_token = args.commit.lower()
    if commit_token not in query_tokens:
        raise RuntimeError(
            f"BM25_COMMIT_TOKENIZATION_FAILED LABEL={args.label} TOKENS={query_tokens}"
        )

    bm25 = getattr(backend, "_bm25", None)
    idf = getattr(bm25, "idf", {}) if bm25 is not None else {}
    if commit_token not in idf:
        raise RuntimeError(
            f"BM25_COMMIT_TOKEN_NOT_INDEXED LABEL={args.label} COMMIT={args.commit}"
        )

    results = backend.search(args.commit, limit=args.limit)
    if not results:
        raise RuntimeError(
            f"BM25_COMMIT_SEARCH_EMPTY LABEL={args.label} COMMIT={args.commit}"
        )

    db = lancedb.connect(str(lance_path))
    table = db.open_table("vectors")
    found_path: str | None = None

    for chunk_id, _score in results:
        escaped = chunk_id.replace("'", "''")
        arrow = (
            table.to_lance()
            .scanner(
                filter=f"chunk_id = '{escaped}'",
                columns=["chunk_id", "content", "file_path"],
            )
            .to_table()
        )
        if arrow.num_rows < 1:
            continue
        row = arrow.slice(0, 1).to_pylist()[0]
        content = str(row.get("content") or "")
        if args.commit in content:
            found_path = str(row.get("file_path") or "")
            break

    if not found_path:
        raise RuntimeError(
            f"BM25_COMMIT_CHUNK_NOT_RETRIEVED LABEL={args.label} COMMIT={args.commit} RESULTS={len(results)}"
        )

    print(
        "GACE_BM25_KNOWLEDGE_PROBE=PASS "
        f"LABEL={args.label} COMMIT={args.commit[:8]} RESULTS={len(results)} FILE={found_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
