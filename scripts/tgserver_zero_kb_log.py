#!/usr/bin/env python3
"""Bounded TGserver ZERO runtime-log producer for G-ACE KB."""
from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone

PROJECT_ID = "P014"
HINT = "gace-kb-runtime"
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
ACTIONS = {"search", "exact"}
STATUSES = {"PASS", "FAIL"}
ERROR_CODE_RE = re.compile(r"^[A-Z0-9_]{1,64}$")
DEFAULT_TIMEOUT_MS = 1500
MAX_TIMEOUT_MS = 10000


def build_bulk_url(value: str) -> str:
    base = str(value or "").strip().rstrip("/")
    if not base:
        raise ValueError("TGSERVER_LOG_URL_EMPTY")
    if base.endswith("/ingest/bulk"):
        return base
    if base.endswith("/ingest"):
        return base + "/bulk"
    return base + "/ingest/bulk"


def normalize_error_code(value: str | None) -> str | None:
    if value is None:
        return None
    code = str(value).strip().upper()
    return code if ERROR_CODE_RE.fullmatch(code) else "UNKNOWN"


def build_log(*, request_id: str, action: str, status: str, duration_ms: int, error_code: str | None = None, timestamp: str | None = None) -> dict:
    if not REQUEST_ID_RE.fullmatch(request_id):
        raise ValueError("REQUEST_ID_INVALID")
    if action not in ACTIONS:
        raise ValueError("ACTION_INVALID")
    if status not in STATUSES:
        raise ValueError("STATUS_INVALID")
    bounded_duration = max(0, min(int(duration_ms), 86_400_000))
    event = {
        "event": "gace-kb.request.completed" if status == "PASS" else "gace-kb.request.failed",
        "request_id": request_id,
        "action": action,
        "duration_ms": bounded_duration,
        "error_code": normalize_error_code(error_code) if status == "FAIL" else None,
    }
    return {
        "project_id": PROJECT_ID,
        "severity": "info" if status == "PASS" else "error",
        "message": json.dumps(event, ensure_ascii=False, separators=(",", ":")),
        "hint": HINT,
        "timestamp": timestamp or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }


def validate_receipt(payload: object, expected_count: int = 1) -> None:
    if not isinstance(payload, dict) or not isinstance(payload.get("results"), list):
        raise ValueError("TGSERVER_RECEIPT_INVALID")
    results = payload["results"]
    if len(results) != expected_count:
        raise ValueError("TGSERVER_RECEIPT_COUNT_MISMATCH")
    if any(not isinstance(item, dict) or item.get("status") not in {"accepted", "duplicate"} for item in results):
        raise ValueError("TGSERVER_RECEIPT_REJECTED")


def timeout_seconds(env: dict[str, str]) -> float:
    raw = env.get("TGSERVER_LOG_TIMEOUT_MS", str(DEFAULT_TIMEOUT_MS))
    try:
        ms = int(raw)
    except ValueError:
        ms = DEFAULT_TIMEOUT_MS
    ms = max(1, min(ms, MAX_TIMEOUT_MS))
    return ms / 1000.0


def send_log(log: dict, *, env: dict[str, str] | None = None, opener=None) -> dict:
    current_env = dict(os.environ if env is None else env)
    configured = str(current_env.get("TGSERVER_LOG_URL") or "").strip()
    if not configured:
        return {"status": "DISABLED"}
    body = json.dumps({"logs": [log]}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        build_bulk_url(configured),
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    client = opener or urllib.request.build_opener()
    try:
        with client.open(request, timeout=timeout_seconds(current_env)) as response:
            if getattr(response, "status", None) != 200:
                return {"status": "FAILED", "reason": "HTTP_STATUS"}
            payload = json.loads(response.read(65536))
        validate_receipt(payload, 1)
        return {"status": "SENT"}
    except Exception:
        return {"status": "FAILED", "reason": "TRANSPORT_OR_RECEIPT"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--action", choices=sorted(ACTIONS), required=True)
    parser.add_argument("--status", choices=sorted(STATUSES), required=True)
    parser.add_argument("--duration-ms", type=int, required=True)
    parser.add_argument("--error-code")
    args = parser.parse_args()
    try:
        log = build_log(
            request_id=args.request_id,
            action=args.action,
            status=args.status,
            duration_ms=args.duration_ms,
            error_code=args.error_code,
        )
        result = send_log(log)
        print(f"GACE_KB_TGZERO_LOG={result['status']} PROJECT_ID={PROJECT_ID} REQUEST={args.request_id} ACTION={args.action}")
        return 0
    except Exception as exc:
        print(f"GACE_KB_TGZERO_LOG=FAILED CLASS={type(exc).__name__}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
