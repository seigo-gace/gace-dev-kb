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

The repository and Git history remain the primary development evidence. The KB is the reuse/search layer, not a replacement source of truth.

## Minimal implementation strategy

Build the shortest useful system:

1. use one suitable OSS core first;
2. reuse OSS functionality instead of rebuilding generic KB/search/MCP capability;
3. migrate only valuable G-ACE-specific parts from the former KB System;
4. add only the missing repository/knowledge adapter logic;
5. add another component only after a measured gap is confirmed.

`mcp-vector-search` 4.1.14 is the active OSS core. The repository-managed Windows bootstrap, compatibility verification, repository regression, deterministic G-ACE knowledge adapter/export, generated Markdown corpus, dedicated generated-knowledge index, real MCP stdio server → MCP client handshake/tool calls, and known-record MCP retrieval gates have passed on the Master Windows environment. The remaining runtime gate is cross-repository knowledge reuse E2E.

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
├─ assets\     # migration/input assets
└─ .venv\      # local environment from preparation
```

Only source, configuration, design, tests, and durable documentation belong in Git by default. Runtime downloads, generated indexes/data, caches, secrets, generated knowledge-record exports, and local environments stay outside the repository unless a later design decision explicitly changes that boundary.

## Windows bootstrap and regression

- `scripts/bootstrap-mvs-windows.ps1` installs pinned `mcp-vector-search==4.1.14` and applies the measured Windows/docs compatibility fixes, including Windows Kuzu-path handling, Windows multiprocessing `spawn`, and the measured MCP SDK 2.x server compatibility adaptation required by the installed dependency set.
- `tests/verify-mvs-windows.ps1` verifies the installed compatibility state, CLI startup, actual multiprocessing context, and MCP server creation compatibility.
- `tests/regression-mvs-windows.ps1` performs the tracked KB corpus full reindex, knowledge-graph build, status check, and two semantic retrieval regressions. It temporarily isolates the regression from a local `.gitignore` by changing `respect_gitignore`, then restores the prior value.

## G-ACE knowledge adapter and generated search corpus

- `scripts/gace_knowledge_adapter.py` reads committed Git evidence and projects it into the initial G-ACE knowledge contract without replacing Git as authority.
- `tests/test_gace_knowledge_adapter.py` validates record classification, marker extraction, clean tracked-tree gating, and JSONL contract output. Master Windows result: 5 tests, all PASS.
- `scripts/export-knowledge-windows.ps1` writes generated records outside Git source under `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl`.
- `scripts/render_knowledge_corpus.py` turns JSONL records into deterministic Markdown documents suitable for semantic indexing without synthesizing missing evidence.
- `tests/test_render_knowledge_corpus.py` validates renderer behavior. Master Windows result: 2 tests, all PASS.
- `scripts/index-knowledge-windows.ps1` self-verifies/repairs Windows MVS compatibility, exports records, renders the generated corpus, initializes/reuses `F:\G-ACE-KB\data\knowledge-search`, indexes it with `mcp-vector-search`, verifies exact indexed-file count, and proves retrieval of two known historical records.

## MCP client E2E

- `tests/mcp_knowledge_client_e2e.py` launches the installed `mcp-vector-search` MCP server over stdio, performs the MCP initialize/list-tools handshake, calls `get_project_status`, and retrieves the known Kuzu compatibility and G-ACE adapter records through the real `search_code` MCP tool.
- `scripts/test-mcp-knowledge-e2e-windows.ps1` runs that client E2E against the generated knowledge-search project in one Windows command.

Master Windows result:

```text
MVS_WINDOWS_MP_CONTEXT=spawn
MVS_MCP_SDK2_COMPAT=PASS
MVS_WINDOWS_COMPAT_VERIFY=PASS
MCP_INITIALIZE=PASS
MCP_LIST_TOOLS=PASS COUNT=28
MCP_PROJECT_STATUS=PASS
MCP_SEARCH_KUZU=PASS COMMIT=74e8171
MCP_SEARCH_ADAPTER=PASS COMMIT=4912a442
GACE_MCP_CLIENT_E2E=PASS
GACE_MCP_WINDOWS_E2E=PASS
```

## Cross-repository reuse gate

The active feature branch now contains the source for the final first-version reuse gate:

- `scripts/combine_knowledge_records.py` deterministically combines multiple repository JSONL exports while preserving the initial record contract and deduplicating identical repository/commit/type records;
- `tests/test_combine_knowledge_records.py` validates multi-repository combining and fail-closed behavior;
- `tests/mcp_cross_repo_reuse_e2e.py` proves real MCP retrieval from at least two distinct repositories;
- `scripts/test-cross-repo-reuse-windows.ps1` creates a temporary second-repository clone, exports both repositories, combines and indexes the records in a temporary search project, performs real MCP retrieval from both repositories, then removes the temporary E2E workspace.

The default second repository for the gate is public `seigo-gace/Astera`, using commit `5ef89073...` as the known external-repository record. This cross-repository source is implemented but is not PASS until run on the Master Windows environment.

## Current status

**OSS SEARCH CORE + WINDOWS REGRESSION + G-ACE ADAPTER/EXPORT + GENERATED KNOWLEDGE INDEX/RETRIEVAL + REAL MCP CLIENT E2E VALIDATED / CROSS-REPOSITORY REUSE E2E SOURCE IMPLEMENTED, RUNTIME VALIDATION PENDING**

Validated on the Master Windows environment:

- `mcp-vector-search` 4.1.14 isolated runtime;
- repository-managed Windows bootstrap and compatibility verifier: PASS;
- Windows multiprocessing context: `spawn`;
- MCP SDK 2.x server compatibility probe: PASS;
- repository tracked-corpus reindex: 4 files / 161 chunks / 161 embeddings;
- repository knowledge graph: 58 entities / 57 relationships;
- repository semantic design and failure/root-cause/fix/validation retrieval: PASS;
- real repository regression marker: `MVS_REAL_REGRESSION=PASS`;
- adapter unit tests: 5/5 PASS;
- renderer unit tests: 2/2 PASS;
- latest validated generated knowledge export: 47 records;
- generated corpus: 47 Markdown knowledge documents;
- generated knowledge index: 47/47 files, 331 chunks, 331 embeddings;
- generated knowledge graph: 282 entities / 281 relationships;
- known Kuzu fix retrieval returned commit `74e8171...`;
- known G-ACE adapter retrieval returned commit `4912a442...`;
- final generated-knowledge marker: `GACE_KNOWLEDGE_INDEX=PASS RECORDS=47`;
- real MCP stdio initialize/list-tools/status/search E2E: PASS;
- real MCP tool count observed: 28;
- real MCP Kuzu and adapter retrieval gates: PASS;
- final MCP markers: `GACE_MCP_CLIENT_E2E=PASS` and `GACE_MCP_WINDOWS_E2E=PASS`.

Observed non-blocking evidence retained for follow-up instead of being silently hidden:

- BM25 index build warning caused hybrid search to fall back to vector-only mode;
- semantic searches emitted entity-matching warnings while still returning the required records;
- the embedding library emits a deprecation `FutureWarning` for `get_sentence_embedding_dimension`;
- MCP initialization currently reports server name/version as `unknown` in the client-side display even though protocol initialization succeeds;
- local `.gitignore` remains untracked and is not modified by repository automation;
- the pre-existing local `scripts/__pycache__/` remains untouched; current tests disable new bytecode generation.

Implemented on the active feature branch, not yet Windows-runtime validated:

- deterministic multi-repository knowledge-record combining;
- real MCP cross-repository retrieval E2E using `gace-dev-kb` plus public `seigo-gace/Astera` in a temporary workspace.

Not yet completed:

- Master Windows `GACE_CROSS_REPO_REUSE_E2E=PASS`.

Do not report incomplete items as validated.
