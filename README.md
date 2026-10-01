# G-ACE Development Knowledge Base

G-ACE Dev KB is the repository-centered knowledge base for reusing development knowledge across G-ACE projects.

> **Development starts here.** Before changing source, read the linked Current Design and Project Tree. Check Design Delta when the work touches an existing design decision. Do not treat future design as current implementation.

## Development entry points

- [Current Design](docs/CURRENT_DESIGN.md) — current design baseline, responsibilities, boundaries, and repository workflow.
- [Project Tree](docs/PROJECT_TREE.md) — current repository navigation and file/directory responsibilities.
- [Design Delta](docs/DESIGN_DELTA.md) — intentional differences from the baseline, why they changed, evidence, and applying commits.

## Mandatory repository routine

```text
README
→ Current Design / Project Tree / relevant Design Delta
→ implementation
→ test / debug / validation
→ commit = work/change record
→ documentation gate
→ completion gate
→ KB ingestion
```

Before declaring work complete, explicitly determine whether the change requires updates to README, Project Tree, Design Delta, or a system/feature document. If an update is required but missing, the work is not complete.

### Design rule

Design is a baseline. Do **not** silently rewrite design merely because implementation differs. When an intentional implementation change differs from the baseline, record the difference, reason, evidence, and applying commit in Design Delta. Reflect completed and validated capability in README.

## Purpose

Capture and reuse repository-derived development knowledge, including reusable implementation assets, design and decision rationale, successful outcomes, failures and failure reasons, root causes, fixes, tests and validation results, and commit/evidence references.

The repository and Git history remain the primary development evidence for repository-derived records. Verified reusable assets may also enter the formal KB from an explicitly registered external source when its exact repository/commit, manifest, evidence boundary, record count, and source reference are all validated. The KB is the reuse/search layer, not a replacement source of truth.

## Minimal implementation strategy

Build the shortest useful system:

1. use one suitable OSS core first;
2. reuse OSS functionality instead of rebuilding generic KB/search/MCP capability;
3. migrate only valuable G-ACE-specific parts from the former KB System;
4. add only the missing repository/knowledge adapter logic;
5. add another component only after a measured gap is confirmed.

`mcp-vector-search` 4.1.14 is the active OSS core. The repository-managed Windows bootstrap, compatibility verification, deterministic full-history G-ACE knowledge adapter/export, generated Markdown corpus, dedicated generated-knowledge index, persisted BM25 retention probe, real MCP stdio server → MCP client handshake/tool calls, known-record MCP retrieval gates, cross-repository reuse E2E, and verified external-skill admission into the formal KB have passed on the Master Windows environment.

## Initial knowledge contract

Keep the first record shape small:

- `type`
- `repository`
- `commit`
- `summary`
- `cause`
- `fix`
- `validation`
- `source`

This must support at least reusable implementation, design/decision, failure/root-cause/fix, and validation knowledge without creating a separate subsystem for every type.

## Local layout

Primary local root:

```text
F:\G-ACE-KB
├─ repo\       # this repository
├─ data\       # generated knowledge records/corpus/index data
├─ runtime\    # OSS runtime
├─ assets\     # pinned migration/input assets
└─ .venv\      # local environment from preparation
```

Only source, configuration, design, tests, and durable documentation belong in Git by default. Runtime downloads, generated indexes/data, caches, secrets, generated knowledge-record exports, and local environments stay outside the repository unless a later design decision explicitly changes that boundary.

## Windows bootstrap and regression

- `scripts/bootstrap-mvs-windows.ps1` installs pinned `mcp-vector-search==4.1.14` and applies measured compatibility fixes for Windows/runtime defects, including Kuzu-path handling, Windows multiprocessing `spawn`, MCP SDK 2.x compatibility, embedding-dimension API compatibility, atomic BM25 backend reopen after rebuild, and doc-only KG search behavior.
- `tests/verify-mvs-windows.ps1` verifies the installed compatibility state, CLI startup, actual multiprocessing context, MCP server creation compatibility, and each repository-managed compatibility patch.
- `tests/regression-mvs-windows.ps1` performs the tracked KB corpus full reindex, knowledge-graph build, status check, and two semantic retrieval regressions. It temporarily isolates the regression from a local `.gitignore` by changing `respect_gitignore`, then restores the prior value.

## G-ACE knowledge adapter and generated search corpus

- `scripts/gace_knowledge_adapter.py` reads committed Git evidence and projects it into the initial G-ACE knowledge contract without replacing Git as authority. The durable default is all commits reachable from the requested revision; bounded `--max-count` is explicit test/temporary behavior only.
- `tests/test_gace_knowledge_adapter.py` validates record classification, marker extraction, clean tracked-tree gating, JSONL contract output, and full-history retention semantics.
- `scripts/export-knowledge-windows.ps1` writes generated records outside Git source under `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl` and supports an explicit revision pin through `GACE_KNOWLEDGE_REVISION`.
- `scripts/render_knowledge_corpus.py` turns JSONL records into deterministic Markdown documents suitable for semantic indexing without synthesizing missing evidence.
- `tests/test_render_knowledge_corpus.py` validates renderer behavior. Master Windows result: 2 tests, all PASS.
- `tests/bm25_knowledge_retention_probe.py` loads the persisted BM25 index directly, searches a full commit ID, resolves the returned LanceDB chunk, and verifies that the indexed content contains the expected commit evidence.
- `scripts/index-knowledge-windows.ps1` self-verifies/repairs Windows MVS compatibility, exports the pinned repository history, imports accepted verified sources, combines them without collapsing distinct source identities, renders the formal corpus, indexes it with `mcp-vector-search`, verifies exact indexed-file count and BM25 persistence, proves direct BM25 retention of two known historical records, and runs real MCP retrieval gates for repository history and accepted skills.

Historical repository-only Windows quality result before external-skill admission:

```text
GACE_KNOWLEDGE_WINDOWS_EXPORT=PASS RECORDS=89 MODE=FULL_HISTORY
GACE_KNOWLEDGE_HISTORY_RETENTION=PASS COMMIT=74e8171
GACE_KNOWLEDGE_HISTORY_RETENTION=PASS COMMIT=4912a442
Reindex complete: 89 files, 625 chunks, 625 embeddings
Knowledge graph: 534 entities / 533 relationships
MVS_BM25_INDEX=PASS
GACE_BM25_KNOWLEDGE_PROBE=PASS LABEL=WINDOWS_KUZU_FIX COMMIT=74e81717 RESULTS=1
GACE_BM25_KNOWLEDGE_PROBE=PASS LABEL=GACE_ADAPTER COMMIT=4912a442 RESULTS=1
MVS_BM25_WARNING_REGRESSION=PASS
MVS_EMBEDDING_FUTUREWARNING_REGRESSION=PASS
MVS_DOC_ONLY_KG_WARNING_REGRESSION=PASS
GACE_KNOWLEDGE_INDEX=PASS RECORDS=89
```

## MCP client E2E

- `tests/mcp_knowledge_client_e2e.py` launches the installed `mcp-vector-search` MCP server over stdio, performs the MCP initialize/list-tools handshake, validates server metadata, calls `get_project_status`, and retrieves the known Kuzu compatibility and G-ACE adapter records through the real `search_code` MCP tool.
- `scripts/test-mcp-knowledge-e2e-windows.ps1` runs that client E2E against the generated knowledge-search project in one Windows command.

Latest repository-history MCP markers remain:

```text
MCP_INITIALIZE=PASS SERVER=mcp-vector-search VERSION=0.4.0
MCP_SERVER_INFO=PASS
MCP_LIST_TOOLS=PASS COUNT=28
MCP_PROJECT_STATUS=PASS
MCP_SEARCH_KUZU=PASS COMMIT=74e8171 MODE=bm25
MCP_SEARCH_ADAPTER=PASS COMMIT=4912a442 MODE=bm25
MCP_DOC_ONLY_KG_WARNING_REGRESSION=PASS
GACE_MCP_CLIENT_E2E=PASS
```

## Cross-repository reuse gate

- `scripts/combine_knowledge_records.py` deterministically combines multiple knowledge-record JSONL inputs while preserving the initial record contract and deduplicating only identical `repository + commit + type + source` identities. Distinct reusable skills at the same repository/commit/type therefore remain distinct records.
- `tests/test_combine_knowledge_records.py` validates multi-repository combining, source-identity preservation, and fail-closed behavior.
- `tests/mcp_cross_repo_reuse_e2e.py` proves real MCP retrieval from at least two distinct repositories.
- `scripts/test-cross-repo-reuse-windows.ps1` creates a temporary second-repository clone, exports both repositories, combines and indexes the records in a temporary search project, performs real MCP retrieval from both repositories, then removes the temporary E2E workspace.

The validated historical cross-repository run used public `seigo-gace/Astera` as the second repository. It combined 70 current-repository records plus 20 Astera records into 90 records, indexed all 90 files into 633 chunks/embeddings, built a 540-entity / 539-relationship graph, retrieved known records from both repositories through real MCP stdio, and removed the temporary workspace.

## Verified external skill admission

The formal KB can now admit an explicitly registered verified ModuleCatalog asset without weakening the initial eight-field contract.

Current accepted source registry:

```text
config/accepted-knowledge-sources.json
  id=debugai-code-repair-verification-skill-pack
  repository=seigo-gace/modular-catalog
  commit=bd258ec91b6970853d14a7bf4e65731312a487e3
  expectedSkillCount=13
  admission=verified
```

Admission is fail-closed:

- exact source repository and commit are pinned;
- Windows checkout disables `core.autocrlf` so manifest byte size/hash checks use canonical Git bytes;
- asset manifest is verified before formal indexing;
- both normal and user evidence must explicitly report `passed=true`;
- expected exported skill count must match;
- each exported function becomes a separate knowledge record with an exact `source` ending in its symbol name;
- the validation boundary is preserved rather than promoted beyond the evidence. The accepted source explicitly does **not** claim real-LLM DebugAI Skill ON/OFF A/B validation;
- repository-derived formal knowledge is pinned to `origin/main`, preventing feature-branch implementation commits from being ingested as already-formal knowledge during promotion.

Master Windows formal promotion result on 2026-10-01:

```text
FORMAL_REPOSITORY_REVISION=PASS REF=origin/main COMMIT=9520098d9666bdf33372bcd34f15758bb9c66f01
ACCEPTED_SOURCE_CANONICAL_CHECKOUT=PASS AUTOCRLF=false
ACCEPTED_SOURCE_MANIFEST_PREFLIGHT=PASS RECORDS=13
FORMAL_KB_UNIT_GATES=PASS
GACE_KNOWLEDGE_WINDOWS_EXPORT=PASS RECORDS=94 MODE=FULL_HISTORY
GACE_ACCEPTED_SOURCE=PASS RECORDS=13 COMMIT=bd258ec91b6970853d14a7bf4e65731312a487e3
GACE_KNOWLEDGE_COMBINE=PASS RECORDS=107 REPOSITORIES=2
GACE_FORMAL_CORPUS=PASS RECORDS=107 CORPUS=107
Reindex complete: 107 files, 1167 chunks, 1167 embeddings
Knowledge graph: 957 entities / 979 relationships
Indexed Files: 107/107
MVS_BM25_INDEX=PASS
GACE_BM25_KNOWLEDGE_PROBE=PASS LABEL=WINDOWS_KUZU_FIX
GACE_BM25_KNOWLEDGE_PROBE=PASS LABEL=GACE_ADAPTER
MCP_SEARCH_KUZU=PASS COMMIT=74e8171 MODE=bm25
MCP_SEARCH_ADAPTER=PASS COMMIT=4912a442 MODE=bm25
MCP_SKILL_SEARCH=PASS for all 13 accepted skills
MCP_NATURAL_SEARCH=PASS CHECK=CROSS_FILE_DEPENDENCY
MCP_NATURAL_SEARCH=PASS CHECK=FALSE_PASS
MCP_NATURAL_SEARCH=PASS CHECK=TARGETED_REGRESSION
GACE_DEBUGAI_SKILL_MCP_E2E=PASS RECORDS=13 NATURAL_CHECKS=3
GACE_KNOWLEDGE_INDEX=PASS RECORDS=107
GACE_FORMAL_KB_PROMOTION=PASS RECORDS=107
```

Generated formal files remain outside Git source:

```text
F:\G-ACE-KB\data\knowledge-records\formal-kb.jsonl
F:\G-ACE-KB\data\knowledge-sources\accepted\debugai-code-repair-verification-skill-pack\
F:\G-ACE-KB\data\knowledge-search\
```

## Current status

**FULL-HISTORY REPOSITORY KNOWLEDGE + VERIFIED EXTERNAL SKILLS → FORMAL INDEX/BM25/VECTOR/KG → MCP REUSE VALIDATED ON MASTER WINDOWS**

Validated current formal-KB state:

- formal repository authority pinned to `origin/main` commit `9520098d9666bdf33372bcd34f15758bb9c66f01`;
- repository knowledge export: 94 records;
- accepted verified ModuleCatalog skills: 13 records;
- formal combined knowledge: 107 records across `seigo-gace/gace-dev-kb` and `seigo-gace/modular-catalog`;
- formal corpus: 107 Markdown records;
- formal index: 107/107 files, 1,167 chunks, 1,167 embeddings;
- formal knowledge graph: 957 entities / 979 relationships;
- persisted BM25 index: PASS;
- direct BM25 retention of historical Kuzu and adapter knowledge: PASS;
- Windows compatibility verifier: PASS;
- BM25 fallback warning regression gate: PASS;
- embedding `FutureWarning` regression gate: PASS;
- doc-only KG entity-warning regression gate: PASS;
- real MCP repository-history retrieval: PASS;
- all 13 accepted DebugAI skills retrieved through real MCP BM25 search: PASS;
- three natural-language skill-discovery checks: PASS;
- final formal marker: `GACE_FORMAL_KB_PROMOTION=PASS RECORDS=107`.

Local-only evidence intentionally left untouched:

- `.gitignore` remains untracked;
- the pre-existing local `scripts/__pycache__/` remains untracked.

The current formal-KB boundary is complete for repository-derived knowledge plus explicitly registered, already-verified external assets. Generic TGserver-linked extraction/normalization/admission is still outside this repository's implemented scope and must not be inferred from this verified ModuleCatalog-source path.
