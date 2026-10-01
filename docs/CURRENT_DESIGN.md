# G-ACE Dev KB — Current Design Baseline

## 1. Purpose

G-ACE Dev KB reuses knowledge produced by repository development so later development does not need to recreate the same implementation, repeat the same investigation, or repeat known failures.

The repository remains the development source of truth. The KB is a downstream reuse/search layer.

## 2. Repository-centered development loop

```text
README
  ↓
Current Design / Project Tree / Design Delta
  ↓
Implementation
  ↓
Test / Debug / Validation
  ↓
Commit = work/change record
  ↓
Documentation Gate
  ↓
Completion Gate
  ↓
Knowledge ingestion
  ↓
Search / MCP reuse in later repository development
```

README is the mandatory entry point for development. It must link directly to the current design, project tree, design delta, and relevant system documents so an AI or developer does not have to rediscover them.

## 3. Design authority rules

- Design is a baseline, not a disposable description of whatever the current code happens to be.
- Do not silently overwrite design to match implementation drift.
- When implementation intentionally differs from the design, record what changed, why it changed, and the applying commit in `DESIGN_DELTA.md`.
- Completed and validated current capability is reflected in README.
- File additions, removals, moves, and major responsibility changes require a Project Tree update.
- Work is not complete while a required README / Tree / Delta / system-document update remains undone.

## 4. Knowledge scope

The first useful version must preserve and retrieve reusable implementation, design and decision rationale, successful outcomes, failures and failure reasons, root causes, fixes, tests and validation results, and commit/evidence references.

The initial record shape stays intentionally small:

- `type`
- `repository`
- `commit`
- `summary`
- `cause`
- `fix`
- `validation`
- `source`

Do not create separate subsystems for each knowledge type unless a measured need requires it.

## 5. Implementation strategy

Shortest-path rule:

1. Use one suitable OSS core first.
2. Reuse OSS capabilities instead of rebuilding generic storage, indexing, search, or MCP functionality.
3. Migrate only valuable G-ACE-specific parts from the former KB System.
4. Add only the missing G-ACE repository/knowledge adapter logic.
5. Add another dependency only after a real measured gap is confirmed.

`mcp-vector-search` 4.1.14 is the active OSS search/index/MCP core. Repository-managed Windows compatibility, repository regression, deterministic repository-to-record adaptation, generated knowledge-corpus indexing, direct semantic retrieval, real MCP stdio client retrieval, and cross-repository reuse have passed on the Master Windows environment.

## 6. G-ACE repository / knowledge adapter boundary

```text
Git repository / committed evidence
  ↓
G-ACE Knowledge Adapter
  ↓
initial knowledge record
  ↓
JSONL projection outside Git source
  ↓
optional deterministic multi-repository combine
  ↓
Markdown knowledge corpus
  ↓
dedicated mcp-vector-search knowledge index
  ↓
MCP stdio server
  ↓
AI/MCP client retrieval
```

Adapter and retrieval rules:

- Git remains authority; the adapter only projects committed evidence.
- Generic MCP/search capability stays in `mcp-vector-search`; do not build a second MCP server for the adapter.
- Record generation must be deterministic and must not invent missing cause, fix, validation, or source evidence.
- Explicit commit-body markers (`Cause:`, `Fix:`, `Validation:`, `Source:`) may populate the corresponding fields.
- When a field is not supported by committed evidence, it remains empty rather than being synthesized.
- Modified or staged tracked files block normal export so uncommitted work is not represented as durable knowledge.
- Untracked local-only files do not block export.
- Generated JSONL, rendered corpus, MVS config, and MVS index stay outside repository source.
- Multi-repository combining preserves the same initial contract and deduplicates identical repository/commit/type records; it does not merge or reconcile conflicting evidence.
- Searchability is implemented by rendering one Markdown document per knowledge record rather than mutating the initial record contract to fit the OSS parser.
- Windows compatibility is verified before generated-knowledge indexing and MCP execution; the pinned runtime may be repaired by the repository-managed compatibility layer and then reverified.
- MCP validation requires real initialize/list-tools/tool-call exchange over stdio and return of known commit-backed records.
- Cross-repository validation requires at least two distinct repository identities in the combined corpus and successful MCP retrieval of a known record from each.

## 7. Runtime / storage boundary

Local durable layout:

```text
F:\G-ACE-KB
├─ repo\
├─ data\
│  ├─ knowledge-records\
│  └─ knowledge-search\
├─ runtime\
│  └─ mcp-vector-search\
├─ assets\
└─ .venv\
```

Git stores source, configuration, design, tests, and durable documentation. Large indexes, caches, runtime downloads, generated data, generated knowledge-record exports, secrets, and local environments stay outside Git unless a later explicit design decision changes that boundary.

Cross-repository E2E uses a temporary OS workspace for the second repository, combined records, temporary corpus, and temporary search index. The test removes that workspace after a successful run; it does not create a new persistent repository or production resource.

Knowledge-data extraction/normalization/admission from TGserver is not implemented in this repository. That processing system is a separate development scope and will integrate with TGserver and this KB later through explicit contracts.

## 8. Windows compatibility boundary

The pinned upstream runtime currently requires repository-managed Windows/runtime compatibility handling for measured defects:

- Unix-only `resource` import guard;
- result display fallback when original similarity is `None`;
- Kuzu cleanup path normalization;
- multiprocessing context: Windows must use `spawn`;
- MCP SDK compatibility: `mcp-vector-search` 4.1.14 uses MCP SDK 1.x decorator APIs while its dependency constraint permits installed MCP SDK 2.x; the repository bootstrap adapts the installed server to the 2.x constructor-handler API and current initialization-options path.

Compatibility source alone is not enough. `tests/verify-mvs-windows.ps1` verifies the installed runtime, actual multiprocessing context, and real MCP server creation compatibility.

## 9. Future boundary

TGserver-linked knowledge processing/admission and any Astera-oriented KB architecture are separate future integration material. They must not be represented as current implementation until implemented and validated in their own scope and integrated through explicit contracts.

## 10. Current implementation boundary (2026-10-01)

Validated current capability:

- isolated OSS runtime under `F:\G-ACE-KB\runtime\mcp-vector-search`;
- repository-managed Windows bootstrap PASS;
- Windows compatibility verifier PASS;
- runtime multiprocessing context `spawn` PASS;
- MCP SDK 2.x server compatibility probe PASS;
- repository tracked-corpus reindex PASS: 4 files, 161 chunks, 161 embeddings;
- repository knowledge graph PASS: 58 entities, 57 relationships;
- repository semantic design and failure/root-cause/fix/validation retrieval PASS;
- real repository regression gate PASS;
- G-ACE knowledge adapter unit tests PASS: 5/5;
- renderer tests PASS: 2/2;
- generated knowledge export/index/retrieval PASS;
- MCP stdio initialize/list-tools/status/search PASS;
- deterministic multi-repository combiner tests PASS: 3/3;
- cross-repository export/combine PASS: 70 current records + 20 Astera records = 90 records;
- cross-repository rendered corpus PASS: 90 Markdown records;
- cross-repository index PASS: 90/90 files, 633 chunks, 633 embeddings;
- cross-repository knowledge graph PASS: 540 entities, 539 relationships;
- MCP retrieval of `gace-dev-kb` record `a017c934...` PASS;
- MCP retrieval of `seigo-gace/Astera` record `5ef89073...` PASS;
- `GACE_CROSS_REPO_MCP_REUSE=PASS CHECKS=2 REPOSITORIES=2`;
- `GACE_CROSS_REPO_REUSE_E2E=PASS RECORDS=90 REPOSITORIES=2`;
- `CROSS_REPO_TEMP_CLEANUP=PASS`.

Observed but not closed:

- BM25 index build emits a non-fatal Lance warning and hybrid mode falls back to vector-only;
- semantic searches can emit entity-matching warnings despite returning the required records;
- the embedding library emits a deprecation `FutureWarning` for `get_sentence_embedding_dimension`;
- client-side initialization display can report MCP server name/version as `unknown` while initialization itself succeeds;
- local `.gitignore` remains untracked and is intentionally not mutated by repository automation;
- the pre-existing local `scripts/__pycache__/` remains untouched; current Python test commands suppress new bytecode generation.

The first-version repository knowledge reuse E2E boundary is closed. Remaining work in this repository is quality hardening and regression protection for the retained warning classes and runtime compatibility behavior.
