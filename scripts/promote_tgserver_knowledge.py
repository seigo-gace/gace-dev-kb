"""Admit explicit knowledge candidates with raw correlation + Git + verified CI.

Reuses the initial KnowledgeRecord/export contract and existing MVS corpus/MCP.
The caller must obtain search evidence through the trusted TGserver reader.
An input file alone cannot prove live Telegram persistence; correlation is retained.
"""
from __future__ import annotations
import argparse
import json
import re
import subprocess
from pathlib import Path
from devlog_producer import redact, canonical, SCHEMA
from gace_knowledge_adapter import KnowledgeRecord, assert_repository, repository_name, run_git, write_jsonl

def github_ci(repository, run_id):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or not str(run_id).isdigit():
        raise ValueError("INVALID_CI_REFERENCE")
    result = subprocess.run(["gh", "api", f"repos/{repository}/actions/runs/{run_id}"], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise ValueError("CI_READBACK_FAILED")
    return json.loads(result.stdout)

def promote(hit, repo: Path, ci):
    if not isinstance(hit, dict) or not isinstance(hit.get("message"), str):
        raise ValueError("INVALID_RAW_EVIDENCE")
    event = json.loads(hit["message"])
    if event.get("schema") != SCHEMA or event.get("event_type") != "KNOWLEDGE_CANDIDATE":
        raise ValueError("NOT_A_KNOWLEDGE_CANDIDATE")
    if any(not isinstance(event.get(field), str) or not event[field] for field in (
        "event_id", "occurred_at", "ingested_at", "source_surface", "source_instance", "session_id", "summary")):
        raise ValueError("CANONICAL_EVENT_CONTEXT_REQUIRED")
    if "project_id" in event.get("project", {}) or not all(field in event for field in ("turn_id", "change_unit_id")):
        raise ValueError("CANONICAL_PROJECT_CONTEXT_REQUIRED")
    if not isinstance(event.get("evidence"), list) or not all(isinstance(item, dict) for item in event["evidence"]):
        raise ValueError("CANONICAL_EVIDENCE_REQUIRED")
    if event.get("privacy") != {"redacted": True, "contains_internal_reasoning": False} or canonical(redact(event)) != canonical(event):
        raise ValueError("PRIVACY_GATE_FAILED")
    ids = hit.get("telegram_message_ids")
    if not isinstance(ids, list) or not ids or not all(type(value) is int and value > 0 for value in ids):
        raise ValueError("RAW_CORRELATION_MISSING")
    if hit.get("ingested_at") != event.get("ingested_at") or not hit.get("ingested_at") or hit.get("event_timestamp") != event.get("occurred_at"):
        raise ValueError("RAW_TIME_EVIDENCE_MISMATCH")
    assert_repository(repo)
    repository = repository_name(repo)
    if event.get("project", {}).get("repository") != repository:
        raise ValueError("SOURCE_REPOSITORY_MISMATCH")
    knowledge = event.get("details", {}).get("knowledge")
    if not isinstance(knowledge, dict):
        raise ValueError("EXPLICIT_KNOWLEDGE_REQUIRED")
    required = ("type", "commit", "summary", "cause", "fix", "validation", "reuse_scope")
    if any(not isinstance(knowledge.get(field), str) for field in required):
        raise ValueError("KNOWLEDGE_CONTRACT_INVALID")
    sha = knowledge["commit"]
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise ValueError("EXACT_GIT_REVISION_REQUIRED")
    if run_git(repo, "rev-parse", f"{sha}^{{commit}}").strip() != sha:
        raise ValueError("GIT_EVIDENCE_MISSING")
    if ci.get("head_sha") != sha or ci.get("head_repository", {}).get("full_name") != repository or ci.get("status") != "completed" or ci.get("conclusion") != "success":
        raise ValueError("EXACT_REVISION_CI_NOT_VERIFIED")
    if knowledge["type"] not in ("implementation", "design", "fix", "validation", "rejected_pattern") or not all(knowledge[field].strip() for field in ("summary", "validation", "reuse_scope")):
        raise ValueError("REUSABLE_KNOWLEDGE_REQUIRED")
    if knowledge["type"] == "fix" and not all(knowledge[field].strip() for field in ("cause", "fix")):
        raise ValueError("ROOT_CAUSE_AND_FIX_REQUIRED")
    # Bind explicit claim to committed source/test paths without executing input commands.
    evidence = event.get("evidence", [])
    git_ref = f"git:{repository}@{sha}"
    if not any(item.get("kind") == "git" and item.get("ref") == git_ref for item in evidence):
        raise ValueError("GIT_REFERENCE_MISSING")
    test_refs = [item.get("ref", "") for item in evidence if item.get("kind") == "test"]
    prefix = git_ref + ":"
    if not test_refs or not all(ref.startswith(prefix) and run_git(repo, "cat-file", "-t", f"{sha}:{ref[len(prefix):]}").strip() == "blob" for ref in test_refs):
        raise ValueError("COMMITTED_TEST_EVIDENCE_REQUIRED")
    source = f"{git_ref}; tgserver:{event['event_id']}; telegram:{','.join(map(str, ids))}; ci:{ci.get('html_url', '')}; reuse:{knowledge['reuse_scope']}"
    return KnowledgeRecord(type=knowledge["type"], repository=repository, commit=sha, summary=knowledge["summary"],
        cause=knowledge["cause"], fix=knowledge["fix"], validation=knowledge["validation"], source=source)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--search-evidence", type=Path, required=True)
    parser.add_argument("--event-id", required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--ci-run", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    if output.is_relative_to(repo) or output.is_relative_to(Path(__file__).resolve().parent.parent):
        raise ValueError("GENERATED_DATA_MUST_STAY_OUTSIDE_GIT_SOURCE")
    evidence = json.loads(args.search_evidence.read_text(encoding="utf-8"))
    if evidence.get("tgserver_zero", {}).get("index_search_verified") is not True:
        raise ValueError("INDEX_SEARCH_EVIDENCE_REQUIRED")
    hits = [hit for hit in evidence.get("hits", []) if json.loads(hit.get("message", "{}" )).get("event_id") == args.event_id]
    if len(hits) != 1:
        raise ValueError("EXACT_SINGLE_EVENT_REQUIRED")
    record = promote(hits[0], repo, github_ci(repository_name(repo), args.ci_run))
    # Output is a versioned projection keyed to event+commit; retry never overwrites
    # a different admission file. Existing renderer/combiner handle downstream index.
    if output.exists():
        from dataclasses import asdict
        current = json.loads(output.read_text(encoding="utf-8").strip())
        if current != asdict(record):
            raise ValueError("KNOWLEDGE_OUTPUT_CONFLICT")
    else:
        write_jsonl([record], output)
    print("KNOWLEDGE_PROMOTION=PASS RECORDS=1 LIVE_TELEGRAM_READBACK=NOT_VERIFIED")

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"KNOWLEDGE_PROMOTION=FAIL CLASS={type(error).__name__}")
        raise SystemExit(1)
