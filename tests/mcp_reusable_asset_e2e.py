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
EXACT_SEARCH_LIMIT = 10
SIDECAR_SEARCH_LIMIT = 10
NATURAL_SEARCH_LIMIT = 50
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


def build_server_env(root: Path):
    env = dict(os.environ)
    env["MCP_ENABLE_FILE_WATCHING"] = "false"
    env["MCP_PROJECT_ROOT"] = str(root)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    if os.name == "nt":
        env.update(WINDOWS_SAFE_ENV)
    return env


def build_server(python: Path, root: Path):
    return StdioServerParameters(
        command=str(python),
        args=["-m", "mcp_vector_search.mcp", str(root)],
        env=build_server_env(root),
        cwd=str(root),
    )


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
    result_limit: int = NATURAL_SEARCH_LIMIT,
):
    result = await wait(
        session.call_tool(
            "search_code",
            arguments={
                "query": query,
                "limit": result_limit,
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
            f"{label}_EXPECTED_MISSING mode={mode} id={knowledge_id} limit={result_limit}"
        )
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


async def run_kg_gates(
    python: Path,
    root: Path,
    *,
    timeout: int,
    relationship_checks: int,
    relationship,
    relationship_id: str,
    case_checks: int,
    case_id: str,
    dependency_probe,
):
    kg_relation_checks = 0
    kg_dependency_checks = 0
    server = build_server(python, root)
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as errlog:
        try:
            async with stdio_client(server, errlog=errlog) as (read_stream, write_stream):
                async with ClientSession(read_stream, write_stream) as session:
                    init = await wait(session.initialize(), timeout, "MCP_KG_INITIALIZE")
                    info = getattr(init, "server_info", None) or getattr(init, "serverInfo", None)
                    if not info:
                        raise RuntimeError("MCP_KG_SERVER_INFO_MISSING")
                    tools = await wait(session.list_tools(), timeout, "MCP_KG_LIST_TOOLS")
                    names = {tool.name for tool in tools.tools}
                    missing = {"kg_stats", "kg_query"} - names
                    if missing:
                        raise RuntimeError(
                            "MCP_REUSABLE_KG_REQUIRED_TOOLS_MISSING="
                            + ",".join(sorted(missing))
                        )
                    print(f"MCP_REUSABLE_KG_SESSION_INITIALIZE=PASS TOOLS={len(names)}")

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
                    statistics = (
                        stats.get("statistics")
                        if isinstance(stats.get("statistics"), dict)
                        else {}
                    )
                    total_entities = int(statistics.get("total_entities", 0) or 0)
                    if total_entities <= 0:
                        raise RuntimeError(
                            f"MCP_REUSABLE_KG_EMPTY entities={total_entities}"
                        )
                    print(f"MCP_REUSABLE_KG_STATS=PASS ENTITIES={total_entities}")

                    await kg_tag_require(
                        session,
                        tag=KG_RUNTIME_TAG,
                        timeout=timeout,
                        label="MCP_REUSABLE_KG_TAG_QUERY",
                    )

                    if relationship_checks:
                        await kg_tag_require(
                            session,
                            tag=f"relationship-id-{safe_tag(relationship_id)}",
                            timeout=timeout,
                            label="MCP_REUSABLE_KG_RELATIONSHIP_ID_TAG_QUERY",
                        )
                    else:
                        print(
                            "MCP_REUSABLE_KG_RELATIONSHIP_ID_TAG_QUERY=PASS "
                            "SKIP=NO_RELATIONSHIP_SIDECAR"
                        )

                    if case_checks:
                        await kg_tag_require(
                            session,
                            tag=f"case-id-{safe_tag(case_id)}",
                            timeout=timeout,
                            label="MCP_REUSABLE_KG_CASE_ID_TAG_QUERY",
                        )
                    else:
                        print(
                            "MCP_REUSABLE_KG_CASE_ID_TAG_QUERY=PASS "
                            "SKIP=NO_CASE_SIDECAR"
                        )

                    relation = str((relationship or {}).get("relation") or "").strip()
                    if relation:
                        await kg_tag_require(
                            session,
                            tag=f"relation-{safe_tag(relation)}",
                            timeout=timeout,
                            label="MCP_REUSABLE_KG_RELATION_TAG_QUERY",
                        )
                        kg_relation_checks = 1
                    else:
                        print(
                            "MCP_REUSABLE_KG_RELATION_TAG_QUERY=PASS "
                            "SKIP=NO_RELATION_SEMANTIC"
                        )

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
                        print(
                            "MCP_REUSABLE_KG_DEPENDENCY_TAG_QUERY=PASS "
                            "SKIP=NO_CATALOG_DEPENDENCY"
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
    return kg_relation_checks, kg_dependency_checks


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
    sidecar_case_probe = case_probe(rows, cases) if cases else None
    sidecar_relationship_probe = relationship_probe(rows, relationships) if relationships else None
    if cases and sidecar_case_probe is None:
        raise RuntimeError("REUSABLE_CASE_SIDECAR_NO_SEARCHABLE_TARGET")
    if relationships and sidecar_relationship_probe is None:
        raise RuntimeError("REUSABLE_RELATIONSHIP_SIDECAR_NO_SEARCHABLE_TARGET")
    dependency_probe = first_dependency_probe(rows)

    if os.name == "nt":
        print(
            "MCP_REUSABLE_WINDOWS_SAFETY=PASS "
            "MULTIPROCESSING=DISABLED WORKERS=1 EMBEDDING_BATCH=8 "
            "FILE_BATCH=16 NATIVE_THREADS=1"
        )

    kind_first = {}
    asset_ids = set()
    natural = vector = hybrid = 0
    case_checks = relationship_checks = 0
    relationship = None
    relationship_id = ""
    case_id = ""

    # Search and KG use separate MCP processes. On Windows, search operations can
    # keep a Kuzu handle for the lifetime of the server process. Closing that
    # process before KG queries guarantees one fresh owner of the graph database.
    search_server = build_server(python, root)
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as errlog:
        try:
            async with stdio_client(search_server, errlog=errlog) as (
                read_stream,
                write_stream,
            ):
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
                            "MCP_REUSABLE_REQUIRED_TOOLS_MISSING="
                            + ",".join(sorted(missing))
                        )
                    print(f"MCP_REUSABLE_INITIALIZE=PASS TOOLS={len(names)}")

                    for index, row in enumerate(rows, 1):
                        knowledge_id = str(row["knowledge_id"])
                        parent_asset_id = str(row.get("parent_asset_id") or "")
                        if not parent_asset_id:
                            raise RuntimeError(
                                f"REUSABLE_ASSET_PARENT_ID_MISSING={knowledge_id}"
                            )
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
                            result_limit=EXACT_SEARCH_LIMIT,
                        )
                        if index % 50 == 0 or index == len(rows):
                            print(
                                f"MCP_REUSABLE_EXACT_BM25_PROGRESS={index}/{len(rows)} "
                                f"LIMIT={EXACT_SEARCH_LIMIT}"
                            )
                    print(
                        f"MCP_REUSABLE_EXACT_BM25=PASS RECORDS={len(rows)} "
                        f"ASSETS={len(asset_ids)} LIMIT={EXACT_SEARCH_LIMIT}"
                    )

                    if sidecar_case_probe is not None:
                        case_row, _case, case_id = sidecar_case_probe
                        await search_and_require(
                            session,
                            query=case_id,
                            knowledge_id=str(case_row["knowledge_id"]),
                            mode="bm25",
                            timeout=timeout,
                            label=f"MCP_REUSABLE_SIDECAR_CASE_{case_id}",
                            result_limit=SIDECAR_SEARCH_LIMIT,
                        )
                        case_checks = 1
                        print(
                            f"MCP_REUSABLE_SIDECAR_CASE_SEARCH=PASS CASE={case_id} "
                            f"ID={case_row['knowledge_id']} SIDECAR={len(cases)}"
                        )
                    else:
                        print(
                            "MCP_REUSABLE_SIDECAR_CASE_SEARCH=PASS "
                            "CASES=0 SKIP=NO_CASE_SIDECAR"
                        )

                    if sidecar_relationship_probe is not None:
                        relationship_row, relationship, relationship_id = (
                            sidecar_relationship_probe
                        )
                        await search_and_require(
                            session,
                            query=relationship_id,
                            knowledge_id=str(relationship_row["knowledge_id"]),
                            mode="bm25",
                            timeout=timeout,
                            label=(
                                "MCP_REUSABLE_SIDECAR_RELATIONSHIP_"
                                f"{relationship_id}"
                            ),
                            result_limit=SIDECAR_SEARCH_LIMIT,
                        )
                        relationship_checks = 1
                        print(
                            "MCP_REUSABLE_SIDECAR_RELATIONSHIP_SEARCH=PASS "
                            f"RELATIONSHIP={relationship_id} "
                            f"ID={relationship_row['knowledge_id']} "
                            f"SIDECAR={len(relationships)}"
                        )
                    else:
                        print(
                            "MCP_REUSABLE_SIDECAR_RELATIONSHIP_SEARCH=PASS "
                            "RELATIONSHIPS=0 SKIP=NO_RELATIONSHIP_SIDECAR"
                        )

                    for knowledge_kind, row in sorted(kind_first.items()):
                        query = natural_query(row)
                        knowledge_id = str(row["knowledge_id"])
                        if not query:
                            raise RuntimeError(
                                "MCP_REUSABLE_NATURAL_QUERY_EMPTY "
                                f"kind={knowledge_kind} id={knowledge_id}"
                            )
                        for mode in ("bm25", "vector", "hybrid"):
                            await search_and_require(
                                session,
                                query=query,
                                knowledge_id=knowledge_id,
                                mode=mode,
                                timeout=timeout,
                                label=f"MCP_REUSABLE_{mode.upper()}_{knowledge_kind}",
                                result_limit=NATURAL_SEARCH_LIMIT,
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

    print("MCP_REUSABLE_SEARCH_SESSION=PASS CLOSED=YES")

    kg_relation_checks, kg_dependency_checks = await run_kg_gates(
        python,
        root,
        timeout=timeout,
        relationship_checks=relationship_checks,
        relationship=relationship,
        relationship_id=relationship_id,
        case_checks=case_checks,
        case_id=case_id,
        dependency_probe=dependency_probe,
    )

    print(
        f"GACE_REUSABLE_ASSET_MCP_E2E=PASS RECORDS={len(rows)} ASSETS={len(asset_ids)} "
        f"KNOWLEDGE_KINDS={len(kind_first)} BM25_NATURAL={natural} VECTOR={vector} "
        f"HYBRID={hybrid} SIDECAR_CASE_SEARCH={case_checks} "
        f"SIDECAR_RELATIONSHIP_SEARCH={relationship_checks} "
        f"KG_RELATION={kg_relation_checks} KG_DEPENDENCY={kg_dependency_checks} "
        f"CASE_SIDECAR_COUNT={len(cases)} RELATIONSHIP_SIDECAR_COUNT={len(relationships)} "
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