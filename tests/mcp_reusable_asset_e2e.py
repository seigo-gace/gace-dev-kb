#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import tempfile
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


def text_from_result(result):
    return "\n".join(
        str(getattr(item, "text"))
        for item in (getattr(result, "content", None) or [])
        if getattr(item, "text", None)
    )


def load(path: Path):
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows:
        raise RuntimeError("REUSABLE_ASSET_METADATA_EMPTY")
    return rows


def natural_query(row):
    discovery = row.get("discovery") if isinstance(row.get("discovery"), dict) else {}
    terms = []
    for key in ("capabilities", "keywords", "semantic_terms"):
        values = discovery.get(key)
        if isinstance(values, list):
            terms.extend(str(value) for value in values if str(value).strip())
    for key in ("purpose", "responsibility", "summary"):
        if discovery.get(key):
            terms.append(str(discovery[key]))
    for key in ("name", "knowledge_kind", "content"):
        if row.get(key):
            terms.append(str(row[key]))
    return " ".join(terms).strip()


async def wait(awaitable, seconds, label):
    try:
        async with asyncio.timeout(seconds):
            return await awaitable
    except TimeoutError as exc:
        raise RuntimeError(f"{label}_TIMEOUT={seconds}s") from exc


async def run(python: Path, root: Path, metadata: Path, expected: int, timeout: int):
    rows = load(metadata)
    if len(rows) != expected:
        raise RuntimeError(f"REUSABLE_ASSET_COUNT_MISMATCH expected={expected} actual={len(rows)}")

    ids = [str(row.get("knowledge_id") or "") for row in rows]
    if any(not value for value in ids):
        raise RuntimeError("REUSABLE_ASSET_KNOWLEDGE_ID_MISSING")
    if len(set(ids)) != len(ids):
        raise RuntimeError("REUSABLE_ASSET_KNOWLEDGE_ID_DUPLICATE")

    env = dict(os.environ)
    env["MCP_ENABLE_FILE_WATCHING"] = "false"
    env["MCP_PROJECT_ROOT"] = str(root)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    server = StdioServerParameters(
        command=str(python),
        args=["-m", "mcp_vector_search.mcp", str(root)],
        env=env,
        cwd=str(root),
    )

    kind_first = {}
    asset_ids = set()
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as errlog:
        try:
            async with stdio_client(server, errlog=errlog) as (read_stream, write_stream):
                async with ClientSession(read_stream, write_stream) as session:
                    init = await wait(session.initialize(), timeout, "MCP_INITIALIZE")
                    info = getattr(init, "server_info", None) or getattr(init, "serverInfo", None)
                    if not info:
                        raise RuntimeError("MCP_SERVER_INFO_MISSING")
                    tools = await wait(session.list_tools(), timeout, "MCP_LIST_TOOLS")
                    names = {tool.name for tool in tools.tools}
                    if "search_code" not in names:
                        raise RuntimeError("MCP_SEARCH_CODE_TOOL_MISSING")
                    print(f"MCP_REUSABLE_INITIALIZE=PASS TOOLS={len(names)}")

                    for row in rows:
                        knowledge_id = str(row["knowledge_id"])
                        parent_asset_id = str(row.get("parent_asset_id") or "")
                        if not parent_asset_id:
                            raise RuntimeError(f"REUSABLE_ASSET_PARENT_ID_MISSING={knowledge_id}")
                        asset_ids.add(parent_asset_id)
                        knowledge_kind = str(row.get("knowledge_kind") or "unknown")
                        kind_first.setdefault(knowledge_kind, row)
                        result = await wait(
                            session.call_tool(
                                "search_code",
                                arguments={
                                    "query": knowledge_id,
                                    "limit": 50,
                                    "similarity_threshold": 0.0,
                                    "search_mode": "bm25",
                                    "use_rerank": False,
                                    "expand": False,
                                },
                            ),
                            timeout,
                            f"MCP_REUSABLE_{knowledge_id}",
                        )
                        if getattr(result, "isError", False):
                            raise RuntimeError(
                                f"MCP_REUSABLE_TOOL_ERROR={knowledge_id}:{text_from_result(result)}"
                            )
                        if knowledge_id not in text_from_result(result):
                            raise RuntimeError(f"MCP_REUSABLE_NOT_RETRIEVED={knowledge_id}")
                    print(
                        f"MCP_REUSABLE_EXACT_SEARCH=PASS RECORDS={len(rows)} ASSETS={len(asset_ids)}"
                    )

                    natural = 0
                    for knowledge_kind, row in sorted(kind_first.items()):
                        query = natural_query(row)
                        knowledge_id = str(row["knowledge_id"])
                        if not query:
                            raise RuntimeError(
                                f"MCP_REUSABLE_NATURAL_QUERY_EMPTY kind={knowledge_kind} id={knowledge_id}"
                            )
                        result = await wait(
                            session.call_tool(
                                "search_code",
                                arguments={
                                    "query": query,
                                    "limit": 50,
                                    "similarity_threshold": 0.0,
                                    "search_mode": "bm25",
                                    "use_rerank": False,
                                    "expand": False,
                                },
                            ),
                            timeout,
                            f"MCP_REUSABLE_NATURAL_{knowledge_kind}",
                        )
                        if getattr(result, "isError", False):
                            raise RuntimeError(
                                f"MCP_REUSABLE_NATURAL_TOOL_ERROR={knowledge_kind}"
                            )
                        if knowledge_id not in text_from_result(result):
                            raise RuntimeError(
                                f"MCP_REUSABLE_NATURAL_EXPECTED_MISSING kind={knowledge_kind} id={knowledge_id}"
                            )
                        natural += 1
                        print(
                            f"MCP_REUSABLE_NATURAL_SEARCH=PASS KIND={knowledge_kind} ID={knowledge_id}"
                        )

            errlog.flush()
            errlog.seek(0)
            stderr = errlog.read()
            if "Could not find entity matching" in stderr:
                raise RuntimeError("MCP_DOC_ONLY_KG_ENTITY_WARNING_PRESENT")
        except BaseException:
            errlog.flush()
            errlog.seek(0)
            stderr = errlog.read().strip()
            if stderr:
                print(stderr, file=sys.stderr)
            raise

    print(
        f"GACE_REUSABLE_ASSET_MCP_E2E=PASS RECORDS={len(rows)} ASSETS={len(asset_ids)} "
        f"KNOWLEDGE_KINDS={len(kind_first)} NATURAL_CHECKS={natural}"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--expected-count", type=int, required=True)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    if not args.python.is_file():
        raise RuntimeError(f"MCP_RUNTIME_PYTHON_MISSING={args.python}")
    if not args.project_root.is_dir():
        raise RuntimeError(f"MCP_PROJECT_ROOT_MISSING={args.project_root}")
    if not args.metadata.is_file():
        raise RuntimeError(f"REUSABLE_ASSET_METADATA_MISSING={args.metadata}")
    asyncio.run(
        run(
            args.python.resolve(),
            args.project_root.resolve(),
            args.metadata.resolve(),
            args.expected_count,
            args.timeout,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
