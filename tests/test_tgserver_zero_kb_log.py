#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import tgserver_zero_kb_log as producer


class FakeResponse:
    def __init__(self, payload, status=202):
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
        log = producer.build_zero_log(
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
        for forbidden in ("query", "knowledge_id", "result", "cases", "relationships"):
            self.assertNotIn(forbidden, message)

    def test_failure_keeps_only_bounded_error_code(self):
        log = producer.build_zero_log(
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

    def test_wraps_zero_bulk_envelope_in_generic_internal_event(self):
        log = producer.build_zero_log(
            request_id="req-003",
            action="search",
            status="PASS",
            duration_ms=5,
            timestamp="2026-10-06T14:00:01Z",
        )
        event = producer.build_gateway_event(log)
        self.assertEqual(event["eventId"], "gace-kb:req-003:pass")
        self.assertEqual(event["eventType"], "gace-kb.runtime")
        self.assertEqual(event["sourceId"], "gace-kb-master-pc")
        self.assertEqual(event["destinationId"], "tgserver-zero-bulk")
        self.assertEqual(event["data"], {"logs": [log]})

    def test_sender_uses_gateway_token_and_durable_receipt(self):
        opener = FakeOpener(FakeResponse({
            "ok": True,
            "duplicate": False,
            "eventId": "gateway-row-id",
            "deliveries": 1,
            "enqueueMode": "deferred+outbox",
        }))
        result = producer.send_log(
            producer.build_zero_log(request_id="req-004", action="search", status="PASS", duration_ms=1),
            env={
                "GACE_EVENT_GATEWAY_URL": "https://gateway.example.test",
                "GACE_EVENT_GATEWAY_TOKEN": "test-internal-token",
                "GACE_EVENT_GATEWAY_TIMEOUT_MS": "50",
            },
            opener=opener,
        )
        self.assertEqual(result, {"status": "SENT", "duplicate": False})
        self.assertEqual(opener.request.full_url, "https://gateway.example.test/internal/events")
        headers = {k.lower(): v for k, v in opener.request.header_items()}
        self.assertEqual(headers["authorization"], "Bearer test-internal-token")
        body = json.loads(opener.request.data)
        self.assertEqual(body["destinationId"], "tgserver-zero-bulk")
        self.assertEqual(body["data"]["logs"][0]["project_id"], "P014")
        self.assertNotIn("test-internal-token", opener.request.data.decode())

    def test_sender_is_fail_open_when_unconfigured_or_unavailable(self):
        log = producer.build_zero_log(request_id="req-005", action="search", status="PASS", duration_ms=1)
        self.assertEqual(producer.send_log(log, env={}, opener=FakeOpener()), {"status": "DISABLED"})
        self.assertEqual(
            producer.send_log(
                log,
                env={
                    "GACE_EVENT_GATEWAY_URL": "https://gateway.example.test",
                    "GACE_EVENT_GATEWAY_TOKEN": "token",
                },
                opener=FakeOpener(error=OSError("offline")),
            ),
            {"status": "FAILED", "reason": "TRANSPORT_OR_RECEIPT"},
        )

    def test_rejects_non_durable_gateway_receipt(self):
        with self.assertRaises(ValueError):
            producer.validate_gateway_receipt({"ok": True, "duplicate": False}, 200)
        with self.assertRaises(ValueError):
            producer.validate_gateway_receipt({"ok": False, "duplicate": False}, 202)


if __name__ == "__main__":
    unittest.main()
