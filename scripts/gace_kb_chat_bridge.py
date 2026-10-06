#!/usr/bin/env python3
"""GitHub-relayed CHAT bridge into the active G-ACE KB MCP runtime."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_REQUEST = "gace.kb.chat-request.v1"
SCHEMA_RESULT = "gace.kb.chat-result.v1"
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$")
ALLOWED_MODES = {"bm25", "vector", "hybrid"}
WINDOWS_SAFE_ENV = {
    "MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING": "1",
    "MCP_VECTOR_SEARCH_WORKERS": "1",
    "MCP_VECTOR_SEARCH_MAX_WORKERS": "1",
    "MCP_VECTOR_SEARCH_BATCH_SIZE": "8",
    "MCP_VECTOR_SEARCH_FILE_BATCH_SIZE": "16",
    "OMP_NUM_THREADS": "1",
    "MKL_NUM_THREADS": "1",
    "OPENBLAS_NUM_THREADS": "1",
    "NUMEXPR_NUM_THREADS": "1",
    "TOKENIZERS_PARALLELISM": "false",
}


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("BRIDGE_JSON_OBJECT_REQUIRED")
    return value


def load_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        raise RuntimeError(f"BRIDGE_REQUIRED_JSONL_MISSING={path}")
    rows: list[dict] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise RuntimeError(f"BRIDGE_JSONL_OBJECT_REQUIRED={path}:{number}")
        rows.append(value)
    return rows


def validate_request(value: dict) -> dict:
    if value.get("schema_version") != SCHEMA_REQUEST:
        raise RuntimeError("BRIDGE_REQUEST_SCHEMA_UNSUPPORTED")
    request_id = str(value.get("request_id") or "")
    if not REQUEST_ID_RE.fullmatch(request_id):
        raise RuntimeError("BRIDGE_REQUEST_ID_INVALID")
    action = str(value.get("action") or "")
    if action not in {"search", "exact"}:
        raise RuntimeError("BRIDGE_ACTION_INVALID")
    requester_repository = str(value.get("requester_repository") or "").strip()
    requester_project = str(value.get("requester_project") or "").strip()
    requester_change_unit = str(value.get("requester_change_unit") or "").strip()
    if requester_repository and not REPOSITORY_RE.fullmatch(requester_repository):
        raise RuntimeError("BRIDGE_REQUESTER_REPOSITORY_INVALID")
    if len(requester_project) > 200:
        raise RuntimeError("BRIDGE_REQUESTER_PROJECT_INVALID")
    if len(requester_change_unit) > 300:
        raise RuntimeError("BRIDGE_REQUESTER_CHANGE_UNIT_INVALID")
    normalized = {
        "schema_version": SCHEMA_REQUEST,
        "request_id": request_id,
        "action": action,
        "requested_by": str(value.get("requested_by") or "gpt-chat"),
    }
    if requester_repository:
        normalized["requester_repository"] = requester_repository
    if requester_project:
        normalized["requester_project"] = requester_project
    if requester_change_unit:
        normalized["requester_change_unit"] = requester_change_unit
    if action == "search":
        query = str(value.get("query") or "").strip()
        mode = str(value.get("mode") or "hybrid").lower()
        limit = int(value.get("limit", 10))
        if not query or len(query) > 2000 or any(ord(ch) < 32 and ch not in "\t\n\r" for ch in query):
            raise RuntimeError("BRIDGE_QUERY_INVALID")
        if mode not in ALLOWED_MODES:
            raise RuntimeError("BRIDGE_SEARCH_MODE_INVALID")
        if limit < 1 or limit > 50:
            raise RuntimeError("BRIDGE_SEARCH_LIMIT_INVALID")
        normalized.update(query=query, mode=mode, limit=limit)
    else:
        knowledge_id = str(value.get("knowledge_id") or "").strip()
        if not knowledge_id or len(knowledge_id) > 512:
            raise RuntimeError("BRIDGE_KNOWLEDGE_ID_INVALID")
        normalized["knowledge_id"] = knowledge_id
    return normalized


def exact_payload(
    knowledge_id: str,
    metadata_path: Path,
    relationships_path: Path,
    cases_path: Path,
) -> dict:
    metadata = load_jsonl(metadata_path)
    matches = [row for row in metadata if str(row.get("knowledge_id") or "") == knowledge_id]
    if len(matches) != 1:
        raise RuntimeError(f"BRIDGE_EXACT_KNOWLEDGE_ID_MATCH_COUNT={len(matches)}")
    row = matches[0]
    asset_id = str(row.get("parent_asset_id") or "")
    relationships = [
        rel
        for rel in load_jsonl(relationships_path)
        if str(rel.get("from") or "") in {knowledge_id, asset_id}
        or str(rel.get("to") or "") in {knowledge_id, asset_id}
        or str(rel.get("parent_asset_id") or "") == asset_id
    ]
    cases = [
        case
        for case in load_jsonl(cases_path)
        if str(case.get("parent_asset_id") or "") == asset_id
        or str(case.get("knowledge_id") or "") == knowledge_id
    ]
    return {
        "knowledge_id": knowledge_id,
        "parent_asset_id": asset_id,
        "metadata": row,
        "relationships": relationships,
        "cases": cases,
    }


def text_from_result(result: object) -> str:
    return "\n".join(
        str(getattr(item, "text"))
        for item in (getattr(result, "content", None) or [])
        if getattr(item, "text", None)
    )


async def search_payload(
    python: Path,
    project_root: Path,
    *,
    query: str,
    mode: str,
    limit: int,
    timeout: int,
) -> dict:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    env = dict(os.environ)
    env["MCP_ENABLE_FILE_WATCHING"] = "false"
    env["MCP_PROJECT_ROOT"] = str(project_root)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    if os.name == "nt":
        env.update(WINDOWS_SAFE_ENV)
    server = StdioServerParameters(
        command=str(python),
        args=["-m", "mcp_vector_search.mcp", str(project_root)],
        env=env,
        cwd=str(project_root),
    )
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as errlog:
        try:
            async with stdio_client(server, errlog=errlog) as (read_stream, write_stream):
                async with ClientSession(read_stream, write_stream) as session:
                    async with asyncio.timeout(timeout):
                        init = await session.initialize()
                        tools = await session.list_tools()
                        names = {tool.name for tool in tools.tools}
                        if "search_code" not in names:
                            raise RuntimeError("BRIDGE_MCP_SEARCH_TOOL_MISSING")
                        result = await session.call_tool(
                            "search_code",
                            arguments={
                                "query": query,
                                "limit": limit,
                                "similarity_threshold": 0.0,
                                "search_mode": mode,
                                "use_rerank": False,
                                "expand": False,
                            },
                        )
                    if getattr(result, "isError", False):
                        raise RuntimeError("BRIDGE_MCP_SEARCH_ERROR=" + text_from_result(result)[:2000])
                    info = getattr(init, "server_info", None) or getattr(init, "serverInfo", None)
                    return {
                        "query": query,
                        "mode": mode,
                        "limit": limit,
                        "mcp_server": str(getattr(info, "name", "") or ""),
                        "mcp_text": text_from_result(result),
                    }
        except TimeoutError as exc:
            raise RuntimeError(f"BRIDGE_MCP_TIMEOUT={timeout}s") from exc
        except BaseException:
            errlog.flush()
            errlog.seek(0)
            stderr = errlog.read().strip()
            if stderr:
                print(stderr, file=sys.stderr)
            raise


def result_envelope(request: dict, status: str, payload: dict | None = None, error: str | None = None) -> dict:
    value = {
        "schema_version": SCHEMA_RESULT,
        "request_id": request["request_id"],
        "action": request["action"],
        "status": status,
        "requested_by": request.get("requested_by", "gpt-chat"),
        "requester_repository": request.get("requester_repository"),
        "requester_project": request.get("requester_project"),
        "requester_change_unit": request.get("requester_change_unit"),
        "completed_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    if payload is not None:
        value["result"] = payload
    if error is not None:
        value["error"] = error
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--result", type=Path, required=True)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--relationships", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args(argv)

    request = validate_request(load_json(args.request))
    try:
        if request["action"] == "search":
            if not args.python.is_file():
                raise RuntimeError(f"BRIDGE_RUNTIME_PYTHON_MISSING={args.python}")
            if not args.project_root.is_dir():
                raise RuntimeError(f"BRIDGE_PROJECT_ROOT_MISSING={args.project_root}")
            payload = asyncio.run(
                search_payload(
                    args.python.resolve(),
                    args.project_root.resolve(),
                    query=request["query"],
                    mode=request["mode"],
                    limit=request["limit"],
                    timeout=args.timeout,
                )
            )
        else:
            payload = exact_payload(
                request["knowledge_id"],
                args.metadata.resolve(),
                args.relationships.resolve(),
                args.cases.resolve(),
            )
        result = result_envelope(request, "PASS", payload=payload)
        exit_code = 0
    except Exception as exc:
        result = result_envelope(request, "FAIL", error=f"{type(exc).__name__}: {exc}")
        exit_code = 1

    args.result.parent.mkdir(parents=True, exist_ok=True)
    args.result.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"GACE_KB_CHAT_BRIDGE={result['status']} REQUEST={request['request_id']} "
        f"ACTION={request['action']}"
    )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
