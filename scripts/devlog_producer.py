"""Reusable stdlib producer: immutable redacted SQLite outbox -> Gateway.

Canonical contract owner: src/ingest/development-event.ts.
No secrets are written to the outbox. No TGserver direct fallback.
"""
from __future__ import annotations
import argparse
import hashlib
import hmac
import json
import os
import re
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

SCHEMA = "gace.development.event.v1"
SENSITIVE_KEY = re.compile(r"authorization|cookie|password|passwd|secret|token|api[_-]?key|private[_-]?key|credential", re.I)
FORBIDDEN_KEY = re.compile(r"^(analysis|reasoning|chain[_-]?of[_-]?thought|internal_reasoning)$", re.I)

def redact(value):
    if isinstance(value, str):
        value = re.sub(r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----", "<REDACTED_PRIVATE_KEY>", value, flags=re.S)
        value = re.sub(r"\b\d{8,12}:[A-Za-z0-9_-]{30,}\b", "<REDACTED_TELEGRAM_TOKEN>", value)
        value = re.sub(r"\bBearer\s+[A-Za-z0-9._~+/=-]+", "Bearer <REDACTED>", value, flags=re.I)
        value = re.sub(r"\b(?:ghp_|github_pat_|whsec_)[A-Za-z0-9_]+", "<REDACTED>", value)
        return re.sub(r"((?:api[_-]?key|token|password|passwd|secret|private[_-]?key|credential)[\"']?\s*[=:]\s*[\"']?)[^\s\"',;]+", r"\1<REDACTED>", value, flags=re.I)
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            if FORBIDDEN_KEY.match(key):
                raise ValueError("INTERNAL_REASONING_FORBIDDEN")
            result[key] = "<REDACTED>" if SENSITIVE_KEY.search(key) else redact(item)
        return result
    return value

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)

def open_outbox(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    database = sqlite3.connect(path)
    os.chmod(path, 0o600)
    database.execute("PRAGMA journal_mode=WAL")
    database.execute("PRAGMA synchronous=FULL")
    database.execute("CREATE TABLE IF NOT EXISTS devlog_outbox (identity TEXT PRIMARY KEY, event_id TEXT NOT NULL, payload TEXT NOT NULL, gateway_accepted INTEGER NOT NULL DEFAULT 0)")
    database.commit()
    return database

def enqueue(database, event):
    clean = redact(event)
    if clean.get("schema") != SCHEMA or not clean.get("event_id") or not clean.get("occurred_at"):
        raise ValueError("INVALID_EVENT_ID_OR_TIME")
    if "ingested_at" in clean or "project_id" in clean.get("project", {}):
        raise ValueError("PRODUCER_AUTHORITY_SPOOF")
    identity = canonical([clean["project"], clean["source_instance"], clean["event_id"]])
    payload = canonical(clean)
    if len(payload.encode("utf-8")) > 900000:
        raise ValueError("DEVELOPMENT_EVENT_TOO_LARGE")
    with database:
        database.execute("INSERT OR IGNORE INTO devlog_outbox(identity,event_id,payload) VALUES(?,?,?)", (identity, clean["event_id"], payload))
        old = database.execute("SELECT payload FROM devlog_outbox WHERE identity=?", (identity,)).fetchone()[0]
        if old != payload:
            raise ValueError("EVENT_ID_CONFLICT")
    return identity

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def flush(database, url, signing_secret, limit=100):
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("INVALID_GATEWAY_URL")
    if not signing_secret:
        raise ValueError("GATEWAY_SIGNATURE_NOT_CONFIGURED")
    if signing_secret.startswith("base64:"):
        import base64
        key = base64.b64decode(signing_secret[7:], validate=True)
    else:
        key = signing_secret.encode("utf-8")
    if len(key) < 32:
        raise ValueError("GATEWAY_SIGNATURE_CONTRACT_INVALID")
    count = 0
    opener = urllib.request.build_opener(NoRedirect)
    for identity, event_id, payload in database.execute("SELECT identity,event_id,payload FROM devlog_outbox WHERE gateway_accepted=0 ORDER BY rowid LIMIT ?", (limit,)).fetchall():
        # Fresh transport signature; original event ID, occurrence time and bytes stay fixed.
        timestamp = str(int(time.time()))
        body = payload.encode("utf-8")
        signature = hmac.new(key, timestamp.encode()+b"."+body, hashlib.sha256).hexdigest()
        request = urllib.request.Request(url, data=body, method="POST", headers={
            "Content-Type": "application/json", "x-event-id": event_id,
            "x-timestamp": timestamp, "x-signature": "sha256="+signature,
            "x-event-type": "gace.development."+json.loads(payload)["event_type"]})
        with opener.open(request, timeout=30) as response:
            result = json.loads(response.read(65536))
            if response.status != 202 or result.get("ok") is not True or not (
                result.get("spooled") is True or (isinstance(result.get("eventId"), str) and result.get("eventId"))):
                raise RuntimeError("INVALID_GATEWAY_DURABLE_RECEIPT")
        with database:
            database.execute("UPDATE devlog_outbox SET gateway_accepted=1 WHERE identity=?", (identity,))
        count += 1
    return count

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outbox", type=Path, required=True)
    parser.add_argument("--input", type=Path, help="canonical JSON event; omit to retry only")
    parser.add_argument("--enqueue-only", action="store_true")
    args = parser.parse_args()
    database = open_outbox(args.outbox)
    try:
        if args.input:
            enqueue(database, json.loads(args.input.read_text(encoding="utf-8")))
        if not args.enqueue_only:
            count = flush(database, os.environ["DEVLOG_GATEWAY_URL"], os.environ["DEVLOG_HMAC_SECRET"])
            print(f"GATEWAY_DURABLE_ACCEPTED={count}")
    finally:
        database.close()

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Provider bodies and URLs may contain secrets. Report class only.
        print(f"DEVLOG_PRODUCER=FAIL CLASS={type(error).__name__}", file=sys.stderr)
        raise SystemExit(1)
