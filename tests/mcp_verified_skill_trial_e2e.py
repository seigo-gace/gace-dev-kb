#!/usr/bin/env python3
"""Real MCP stdio retrieval gate for the DebugAI verified-skill trial corpus."""

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


NATURAL_CHECKS = (
    (
        "CROSS_FILE_DEPENDENCY",
        "cross file dependency closure trace changed files",
        "crossFileDependencyTrace",
    ),
    (
        "FALSE_PASS",
        "false pass skipped test assertion mutation detector",
        "falsePassDetector",
    ),
    (
        "TARGETED_REGRESSION",
        "targeted regression adjacent full relevant tests strategy",
        "targetedRegressionStrategy",
    ),
)


def text_from_result(result: object) -> str:
    parts: list[str] = []
    for item in getattr(result, "content", None) or []:
        text = getattr(item, "text", None)
        if text:
            parts.append(str(text))
    return "\n".join(parts)


def load_records(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    if not rows:
        raise RuntimeError("SKILL_KNOWLEDGE_RECORDS_EMPTY")
    return rows


def skill_symbol(record: dict[str, str]) -> str:
    source = str(record.get("source") or "")
    if "::" not in source:
        raise RuntimeError(f"SKILL_SOURCE_SYMBOL_MISSING={source}")
    return source.rsplit("::", 1)[1]


async def with_timeout(awaitable, seconds: int, label: str):
    try:
        async with asyncio.timeout(seconds):
            return await awaitable
    except TimeoutError as exc:
        raise RuntimeError(f"{label}_TIMEOUT={seconds}s") from exc


async def run_e2e(
    python: Path,
    project_root: Path,
    records_path: Path,
    expected_count: int,
    timeout: int,
) -> None:
    records = load_records(records_path)
    if len(records) != expected_count:
        raise RuntimeError(
            f"SKILL_KNOWLEDGE_RECORD_COUNT_MISMATCH expected={expected_count} actual={len(records)}"
        )

    env = dict(os.environ)
    env["MCP_ENABLE_FILE_WATCHING"] = "false"
    env["MCP_PROJECT_ROOT"] = str(project_root)
    env["PYTHONDONTWRITEBYTECODE"] = "1"

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
                    init_result = await with_timeout(
                        session.initialize(), timeout, "MCP_INITIALIZE"
                    )
                    server_info = getattr(init_result, "server_info", None) or getattr(
                        init_result, "serverInfo", None
                    )
                    server_name = getattr(server_info, "name", None) if server_info else None
                    server_version = (
                        getattr(server_info, "version", None) if server_info else None
                    )
                    if not server_name or not server_version:
                        raise RuntimeError("MCP_SERVER_INFO_MISSING")
                    print(
                        f"MCP_INITIALIZE=PASS SERVER={server_name} VERSION={server_version}"
                    )

                    tools_result = await with_timeout(
                        session.list_tools(), timeout, "MCP_LIST_TOOLS"
                    )
                    tool_names = {tool.name for tool in tools_result.tools}
                    if "search_code" not in tool_names:
                        raise RuntimeError("MCP_SEARCH_CODE_TOOL_MISSING")
                    print(f"MCP_LIST_TOOLS=PASS COUNT={len(tool_names)}")

                    for record in records:
                        symbol = skill_symbol(record)
                        query = str(record.get("summary") or symbol)
                        result = await with_timeout(
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
                            f"MCP_SKILL_{symbol}",
                        )
                        if getattr(result, "isError", False):
                            raise RuntimeError(
                                f"MCP_SKILL_TOOL_ERROR={symbol}:{text_from_result(result)}"
                            )
                        text = text_from_result(result)
                        if symbol not in text:
                            raise RuntimeError(f"MCP_SKILL_NOT_RETRIEVED={symbol}")
                        print(f"MCP_SKILL_SEARCH=PASS SKILL={symbol}")

                    for label, query, expected_symbol in NATURAL_CHECKS:
                        result = await with_timeout(
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
                            f"MCP_NATURAL_{label}",
                        )
                        if getattr(result, "isError", False):
                            raise RuntimeError(
                                f"MCP_NATURAL_TOOL_ERROR={label}:{text_from_result(result)}"
                            )
                        text = text_from_result(result)
                        if expected_symbol not in text:
                            raise RuntimeError(
                                f"MCP_NATURAL_EXPECTED_SKILL_MISSING={label}:{expected_symbol}"
                            )
                        print(
                            f"MCP_NATURAL_SEARCH=PASS CHECK={label} SKILL={expected_symbol}"
                        )

            errlog.flush()
            errlog.seek(0)
            stderr_text = errlog.read().strip()
            if "Could not find entity matching" in stderr_text:
                raise RuntimeError("MCP_DOC_ONLY_KG_ENTITY_WARNING_PRESENT")
        except BaseException:
            errlog.flush()
            errlog.seek(0)
            stderr_text = errlog.read().strip()
            if stderr_text:
                print("MCP_SERVER_STDERR_BEGIN", file=sys.stderr)
                print(stderr_text, file=sys.stderr)
                print("MCP_SERVER_STDERR_END", file=sys.stderr)
            raise

    print(
        f"GACE_DEBUGAI_SKILL_MCP_E2E=PASS RECORDS={len(records)} "
        f"NATURAL_CHECKS={len(NATURAL_CHECKS)}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--records", type=Path, required=True)
    parser.add_argument("--expected-count", type=int, default=13)
    parser.add_argument("--timeout", type=int, default=180)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    python = args.python.resolve()
    project_root = args.project_root.resolve()
    records = args.records.resolve()
    if not python.is_file():
        raise RuntimeError(f"MCP_RUNTIME_PYTHON_MISSING={python}")
    if not project_root.is_dir():
        raise RuntimeError(f"MCP_PROJECT_ROOT_MISSING={project_root}")
    if not records.is_file():
        raise RuntimeError(f"SKILL_RECORDS_MISSING={records}")
    if not (project_root / ".mcp-vector-search" / "config.json").is_file():
        raise RuntimeError("MCP_PROJECT_CONFIG_MISSING")

    asyncio.run(
        run_e2e(
            python,
            project_root,
            records,
            args.expected_count,
            args.timeout,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
