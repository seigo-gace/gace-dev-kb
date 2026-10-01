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

Before declaring work complete, explicitly determine whether the change requires updates to:

- README
- Project Tree
- Design Delta
- a system/feature document

If an update is required but missing, the work is not complete.

### Design rule

Design is a baseline. Do **not** silently rewrite design merely because implementation differs. When an intentional implementation change differs from the baseline, record the difference, reason, evidence, and applying commit in Design Delta. Reflect completed and validated capability in README.

## Purpose

Capture and reuse repository-derived development knowledge, including:

- reusable implementation assets
- design and decision rationale
- successful outcomes
- failures and failure reasons
- root causes
- fixes
- tests and validation results
- commit/evidence references

The repository and Git history remain the primary development evidence. The KB is the reuse/search layer, not a replacement source of truth.

## Minimal implementation strategy

Build the shortest useful system:

1. use one suitable OSS core first;
2. reuse OSS functionality instead of rebuilding generic KB/search/MCP capability;
3. migrate only valuable G-ACE-specific parts from the former KB System;
4. add only the missing repository/knowledge adapter logic;
5. add another component only after a measured gap is confirmed.

`mcp-vector-search` 4.1.14 is the active OSS core. The repository-managed Windows bootstrap, compatibility verification, real full reindex, knowledge-graph build, semantic retrieval regression, deterministic G-ACE knowledge adapter tests, and real JSONL export have passed on the Master Windows environment. Automatic generated-record indexing into a dedicated `mcp-vector-search` knowledge corpus is now implemented in source and awaits Master Windows validation. MCP client E2E remains incomplete.

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

- `scripts/bootstrap-mvs-windows.ps1` installs the pinned OSS runtime and applies the measured Windows/docs compatibility fixes, including the Kuzu Windows-path compatibility handling.
- `tests/verify-mvs-windows.ps1` verifies the installed compatibility state and CLI startup.
- `tests/regression-mvs-windows.ps1` performs the tracked KB corpus full reindex, knowledge-graph build, status check, and the two required semantic retrieval regressions. It temporarily isolates the regression from a local `.gitignore` by changing `respect_gitignore`, then restores the prior value.

## G-ACE knowledge adapter and generated search corpus

- `scripts/gace_knowledge_adapter.py` reads committed Git evidence and projects it into the initial G-ACE knowledge contract without replacing Git as authority.
- `tests/test_gace_knowledge_adapter.py` validates record classification, marker extraction, clean tracked-tree gating, and JSONL contract output. Master Windows result: 5 tests, all PASS.
- `scripts/export-knowledge-windows.ps1` writes generated records outside Git source under `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl`. Master Windows real export: 36 records, PASS.
- `scripts/render_knowledge_corpus.py` turns JSONL records into deterministic Markdown documents suitable for semantic indexing without synthesizing missing evidence.
- `tests/test_render_knowledge_corpus.py` validates renderer behavior; Master Windows execution is pending.
- `scripts/index-knowledge-windows.ps1` exports, renders, initializes/reuses `F:\G-ACE-KB\data\knowledge-search`, indexes the generated corpus with `mcp-vector-search`, checks indexed-file count, and verifies retrieval of two known historical records. Source is implemented; Master Windows runtime validation is pending.

## Current status

**OSS SEARCH CORE + WINDOWS REGRESSION + G-ACE ADAPTER/EXPORT VALIDATED / GENERATED KNOWLEDGE INDEX SOURCE IMPLEMENTED, RUNTIME VALIDATION PENDING**

Validated on the Master Windows environment:

- `mcp-vector-search` 4.1.14 isolated runtime;
- repository-managed Windows bootstrap: PASS;
- Windows compatibility verifier: PASS;
- tracked KB corpus full reindex: 4 files / 161 chunks / 161 embeddings;
- embedding model: `sentence-transformers/all-MiniLM-L6-v2`;
- knowledge graph build: 58 entities / 57 relationships;
- status: 4/4 indexed, version 4.1.14;
- semantic design query returned `CURRENT_DESIGN.md` first;
- semantic failure/root-cause/fix/validation query returned expected repository knowledge;
- real Windows regression marker: `MVS_REAL_REGRESSION=PASS`;
- `respect_gitignore` restored to its original `true` value after regression;
- adapter unit tests: 5/5 PASS;
- real adapter export: `GACE_KNOWLEDGE_EXPORT=PASS`, 36 records;
- Windows export wrapper: `GACE_KNOWLEDGE_WINDOWS_EXPORT=PASS`, 36 records.

Observed non-blocking evidence retained for follow-up instead of being silently hidden:

- BM25 index build warning caused hybrid search to fall back to vector-only mode during the repository regression;
- semantic searches emitted entity-matching warnings while still returning the required results;
- local `.gitignore` remains untracked and is not modified by repository automation;
- the first adapter test run created local `scripts/__pycache__/`; future test execution disables bytecode generation, but the existing local cache has not been deleted by repository automation.

Implemented on the active feature branch, not yet Windows-runtime validated:

- deterministic JSONL → Markdown knowledge-corpus renderer;
- generated-record → dedicated `mcp-vector-search` knowledge-index pipeline;
- renderer tests and two-record semantic retrieval gate.

Not yet completed:

- Windows real-runtime generated knowledge corpus/index/retrieval PASS;
- MCP server → AI client E2E validation;
- cross-repository knowledge reuse E2E.

Do not report those incomplete items as implemented or validated.
