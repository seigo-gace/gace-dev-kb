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

REQUIRED_TOOLS = {"search_code", "kg_stats", "kg_query"}
KG_RUNTIME_TAG = "gace-reusable-asset"


def text_from_result(result):
    return "\n".join(
        str(getattr(item, "text"))
        for item in (getattr(result, "content", None) or [])
        if getattr(item, "text", None)
    )


def json_from_result(result, label):
    text = text_from_result(result).strip()
    if not text:
        raise RuntimeError(f"{label}_EMPTY")
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{label}_NON_JSON={text[:500]}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"{label}_JSON_OBJECT_REQUIRED")
    return value


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
    for key in ("name", "knowledge_kind"):
        if row.get(key):
            terms.append(str(row[key]))
    content = str(row.get("content") or "").strip()
    if content:
        terms.append(content[:600])
    return " ".join(terms).strip()


def first_embedded_probe(rows, collection_key, id_key):
    for row in rows:
        values = row.get(collection_key)
        if not isinstance(values, list):
            continue
        for value in values:
            if not isinstance(value, dict):
                continue
            probe_id = str(value.get(id_key) or "").strip()
            if probe_id:
                return row, value, probe_id
    return None


def first_cross_unit_relationship_probe(rows):
    known_units = {str(row.get("knowledge_id") or "") for row in rows}
    known_units.discard("")
    for row in rows:
        current = str(row.get("knowledge_id") or "")
        values = row.get("relationships")
        if not isinstance(values, list):
            continue
        for value in values:
            if not isinstance(value, dict):
                continue
            source = str(value.get("from") or "")
            target = str(value.get("to") or "")
            relation_id = str(value.get("relationship_id") or "")
            if (
                relation_id
                and source in known_units
                and target in known_units
                and source != target
                and current in {source, target}
            ):
                return row, value, relation_id
    return None


async def wait(awaitable, seconds, label):
    try:
        async with asyncio.timeout(seconds):
            return await awaitable
    except TimeoutError as exc:
        raise RuntimeError(f"{label}_TIMEOUT={seconds}s") from exc


async def search_and_require(
    session,
    *,
    query: str,
    knowledge_id: str,
    mode: str,
    timeout: int,
    label: str,
):
    result = await wait(
        session.call_tool(
            "search_code",
            arguments={
                "query": query,
                "limit": 50,
                "similarity_threshold": 0.0,
                "search_mode": mode,
                "use_rerank": False,
                "expand": False,
            },
        ),
        timeout,
        label,
    )
    if getattr(result, "isError", False):
        raise RuntimeError(f"{label}_TOOL_ERROR={text_from_result(result)}")
    text = text_from_result(result)
    if knowledge_id not in text:
        raise RuntimeError(
            f"{label}_EXPECTED_MISSING mode={mode} id={knowledge_id}"
        )
    return text


async def run(python: Path, root: Path, metadata: Path, expected: int, timeout: int):
    rows = load(metadata)
    if len(rows) != expected:
        raise RuntimeError(f"REUSABLE_ASSET_COUNT_MISMATCH expected={expected} actual={len(rows)}")

    ids = [str(row.get("knowledge_id") or "") for row in rows]
    if any(not value for value in ids):
        raise RuntimeError("REUSABLE_ASSET_KNOWLEDGE_ID_MISSING")
    if len(set(ids)) != len(ids):
        raise RuntimeError("REUSABLE_ASSET_KNOWLEDGE_ID_DUPLICATE")

    case_probe = first_embedded_probe(rows, "cases", "case_id")
    relationship_probe = first_embedded_probe(rows, "relationships", "relationship_id")
    cross_unit_relationship_probe = first_cross_unit_relationship_probe(rows)

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
                    missing = REQUIRED_TOOLS - names
                    if missing:
                        raise RuntimeError(
                            "MCP_REUSABLE_REQUIRED_TOOLS_MISSING=" + ",".join(sorted(missing))
                        )
                    print(f"MCP_REUSABLE_INITIALIZE=PASS TOOLS={len(names)}")

                    # Every Knowledge Unit must remain exactly retrievable by stable ID.
                    for row in rows:
                        knowledge_id = str(row["knowledge_id"])
                        parent_asset_id = str(row.get("parent_asset_id") or "")
                        if not parent_asset_id:
                            raise RuntimeError(f"REUSABLE_ASSET_PARENT_ID_MISSING={knowledge_id}")
                        asset_ids.add(parent_asset_id)
                        knowledge_kind = str(row.get("knowledge_kind") or "unknown")
                        kind_first.setdefault(knowledge_kind, row)
                        await search_and_require(
                            session,
                            query=knowledge_id,
                            knowledge_id=knowledge_id,
                            mode="bm25",
                            timeout=timeout,
                            label=f"MCP_REUSABLE_BM25_{knowledge_id}",
                        )
                    print(
                        f"MCP_REUSABLE_EXACT_BM25=PASS RECORDS={len(rows)} ASSETS={len(asset_ids)}"
                    )

                    # Structured case/relationship sidecars are not archival-only: their
                    # stable IDs are rendered into the existing searchable corpus.
                    case_checks = 0
                    if case_probe:
                        row, _case, case_id = case_probe
                        await search_and_require(
                            session,
                            query=case_id,
                            knowledge_id=str(row["knowledge_id"]),
                            mode="bm25",
                            timeout=timeout,
                            label=f"MCP_REUSABLE_CASE_{case_id}",
                        )
                        case_checks = 1
                        print(
                            f"MCP_REUSABLE_CASE_SEARCH=PASS CASE={case_id} "
                            f"ID={row['knowledge_id']}"
                        )
                    else:
                        print("MCP_REUSABLE_CASE_SEARCH=PASS CASES=0 SKIP=NO_EMBEDDED_CASE")

                    relationship_checks = 0
                    if relationship_probe:
                        row, _rel, relationship_id = relationship_probe
                        await search_and_require(
                            session,
                            query=relationship_id,
                            knowledge_id=str(row["knowledge_id"]),
                            mode="bm25",
                            timeout=timeout,
                            label=f"MCP_REUSABLE_RELATIONSHIP_{relationship_id}",
                        )
                        relationship_checks = 1
                        print(
                            f"MCP_REUSABLE_RELATIONSHIP_SEARCH=PASS RELATIONSHIP={relationship_id} "
                            f"ID={row['knowledge_id']}"
                        )
                    else:
                        print(
                            "MCP_REUSABLE_RELATIONSHIP_SEARCH=PASS RELATIONSHIPS=0 "
                            "SKIP=NO_EMBEDDED_RELATIONSHIP"
                        )

                    # One representative of every Knowledge Kind must be usable through
                    # all three existing retrieval modes, not BM25 alone.
                    natural = 0
                    vector = 0
                    hybrid = 0
                    for knowledge_kind, row in sorted(kind_first.items()):
                        query = natural_query(row)
                        knowledge_id = str(row["knowledge_id"])
                        if not query:
                            raise RuntimeError(
                                f"MCP_REUSABLE_NATURAL_QUERY_EMPTY kind={knowledge_kind} id={knowledge_id}"
                            )
                        for mode in ("bm25", "vector", "hybrid"):
                            await search_and_require(
                                session,
                                query=query,
                                knowledge_id=knowledge_id,
                                mode=mode,
                                timeout=timeout,
                                label=f"MCP_REUSABLE_{mode.upper()}_{knowledge_kind}",
                            )
                            if mode == "bm25":
                                natural += 1
                            elif mode == "vector":
                                vector += 1
                            else:
                                hybrid += 1
                        print(
                            f"MCP_REUSABLE_MULTI_MODE_SEARCH=PASS KIND={knowledge_kind} "
                            f"ID={knowledge_id} MODES=bm25,vector,hybrid"
                        )

                    # MVS 4.1.14 kg_stats exposes total_entities + relationships but not
                    # doc-section count. Document presence is therefore proven by the
                    # following tag query, not by an unsupported stats field.
                    kg_stats = await wait(
                        session.call_tool("kg_stats", arguments={}),
                        timeout,
                        "MCP_REUSABLE_KG_STATS",
                    )
                    if getattr(kg_stats, "isError", False):
                        raise RuntimeError(
                            "MCP_REUSABLE_KG_STATS_TOOL_ERROR=" + text_from_result(kg_stats)
                        )
                    stats = json_from_result(kg_stats, "MCP_REUSABLE_KG_STATS")
                    if str(stats.get("status") or "").lower() not in {"success", "ok"}:
                        raise RuntimeError(f"MCP_REUSABLE_KG_STATS_STATUS_INVALID={stats}")
                    statistics = stats.get("statistics") if isinstance(stats.get("statistics"), dict) else {}
                    total_entities = int(statistics.get("total_entities", 0) or 0)
                    if total_entities <= 0:
                        raise RuntimeError(f"MCP_REUSABLE_KG_EMPTY entities={total_entities}")

                    relationship_stats = (
                        statistics.get("relationships")
                        if isinstance(statistics.get("relationships"), dict)
                        else {}
                    )
                    normalized_relationship_stats = {
                        str(key).lower(): int(value or 0)
                        for key, value in relationship_stats.items()
                    }
                    if cross_unit_relationship_probe:
                        links_to = normalized_relationship_stats.get("links_to", 0)
                        if links_to <= 0:
                            raise RuntimeError(
                                "MCP_REUSABLE_KG_RELATION_LINKS_MISSING="
                                f"{normalized_relationship_stats}"
                            )
                        print(f"MCP_REUSABLE_KG_RELATION_LINKS=PASS LINKS_TO={links_to}")
                    else:
                        print(
                            "MCP_REUSABLE_KG_RELATION_LINKS=PASS SKIP=NO_CROSS_UNIT_RELATIONSHIP"
                        )
                    print(f"MCP_REUSABLE_KG_STATS=PASS ENTITIES={total_entities}")

                    kg_query = await wait(
                        session.call_tool(
                            "kg_query",
                            arguments={"entity": f"tag:{KG_RUNTIME_TAG}", "limit": 100},
                        ),
                        timeout,
                        "MCP_REUSABLE_KG_TAG_QUERY",
                    )
                    if getattr(kg_query, "isError", False):
                        raise RuntimeError(
                            "MCP_REUSABLE_KG_TAG_TOOL_ERROR=" + text_from_result(kg_query)
                        )
                    kg_payload = json_from_result(kg_query, "MCP_REUSABLE_KG_TAG_QUERY")
                    if str(kg_payload.get("status") or "").lower() not in {"success", "ok"}:
                        raise RuntimeError(f"MCP_REUSABLE_KG_TAG_STATUS_INVALID={kg_payload}")
                    results = kg_payload.get("results")
                    if not isinstance(results, list) or not results:
                        raise RuntimeError("MCP_REUSABLE_KG_TAG_RESULTS_EMPTY")
                    print(
                        f"MCP_REUSABLE_KG_TAG_QUERY=PASS TAG={KG_RUNTIME_TAG} RESULTS={len(results)}"
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
        f"KNOWLEDGE_KINDS={len(kind_first)} BM25_NATURAL={natural} VECTOR={vector} "
        f"HYBRID={hybrid} CASE_SEARCH={case_checks} RELATIONSHIP_SEARCH={relationship_checks} "
        "KG=PASS"
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
