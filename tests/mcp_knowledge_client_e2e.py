#!/usr/bin/env python3
"""Real MCP stdio client E2E for the generated G-ACE knowledge index.

The test launches the installed mcp-vector-search MCP server over stdio,
performs the MCP initialize/list-tools handshake, calls real MCP tools, and
verifies that known repository knowledge is returned through the protocol.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
import tempfile
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


REQUIRED_TOOLS = {"search_code", "get_project_status"}


def text_from_result(result: object) -> str:
    content = getattr(result, "content", None) or []
    parts: list[str] = []
    for item in content:
        text = getattr(item, "text", None)
        if text:
            parts.append(str(text))
    return "\n".join(parts)


async def with_timeout(awaitable, seconds: int, label: str):
    try:
        async with asyncio.timeout(seconds):
            return await awaitable
    except TimeoutError as exc:
        raise RuntimeError(f"{label}_TIMEOUT={seconds}s") from exc


async def run_e2e(python: Path, project_root: Path, timeout: int) -> None:
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

    print(f"MCP_SERVER_COMMAND={python} -m mcp_vector_search.mcp {project_root}")

    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as errlog:
        try:
            async with stdio_client(server, errlog=errlog) as (read_stream, write_stream):
                async with ClientSession(read_stream, write_stream) as session:
                    init_result = await with_timeout(session.initialize(), timeout, "MCP_INITIALIZE")
                    # MCP SDK 2.x exposes snake_case Pydantic attributes while
                    # serialized protocol fields remain camelCase. Support both
                    # so the E2E reports the actual server metadata instead of
                    # a client-side "unknown" display artifact.
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
                    print("MCP_SERVER_INFO=PASS")

                    tools_result = await with_timeout(session.list_tools(), timeout, "MCP_LIST_TOOLS")
                    tool_names = {tool.name for tool in tools_result.tools}
                    missing = REQUIRED_TOOLS - tool_names
                    if missing:
                        raise RuntimeError("MCP_REQUIRED_TOOLS_MISSING=" + ",".join(sorted(missing)))
                    print(f"MCP_LIST_TOOLS=PASS COUNT={len(tool_names)}")

                    status = await with_timeout(
                        session.call_tool("get_project_status", arguments={}),
                        timeout,
                        "MCP_PROJECT_STATUS",
                    )
                    if getattr(status, "isError", False):
                        raise RuntimeError("MCP_PROJECT_STATUS_TOOL_ERROR=" + text_from_result(status))
                    status_text = text_from_result(status)
                    if not status_text.strip():
                        raise RuntimeError("MCP_PROJECT_STATUS_EMPTY")
                    print("MCP_PROJECT_STATUS=PASS")

                    kuzu = await with_timeout(
                        session.call_tool(
                            "search_code",
                            arguments={
                                "query": "normalize Windows paths for Kuzu graph cleanup",
                                "limit": 50,
                                "similarity_threshold": 0.0,
                                "search_mode": "bm25",
                                "use_rerank": False,
                                "expand": False,
                            },
                        ),
                        timeout,
                        "MCP_SEARCH_KUZU",
                    )
                    if getattr(kuzu, "isError", False):
                        raise RuntimeError("MCP_SEARCH_KUZU_TOOL_ERROR=" + text_from_result(kuzu))
                    kuzu_text = text_from_result(kuzu)
                    if "74e8171" not in kuzu_text:
                        raise RuntimeError("MCP_SEARCH_KUZU_RECORD_MISSING")
                    print("MCP_SEARCH_KUZU=PASS COMMIT=74e8171 MODE=bm25")

                    adapter = await with_timeout(
                        session.call_tool(
                            "search_code",
                            arguments={
                                "query": "deterministic G-ACE repository knowledge adapter",
                                "limit": 50,
                                "similarity_threshold": 0.0,
                                "search_mode": "bm25",
                                "use_rerank": False,
                                "expand": False,
                            },
                        ),
                        timeout,
                        "MCP_SEARCH_ADAPTER",
                    )
                    if getattr(adapter, "isError", False):
                        raise RuntimeError("MCP_SEARCH_ADAPTER_TOOL_ERROR=" + text_from_result(adapter))
                    adapter_text = text_from_result(adapter)
                    if "4912a442" not in adapter_text:
                        raise RuntimeError("MCP_SEARCH_ADAPTER_RECORD_MISSING")
                    print("MCP_SEARCH_ADAPTER=PASS COMMIT=4912a442 MODE=bm25")

            errlog.flush()
            errlog.seek(0)
            stderr_text = errlog.read().strip()
            if "Could not find entity matching" in stderr_text:
                raise RuntimeError("MCP_DOC_ONLY_KG_ENTITY_WARNING_PRESENT")
            print("MCP_DOC_ONLY_KG_WARNING_REGRESSION=PASS")
        except BaseException:
            errlog.flush()
            errlog.seek(0)
            stderr_text = errlog.read().strip()
            if stderr_text:
                print("MCP_SERVER_STDERR_BEGIN", file=sys.stderr)
                print(stderr_text, file=sys.stderr)
                print("MCP_SERVER_STDERR_END", file=sys.stderr)
            raise

    print("GACE_MCP_CLIENT_E2E=PASS")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate G-ACE knowledge retrieval over MCP stdio")
    parser.add_argument("--python", type=Path, required=True, help="Python executable containing mcp-vector-search")
    parser.add_argument("--project-root", type=Path, required=True, help="Initialized generated knowledge-search project")
    parser.add_argument("--timeout", type=int, default=180, help="Per-MCP-operation timeout in seconds")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    python = args.python.resolve()
    project_root = args.project_root.resolve()

    if not python.is_file():
        raise RuntimeError(f"MCP_RUNTIME_PYTHON_MISSING={python}")
    if not project_root.is_dir():
        raise RuntimeError(f"MCP_PROJECT_ROOT_MISSING={project_root}")
    config = project_root / ".mcp-vector-search" / "config.json"
    if not config.is_file():
        raise RuntimeError(f"MCP_PROJECT_CONFIG_MISSING={config}")

    asyncio.run(run_e2e(python, project_root, args.timeout))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
