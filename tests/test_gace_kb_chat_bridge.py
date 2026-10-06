#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "gace_kb_chat_bridge.py"
SPEC = importlib.util.spec_from_file_location("gace_kb_chat_bridge", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("BRIDGE_MODULE_LOAD_FAILED")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class ChatKbBridgeTests(unittest.TestCase):
    def test_search_request_is_fail_closed(self):
        value = bridge.validate_request(
            {
                "schema_version": "gace.kb.chat-request.v1",
                "request_id": "req-test-search-001",
                "action": "search",
                "query": "approval routing reusable logic",
                "mode": "hybrid",
                "limit": 7,
                "requested_by": "gpt-chat",
                "requester_repository": "seigo-gace/modular-catalog",
                "requester_project": "Catalog",
                "requester_change_unit": "cross-repo-kb-reuse",
            }
        )
        self.assertEqual(value["mode"], "hybrid")
        self.assertEqual(value["limit"], 7)
        self.assertEqual(value["requester_repository"], "seigo-gace/modular-catalog")
        self.assertEqual(value["requester_project"], "Catalog")
        self.assertEqual(value["requester_change_unit"], "cross-repo-kb-reuse")
        with self.assertRaisesRegex(RuntimeError, "BRIDGE_ACTION_INVALID"):
            bridge.validate_request(
                {
                    "schema_version": "gace.kb.chat-request.v1",
                    "request_id": "req-test-bad-001",
                    "action": "shell",
                }
            )
        with self.assertRaisesRegex(RuntimeError, "BRIDGE_REQUESTER_REPOSITORY_INVALID"):
            bridge.validate_request(
                {
                    "schema_version": "gace.kb.chat-request.v1",
                    "request_id": "req-test-bad-repo-001",
                    "action": "search",
                    "query": "x",
                    "requester_repository": "../unsafe",
                }
            )
        with self.assertRaisesRegex(RuntimeError, "BRIDGE_SEARCH_LIMIT_INVALID"):
            bridge.validate_request(
                {
                    "schema_version": "gace.kb.chat-request.v1",
                    "request_id": "req-test-bad-002",
                    "action": "search",
                    "query": "x",
                    "mode": "bm25",
                    "limit": 500,
                }
            )

    def test_result_echoes_requester_context(self):
        request = bridge.validate_request(
            {
                "schema_version": "gace.kb.chat-request.v1",
                "request_id": "req-test-context-001",
                "action": "search",
                "query": "reuse",
                "requester_repository": "seigo-gace/debug-ai",
                "requester_project": "DebugAI",
                "requester_change_unit": "shared-kb-proof",
            }
        )
        result = bridge.result_envelope(request, "PASS", payload={"ok": True})
        self.assertEqual(result["requester_repository"], "seigo-gace/debug-ai")
        self.assertEqual(result["requester_project"], "DebugAI")
        self.assertEqual(result["requester_change_unit"], "shared-kb-proof")

    def test_exact_returns_metadata_relationships_and_cases(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            metadata = root / "knowledge-metadata.jsonl"
            relationships = root / "relationships.jsonl"
            cases = root / "cases.jsonl"
            metadata.write_text(
                json.dumps(
                    {
                        "knowledge_id": "approval-route-resolver::logic",
                        "parent_asset_id": "approval-route-resolver",
                        "knowledge_kind": "logic",
                        "content": "Resolve approval routing deterministically.",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            relationships.write_text(
                json.dumps(
                    {
                        "relationship_id": "rel-1",
                        "from": "approval-route-resolver",
                        "to": "approval-route-resolver::logic",
                        "relation": "contains",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            cases.write_text(
                json.dumps(
                    {
                        "case_id": "case-1",
                        "parent_asset_id": "approval-route-resolver",
                        "result": "PASS",
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            result = bridge.exact_payload(
                "approval-route-resolver::logic",
                metadata,
                relationships,
                cases,
            )
            self.assertEqual(result["metadata"]["knowledge_kind"], "logic")
            self.assertEqual(len(result["relationships"]), 1)
            self.assertEqual(result["relationships"][0]["relationship_id"], "rel-1")
            self.assertEqual(len(result["cases"]), 1)
            self.assertEqual(result["cases"][0]["case_id"], "case-1")

    def test_exact_requires_unique_knowledge_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            metadata = root / "knowledge-metadata.jsonl"
            relationships = root / "relationships.jsonl"
            cases = root / "cases.jsonl"
            row = {
                "knowledge_id": "dup::logic",
                "parent_asset_id": "dup",
                "knowledge_kind": "logic",
            }
            metadata.write_text(
                json.dumps(row) + "\n" + json.dumps(row) + "\n",
                encoding="utf-8",
            )
            relationships.write_text("", encoding="utf-8")
            cases.write_text("", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "BRIDGE_EXACT_KNOWLEDGE_ID_MATCH_COUNT=2"):
                bridge.exact_payload("dup::logic", metadata, relationships, cases)


if __name__ == "__main__":
    unittest.main()
