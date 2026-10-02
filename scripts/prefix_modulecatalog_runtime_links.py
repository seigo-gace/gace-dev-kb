#!/usr/bin/env python3
"""Rewrite runtime-only frontmatter related links after corpus filename prefixing."""
from __future__ import annotations

import argparse
import re
from pathlib import Path

RELATED_ITEM = re.compile(r'^(\s*-\s*")([^"]+\.md)("\s*)$')


def rewrite(corpus: Path, prefix: str) -> int:
    corpus = corpus.resolve()
    files = sorted(corpus.glob("*.md"))
    if not files:
        raise RuntimeError(f"RUNTIME_CORPUS_EMPTY={corpus}")
    rewritten = 0
    links = 0
    for path in files:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
        if not lines or lines[0] != "---":
            raise RuntimeError(f"RUNTIME_FRONTMATTER_MISSING={path.name}")
        in_related = False
        changed = False
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
                changed = True
            links += 1
        if changed:
            path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
            rewritten += 1

    print(
        f"GACE_MODULECATALOG_RUNTIME_LINK_PREFIX=PASS FILES={len(files)} "
        f"REWRITTEN={rewritten} LINKS={links} PREFIX={prefix}"
    )
    return links


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--prefix", required=True)
    args = parser.parse_args()
    rewrite(args.corpus, args.prefix)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
