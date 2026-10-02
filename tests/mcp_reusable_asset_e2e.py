#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
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
    rows = [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if not rows:
        raise RuntimeError("REUSABLE_ASSET_METADATA_EMPTY")
    return rows


def load_optional_jsonl(path: Path, label: str):
    if not path.is_file():
        return []
    rows = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise RuntimeError(f"{label}_OBJECT_REQUIRED={path}:{line_number}")
        rows.append(value)
    return rows


def safe_tag(value):
    text = str(value or "unknown").strip().lower()
    text = re.sub(r"[^0-9a-z._-]+", "-", text).strip("-")
    return text or "unknown"


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


def first_dependency_probe(rows):
    for row in rows:
        if str(row.get("knowledge_kind") or "") != "discovery":
            continue
        composition = row.get("composition") if isinstance(row.get("composition"), dict) else {}
        for dependency in composition.get("depends_on") or []:
            value = str(dependency or "").strip()
            if value:
                return row, value
    return None


def runtime_maps(rows):
    by_unit = {}
    discovery_by_asset = {}
    source_owners = {}
    for row in rows:
        knowledge_id = str(row.get("knowledge_id") or "")
        asset_id = str(row.get("parent_asset_id") or "")
        if knowledge_id:
            by_unit[knowledge_id] = row
        if asset_id and str(row.get("knowledge_kind") or "") == "discovery":
            discovery_by_asset[asset_id] = row
        for source_path in row.get("source_paths") or []:
            source_owners.setdefault((asset_id, str(source_path)), []).append(row)
    return by_unit, discovery_by_asset, source_owners


def relationship_probe(rows, relationships):
    by_unit, discovery_by_asset, _ = runtime_maps(rows)
    for relationship in relationships:
        relationship_id = str(relationship.get("relationship_id") or "").strip()
        if not relationship_id:
            continue
        source = str(relationship.get("from") or "")
        target = str(relationship.get("to") or "")
        expected = by_unit.get(source) or discovery_by_asset.get(source)
        if expected is None:
            expected = by_unit.get(target) or discovery_by_asset.get(target)
        if expected is not None:
            return expected, relationship, relationship_id
    return None


def case_probe(rows, cases):
    _by_unit, discovery_by_asset, source_owners = runtime_maps(rows)
    for case in cases:
        case_id = str(case.get("case_id") or "").strip()
        asset_id = str(case.get("parent_asset_id") or "").strip()
        if not case_id or not asset_id:
            continue
        source_test = str(case.get("source_test") or "")
        owners = source_owners.get((asset_id, source_test), []) if source_test else []
        expected = owners[0] if owners else discovery_by_asset.get(asset_id)
        if expected is not None:
            return expected, case, case_id
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
        raise RuntimeError(f"{label}_EXPECTED_MISSING mode={mode} id={knowledge_id}")
    return text


async def kg_tag_require(session, *, tag: str, timeout: int, label: str):
    result = await wait(
        session.call_tool(
            "kg_query",
            arguments={"entity": f"tag:{tag}", "limit": 100},
        ),
        timeout,
        label,
    )
    if getattr(result, "isError", False):
        raise RuntimeError(f"{label}_TOOL_ERROR={text_from_result(result)}")
    payload = json_from_result(result, label)
    if str(payload.get("status") or "").lower() not in {"success", "ok"}:
        raise RuntimeError(f"{label}_STATUS_INVALID={payload}")
    results = payload.get("results")
    if not isinstance(results, list) or not results:
        raise RuntimeError(f"{label}_RESULTS_EMPTY tag={tag}")
    print(f"{label}=PASS TAG={tag} RESULTS={len(results)}")
    return results


async def run(python: Path, root: Path, metadata: Path, expected: int, timeout: int):
    rows = load(metadata)
    if len(rows) != expected:
        raise RuntimeError(
            f"REUSABLE_ASSET_COUNT_MISMATCH expected={expected} actual={len(rows)}"
        )

    ids = [str(row.get("knowledge_id") or "") for row in rows]
    if any(not value for value in ids):
        raise RuntimeError("REUSABLE_ASSET_KNOWLEDGE_ID_MISSING")
    if len(set(ids)) != len(ids):
        raise RuntimeError("REUSABLE_ASSET_KNOWLEDGE_ID_DUPLICATE")

    relationships_path = metadata.parent / "relationships.jsonl"
    cases_path = metadata.parent / "cases.jsonl"
    relationships = load_optional_jsonl(relationships_path, "REUSABLE_RELATIONSHIP")
    cases = load_optional_jsonl(cases_path, "REUSABLE_CASE")
    if not relationships:
        raise RuntimeError(f"REUSABLE_RELATIONSHIP_SIDECAR_EMPTY={relationships_path}")
    if not cases:
        raise RuntimeError(f"REUSABLE_CASE_SIDECAR_EMPTY={cases_path}")

    sidecar_case_probe = case_probe(rows, cases)
    sidecar_relationship_probe = relationship_probe(rows, relationships)
    if sidecar_case_probe is None:
        raise RuntimeError("REUSABLE_CASE_SIDECAR_NO_SEARCHABLE_TARGET")
    if sidecar_relationship_probe is None:
        raise RuntimeError("REUSABLE_RELATIONSHIP_SIDECAR_NO_SEARCHABLE_TARGET")
    dependency_probe = first_dependency_probe(rows)

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

                    case_row, case, case_id = sidecar_case_probe
                    await search_and_require(
                        session,
                        query=case_id,
                        knowledge_id=str(case_row["knowledge_id"]),
                        mode="bm25",
                        timeout=timeout,
                        label=f"MCP_REUSABLE_SIDECAR_CASE_{case_id}",
                    )
                    print(
                        f"MCP_REUSABLE_SIDECAR_CASE_SEARCH=PASS CASE={case_id} "
                        f"ID={case_row['knowledge_id']} SIDECAR={len(cases)}"
                    )

                    relationship_row, relationship, relationship_id = sidecar_relationship_probe
                    await search_and_require(
                        session,
                        query=relationship_id,
                        knowledge_id=str(relationship_row["knowledge_id"]),
                        mode="bm25",
                        timeout=timeout,
                        label=f"MCP_REUSABLE_SIDECAR_RELATIONSHIP_{relationship_id}",
                    )
                    print(
                        "MCP_REUSABLE_SIDECAR_RELATIONSHIP_SEARCH=PASS "
                        f"RELATIONSHIP={relationship_id} ID={relationship_row['knowledge_id']} "
                        f"SIDECAR={len(relationships)}"
                    )

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
                    print(f"MCP_REUSABLE_KG_STATS=PASS ENTITIES={total_entities}")

                    await kg_tag_require(
                        session,
                        tag=KG_RUNTIME_TAG,
                        timeout=timeout,
                        label="MCP_REUSABLE_KG_TAG_QUERY",
                    )
                    await kg_tag_require(
                        session,
                        tag=f"relationship-id-{safe_tag(relationship_id)}",
                        timeout=timeout,
                        label="MCP_REUSABLE_KG_RELATIONSHIP_ID_TAG_QUERY",
                    )
                    await kg_tag_require(
                        session,
                        tag=f"case-id-{safe_tag(case_id)}",
                        timeout=timeout,
                        label="MCP_REUSABLE_KG_CASE_ID_TAG_QUERY",
                    )

                    relation = str(relationship.get("relation") or "").strip()
                    kg_relation_checks = 0
                    if relation:
                        await kg_tag_require(
                            session,
                            tag=f"relation-{safe_tag(relation)}",
                            timeout=timeout,
                            label="MCP_REUSABLE_KG_RELATION_TAG_QUERY",
                        )
                        kg_relation_checks = 1
                    else:
                        print("MCP_REUSABLE_KG_RELATION_TAG_QUERY=PASS SKIP=NO_RELATION_SEMANTIC")

                    kg_dependency_checks = 0
                    if dependency_probe:
                        _row, dependency = dependency_probe
                        await kg_tag_require(
                            session,
                            tag=f"depends-on-{safe_tag(dependency)}",
                            timeout=timeout,
                            label="MCP_REUSABLE_KG_DEPENDENCY_TAG_QUERY",
                        )
                        kg_dependency_checks = 1
                    else:
                        print("MCP_REUSABLE_KG_DEPENDENCY_TAG_QUERY=PASS SKIP=NO_CATALOG_DEPENDENCY")

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
        f"HYBRID={hybrid} SIDECAR_CASE_SEARCH=1 SIDECAR_RELATIONSHIP_SEARCH=1 "
        f"KG_RELATION={kg_relation_checks} KG_DEPENDENCY={kg_dependency_checks} "
        "KG_SIDECAR_IDS=PASS KG=PASS"
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
