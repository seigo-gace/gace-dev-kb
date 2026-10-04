"""PC KB activity through the shared durable producer, never direct TGserver."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import uuid
from devlog_producer import SCHEMA, enqueue, flush, open_outbox
from gace_knowledge_adapter import assert_repository, repository_name, run_git

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--outbox", type=Path, required=True)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--event-type", choices=["ACTIVE", "FAILED", "BLOCKER", "REPLAN", "TEST_RESULT", "CHECKPOINT", "SESSION_END"], required=True)
    parser.add_argument("--enqueue-only", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    assert_repository(repo)
    if args.outbox.resolve().is_relative_to(repo):
        raise ValueError("OUTBOX_MUST_STAY_OUTSIDE_GIT_SOURCE")
    event = {"schema": SCHEMA, "event_id": str(uuid.uuid4()), "occurred_at": datetime.now(timezone.utc).isoformat(),
        "source_surface": "kb", "source_instance": os.getenv("DEVLOG_SOURCE_INSTANCE", "generic-hmac-sha256:devlog"),
        "session_id": args.session_id, "turn_id": None, "change_unit_id": None,
        "project": {"repository": repository_name(repo), "stream": "default"}, "event_type": args.event_type,
        "severity": "error" if args.event_type == "FAILED" else "info", "summary": args.summary, "details": {},
        "evidence": [{"kind": "git", "ref": f"git:{repository_name(repo)}@{run_git(repo, 'rev-parse', 'HEAD').strip()}", "state": "OBSERVED"}],
        "privacy": {"redacted": True, "contains_internal_reasoning": False}}
    database = open_outbox(args.outbox)
    try:
        enqueue(database, event)
        if not args.enqueue_only:
            print(f"GATEWAY_DURABLE_ACCEPTED={flush(database, os.environ['DEVLOG_GATEWAY_URL'], os.environ['DEVLOG_HMAC_SECRET'])}")
    finally:
        database.close()

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"KB_EVENT=FAIL CLASS={type(error).__name__}")
        raise SystemExit(1)
