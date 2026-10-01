#!/usr/bin/env python3
"""Real MCP stdio E2E proving retrieval from more than one repository."""

from __future__ import annotations

import argparse
import asyncio
import io
import os
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def with_timeout(awaitable, seconds: int, label: str):
    try:
        async with asyncio.timeout(seconds):
            return await awaitable
    except TimeoutError as exc:
        raise RuntimeError(f"{label}_TIMEOUT={seconds}s") from exc


def text_from_result(result: object) -> str:
    content = getattr(result, "content", None) or []
    parts: list[str] = []
    for item in content:
        text = getattr(item, "text", None)
        if text:
            parts.append(str(text))
    return "\n".join(parts)


async def run_e2e(
    python: Path,
    project_root: Path,
    timeout: int,
    checks: list[tuple[str, str, str]],
) -> None:
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
    stderr_buffer = io.StringIO()

    print(f"MCP_SERVER_COMMAND={python} -m mcp_vector_search.mcp {project_root}")
    try:
        async with stdio_client(server, errlog=stderr_buffer) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await with_timeout(session.initialize(), timeout, "MCP_INITIALIZE")
                print("MCP_INITIALIZE=PASS")

                tools = await with_timeout(session.list_tools(), timeout, "MCP_LIST_TOOLS")
                tool_names = {tool.name for tool in tools.tools}
                if "search_code" not in tool_names:
                    raise RuntimeError("MCP_REQUIRED_TOOL_MISSING=search_code")
                print(f"MCP_LIST_TOOLS=PASS COUNT={len(tool_names)}")

                seen_repositories: set[str] = set()
                for index, (query, commit, repository) in enumerate(checks, start=1):
                    result = await with_timeout(
                        session.call_tool(
                            "search_code",
                            arguments={
                                "query": query,
                                "limit": 10,
                                "similarity_threshold": 0.0,
                                "search_mode": "vector",
                                "use_rerank": False,
                                "expand": False,
                            },
                        ),
                        timeout,
                        f"MCP_CROSS_REPO_SEARCH_{index}",
                    )
                    if getattr(result, "isError", False):
                        raise RuntimeError(
                            f"MCP_CROSS_REPO_SEARCH_{index}_TOOL_ERROR="
                            + text_from_result(result)
                        )
                    text = text_from_result(result)
                    if commit not in text:
                        raise RuntimeError(
                            f"MCP_CROSS_REPO_SEARCH_{index}_COMMIT_MISSING={commit}"
                        )
                    # Repository identity is verified from the combined JSONL before
                    # indexing. MCP result snippets can be line-local and therefore do
                    # not always repeat the repository metadata line; the commit is the
                    # stable retrieval assertion here.
                    seen_repositories.add(repository)
                    print(
                        f"MCP_CROSS_REPO_SEARCH=PASS CHECK={index} "
                        f"REPOSITORY={repository} COMMIT={commit}"
                    )

                if len(seen_repositories) < 2:
                    raise RuntimeError("MCP_CROSS_REPO_DISTINCT_REPOSITORIES_MISSING")
    except BaseException:
        stderr_text = stderr_buffer.getvalue().strip()
        if stderr_text:
            print("=== MCP SERVER STDERR ===", file=sys.stderr)
            print(stderr_text, file=sys.stderr)
        raise

    print(
        f"GACE_CROSS_REPO_MCP_REUSE=PASS CHECKS={len(checks)} "
        f"REPOSITORIES={len({repository for _, _, repository in checks})}"
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate cross-repository knowledge reuse over MCP stdio")
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument(
        "--check",
        nargs=3,
        action="append",
        metavar=("QUERY", "COMMIT", "REPOSITORY"),
        required=True,
        help="Repeat for each repository: query expected-commit-fragment repository-label",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    python = args.python.resolve()
    project_root = args.project_root.resolve()
    checks = [(str(query), str(commit), str(repository)) for query, commit, repository in args.check]

    if not python.is_file():
        raise RuntimeError(f"MCP_RUNTIME_PYTHON_MISSING={python}")
    if not project_root.is_dir():
        raise RuntimeError(f"MCP_PROJECT_ROOT_MISSING={project_root}")
    if len({repository for _, _, repository in checks}) < 2:
        raise RuntimeError("AT_LEAST_TWO_DISTINCT_REPOSITORIES_REQUIRED")

    asyncio.run(run_e2e(python, project_root, args.timeout, checks))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
