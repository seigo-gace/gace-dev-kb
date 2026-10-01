#!/usr/bin/env python3
"""Deterministic repository -> G-ACE knowledge-record adapter.

This adapter does not replace Git as source of truth. It projects committed
repository evidence into the initial G-ACE knowledge contract:

    type, repository, commit, summary, cause, fix, validation, source

It intentionally uses only the Python standard library and Git CLI.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse


FIELD_NAMES = ("cause", "fix", "validation", "source")
MARKER_RE = re.compile(r"^(Cause|Fix|Validation|Source)\s*:\s*(.*)$", re.IGNORECASE)
CONVENTIONAL_PREFIX_RE = re.compile(r"^(?P<prefix>[a-zA-Z]+)(?:\([^)]*\))?!?:\s*(?P<text>.*)$")


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


def run_git(repo: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if check and result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(f"git {' '.join(args)} failed ({result.returncode}): {stderr}")
    return result.stdout


def assert_repository(repo: Path) -> None:
    if not repo.is_dir():
        raise RuntimeError(f"repository not found: {repo}")
    if run_git(repo, "rev-parse", "--is-inside-work-tree").strip().lower() != "true":
        raise RuntimeError(f"not a Git work tree: {repo}")


def assert_tracked_tree_clean(repo: Path) -> None:
    # Deliberately ignore untracked files. Local runtime evidence such as an
    # untracked .gitignore must not block knowledge projection, while modified
    # tracked files or staged-but-uncommitted changes must block it.
    for args, label in (
        (("diff", "--quiet", "--exit-code"), "TRACKED_WORKTREE_DIRTY"),
        (("diff", "--cached", "--quiet", "--exit-code"), "INDEX_DIRTY"),
    ):
        result = subprocess.run(["git", "-C", str(repo), *args], check=False)
        if result.returncode == 1:
            raise RuntimeError(label)
        if result.returncode != 0:
            raise RuntimeError(f"{label}_CHECK_FAILED={result.returncode}")


def normalize_repository(remote: str, repo: Path) -> str:
    value = remote.strip()
    if not value:
        return repo.name

    if value.startswith("git@") and ":" in value:
        path = value.split(":", 1)[1]
    elif "://" in value:
        path = urlparse(value).path.lstrip("/")
    else:
        path = value

    if path.endswith(".git"):
        path = path[:-4]
    return path.strip("/") or repo.name


def repository_name(repo: Path) -> str:
    remote = run_git(repo, "remote", "get-url", "origin", check=False).strip()
    return normalize_repository(remote, repo)


def parse_marked_fields(body: str) -> dict[str, str]:
    fields: dict[str, list[str]] = {name: [] for name in FIELD_NAMES}
    active: str | None = None

    for raw_line in body.splitlines():
        line = raw_line.rstrip()
        marker = MARKER_RE.match(line)
        if marker:
            active = marker.group(1).lower()
            initial = marker.group(2).strip()
            if initial:
                fields[active].append(initial)
            continue

        if active is not None and (raw_line.startswith(" ") or raw_line.startswith("\t")):
            continuation = line.strip()
            if continuation:
                fields[active].append(continuation)
            continue

        if line.strip():
            active = None

    return {key: " ".join(parts).strip() for key, parts in fields.items()}


def strip_conventional_prefix(subject: str) -> tuple[str, str]:
    match = CONVENTIONAL_PREFIX_RE.match(subject.strip())
    if not match:
        return "", subject.strip()
    return match.group("prefix").lower(), match.group("text").strip()


def classify_record(subject: str, files: Iterable[str]) -> str:
    file_list = [path.replace("\\", "/") for path in files]
    prefix, _ = strip_conventional_prefix(subject)

    if prefix in {"fix", "bugfix", "hotfix"}:
        return "fix"
    if prefix in {"test", "tests"}:
        return "validation"
    if prefix in {"feat", "feature", "refactor", "perf"}:
        return "implementation"
    if prefix in {"docs", "doc"}:
        return "design" if any(
            path in {"docs/CURRENT_DESIGN.md", "docs/DESIGN_DELTA.md"} for path in file_list
        ) else "documentation"

    if any(path in {"docs/CURRENT_DESIGN.md", "docs/DESIGN_DELTA.md"} for path in file_list):
        return "design"
    if any(path.startswith("tests/") for path in file_list):
        return "validation"
    return "change"


def commit_files(repo: Path, sha: str) -> list[str]:
    output = run_git(
        repo,
        "diff-tree",
        "--root",
        "--no-commit-id",
        "--name-only",
        "-r",
        sha,
    )
    return [line.strip() for line in output.splitlines() if line.strip()]


def build_record(repo: Path, sha: str, repository: str) -> KnowledgeRecord:
    subject = run_git(repo, "show", "-s", "--format=%s", sha).strip()
    body = run_git(repo, "show", "-s", "--format=%b", sha)
    files = commit_files(repo, sha)
    marked = parse_marked_fields(body)
    record_type = classify_record(subject, files)
    _, summary_text = strip_conventional_prefix(subject)

    cause = marked["cause"]
    fix = marked["fix"]
    validation = marked["validation"]
    source = marked["source"] or f"git:{repository}@{sha}"

    if not fix and record_type == "fix":
        fix = summary_text

    if not validation:
        validation_files = [path for path in files if path.replace("\\", "/").startswith("tests/")]
        if validation_files:
            validation = "Validation evidence files changed: " + ", ".join(validation_files)

    return KnowledgeRecord(
        type=record_type,
        repository=repository,
        commit=sha,
        summary=summary_text or subject,
        cause=cause,
        fix=fix,
        validation=validation,
        source=source,
    )


def list_commits(repo: Path, revision: str, max_count: int = 0) -> list[str]:
    """List commits oldest-to-newest.

    ``max_count=0`` means all commits reachable from ``revision``. A positive
    value is an explicit bounded export for tests or temporary workflows. The
    durable KB path must not silently evict older knowledge as the repository
    grows.
    """
    if max_count < 0:
        raise ValueError("max_count must be >= 0")

    args = ["rev-list", "--reverse"]
    if max_count > 0:
        args.append(f"--max-count={max_count}")
    args.append(revision)

    output = run_git(repo, *args)
    commits = [line.strip() for line in output.splitlines() if line.strip()]
    if not commits:
        raise RuntimeError(f"no commits resolved from revision: {revision}")
    return commits


def write_jsonl(records: Iterable[KnowledgeRecord], output: Path) -> int:
    rows = [json.dumps(asdict(record), ensure_ascii=False, separators=(",", ":")) for record in records]
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(output.suffix + ".tmp")
    temp.write_text("\n".join(rows) + "\n", encoding="utf-8")
    temp.replace(output)
    return len(rows)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export committed G-ACE repository knowledge as JSONL")
    parser.add_argument("--repo", type=Path, required=True, help="Git repository to read")
    parser.add_argument("--revision", default="HEAD", help="Revision or revision range for git rev-list")
    parser.add_argument(
        "--max-count",
        type=int,
        default=0,
        help="Maximum commits to export; 0 exports all reachable commits (default)",
    )
    parser.add_argument("--output", type=Path, help="JSONL destination; omit to print records")
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="Allow modified/staged tracked files (untracked files are always ignored by this gate)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    repo = args.repo.resolve()

    assert_repository(repo)
    if not args.allow_dirty:
        assert_tracked_tree_clean(repo)

    repository = repository_name(repo)
    commits = list_commits(repo, args.revision, args.max_count)
    records = [build_record(repo, sha, repository) for sha in commits]

    if args.output:
        count = write_jsonl(records, args.output.resolve())
        print(f"GACE_KNOWLEDGE_EXPORT=PASS RECORDS={count} OUTPUT={args.output.resolve()}")
    else:
        for record in records:
            print(json.dumps(asdict(record), ensure_ascii=False, separators=(",", ":")))
        print(f"GACE_KNOWLEDGE_EXPORT=PASS RECORDS={len(records)}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
