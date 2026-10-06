#!/usr/bin/env python3
from __future__ import annotations
import io
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import tgserver_zero_kb_log as producer


class FakeResponse:
    def __init__(self, payload, status=200):
        self.status = status
        self._payload = json.dumps(payload).encode()
    def read(self, _limit=-1):
        return self._payload
    def __enter__(self):
        return self
    def __exit__(self, *_args):
        return False


class FakeOpener:
    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error
        self.request = None
        self.timeout = None
    def open(self, request, timeout=None):
        self.request = request
        self.timeout = timeout
        if self.error:
            raise self.error
        return self.response


class TgserverZeroKbLogTests(unittest.TestCase):
    def test_builds_fixed_p014_bounded_envelope(self):
        log = producer.build_log(
            request_id="req-001",
            action="search",
            status="PASS",
            duration_ms=123,
            timestamp="2026-10-06T14:00:00Z",
        )
        self.assertEqual(log["project_id"], "P014")
        self.assertEqual(log["severity"], "info")
        self.assertEqual(log["hint"], "gace-kb-runtime")
        message = json.loads(log["message"])
        self.assertEqual(message, {
            "event": "gace-kb.request.completed",
            "request_id": "req-001",
            "action": "search",
            "duration_ms": 123,
            "error_code": None,
        })
        self.assertNotIn("query", message)
        self.assertNotIn("knowledge_id", message)
        self.assertNotIn("result", message)

    def test_failure_only_keeps_bounded_error_code(self):
        log = producer.build_log(
            request_id="req-002",
            action="exact",
            status="FAIL",
            duration_ms=999999999,
            error_code="secret=value",
        )
        message = json.loads(log["message"])
        self.assertEqual(message["duration_ms"], 86_400_000)
        self.assertEqual(message["error_code"], "UNKNOWN")
        self.assertEqual(log["severity"], "error")

    def test_sender_uses_bulk_without_auth_and_validates_receipt(self):
        opener = FakeOpener(FakeResponse({"results": [{"status": "accepted"}]}))
        result = producer.send_log(
            producer.build_log(request_id="req-003", action="search", status="PASS", duration_ms=1),
            env={"TGSERVER_LOG_URL": "http://127.0.0.1:3000", "TGSERVER_LOG_TIMEOUT_MS": "50"},
            opener=opener,
        )
        self.assertEqual(result, {"status": "SENT"})
        self.assertEqual(opener.request.full_url, "http://127.0.0.1:3000/ingest/bulk")
        headers = {k.lower(): v for k, v in opener.request.header_items()}
        self.assertNotIn("authorization", headers)
        body = json.loads(opener.request.data)
        self.assertEqual(body["logs"][0]["project_id"], "P014")

    def test_sender_is_fail_open_when_disabled_or_unavailable(self):
        log = producer.build_log(request_id="req-004", action="search", status="PASS", duration_ms=1)
        self.assertEqual(producer.send_log(log, env={}, opener=FakeOpener()), {"status": "DISABLED"})
        failed = producer.send_log(
            log,
            env={"TGSERVER_LOG_URL": "http://127.0.0.1:3000"},
            opener=FakeOpener(error=OSError("offline")),
        )
        self.assertEqual(failed, {"status": "FAILED", "reason": "TRANSPORT_OR_RECEIPT"})

    def test_receipt_rejects_unknown_status(self):
        with self.assertRaises(ValueError):
            producer.validate_receipt({"results": [{"status": "rejected"}]})


if __name__ == "__main__":
    unittest.main()
