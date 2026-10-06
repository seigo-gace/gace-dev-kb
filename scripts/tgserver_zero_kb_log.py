#!/usr/bin/env python3
"""Bounded G-ACE KB runtime-log producer through the generic Webhook Gateway."""
from __future__ import annotations

import argparse
import json
import os
import re
import urllib.request
from datetime import datetime, timezone

PROJECT_ID = "P014"
HINT = "gace-kb-runtime"
SOURCE_ID = "gace-kb-master-pc"
DESTINATION_ID = "tgserver-zero-bulk"
EVENT_TYPE = "gace-kb.runtime"
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
ACTIONS = {"search", "exact"}
STATUSES = {"PASS", "FAIL"}
ERROR_CODE_RE = re.compile(r"^[A-Z0-9_]{1,64}$")
DEFAULT_TIMEOUT_MS = 1500
MAX_TIMEOUT_MS = 10000


def gateway_url(value: str) -> str:
    base = str(value or "").strip().rstrip("/")
    if not base:
        raise ValueError("GATEWAY_URL_EMPTY")
    if base.endswith("/internal/events"):
        return base
    return base + "/internal/events"


def normalize_error_code(value: str | None) -> str | None:
    if value is None:
        return None
    code = str(value).strip().upper()
    return code if ERROR_CODE_RE.fullmatch(code) else "UNKNOWN"


def build_zero_log(*, request_id: str, action: str, status: str, duration_ms: int,
                   error_code: str | None = None, timestamp: str | None = None) -> dict:
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


def build_gateway_event(log: dict) -> dict:
    message = json.loads(str(log["message"]))
    request_id = str(message["request_id"])
    status = "PASS" if str(log["severity"]) == "info" else "FAIL"
    return {
        "eventId": f"gace-kb:{request_id}:{status.lower()}",
        "eventType": EVENT_TYPE,
        "sourceId": SOURCE_ID,
        "destinationId": DESTINATION_ID,
        "subject": f"request/{request_id}",
        "time": str(log["timestamp"]),
        "data": {"logs": [log]},
    }


def timeout_seconds(env: dict[str, str]) -> float:
    raw = env.get("GACE_EVENT_GATEWAY_TIMEOUT_MS", str(DEFAULT_TIMEOUT_MS))
    try:
        ms = int(raw)
    except ValueError:
        ms = DEFAULT_TIMEOUT_MS
    return max(1, min(ms, MAX_TIMEOUT_MS)) / 1000.0


def validate_gateway_receipt(payload: object, status: int) -> None:
    if status != 202 or not isinstance(payload, dict) or payload.get("ok") is not True:
        raise ValueError("GATEWAY_DURABLE_RECEIPT_INVALID")
    if payload.get("duplicate") not in {True, False}:
        raise ValueError("GATEWAY_DUPLICATE_STATE_INVALID")


def send_log(log: dict, *, env: dict[str, str] | None = None, opener=None) -> dict:
    current_env = dict(os.environ if env is None else env)
    configured_url = str(current_env.get("GACE_EVENT_GATEWAY_URL") or "").strip()
    token = str(current_env.get("GACE_EVENT_GATEWAY_TOKEN") or "").strip()
    if not configured_url or not token:
        return {"status": "DISABLED"}
    event = build_gateway_event(log)
    body = json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        gateway_url(configured_url),
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
    )
    client = opener or urllib.request.build_opener()
    try:
        with client.open(request, timeout=timeout_seconds(current_env)) as response:
            status = int(getattr(response, "status", 0) or 0)
            payload = json.loads(response.read(65536))
        validate_gateway_receipt(payload, status)
        return {"status": "SENT", "duplicate": bool(payload["duplicate"])}
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
        log = build_zero_log(
            request_id=args.request_id,
            action=args.action,
            status=args.status,
            duration_ms=args.duration_ms,
            error_code=args.error_code,
        )
        result = send_log(log)
        print(
            f"GACE_KB_TGZERO_LOG={result['status']} PROJECT_ID={PROJECT_ID} "
            f"REQUEST={args.request_id} ACTION={args.action} VIA=GENERIC_GATEWAY"
        )
        return 0
    except Exception as exc:
        print(f"GACE_KB_TGZERO_LOG=FAILED CLASS={type(exc).__name__} VIA=GENERIC_GATEWAY")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
