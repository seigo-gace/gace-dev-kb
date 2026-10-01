# G-ACE Dev KB — Current Design Baseline

## 1. Purpose

G-ACE Dev KB reuses knowledge produced by repository development so later development does not need to recreate the same implementation, repeat the same investigation, or repeat known failures.

The repository remains the development source of truth for repository-derived records. The formal KB may also admit explicitly registered external reusable assets when their exact repository/commit, manifest, evidence boundary, record count, and source identity are validated. The KB is a downstream reuse/search layer, not a replacement authority.

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

`mcp-vector-search` 4.1.14 is the active OSS search/index/MCP core. Repository-managed Windows compatibility, deterministic full-history repository-to-record adaptation, generated knowledge-corpus indexing, persisted BM25 retention validation, real MCP stdio client retrieval, cross-repository reuse, and verified external-skill admission into the formal KB have passed on the Master Windows environment.

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
optional deterministic combine
  ↓
Markdown knowledge corpus
  ↓
dedicated mcp-vector-search knowledge index
  ↓
persisted BM25 + vector index
  ↓
MCP stdio server
  ↓
AI/MCP client retrieval
```

Adapter and retrieval rules:

- Git remains authority for repository-derived records; the adapter only projects committed evidence.
- Generic MCP/search capability stays in `mcp-vector-search`; do not build a second MCP server for the adapter.
- Record generation must be deterministic and must not invent missing cause, fix, validation, or source evidence.
- Explicit commit-body markers (`Cause:`, `Fix:`, `Validation:`, `Source:`) may populate the corresponding fields.
- When a field is not supported by committed evidence, it remains empty rather than being synthesized.
- Modified or staged tracked files block normal export so uncommitted work is not represented as durable knowledge.
- Untracked local-only files do not block export.
- Durable export defaults to all commits reachable from the requested revision. A positive `--max-count` is explicit bounded behavior for tests or temporary workflows; it must not silently evict older durable knowledge.
- Formal promotion pins repository-derived knowledge to an explicit revision; the current default is `origin/main`, preventing feature-branch work from becoming formal knowledge before merge.
- Generated JSONL, rendered corpus, MVS config, and MVS index stay outside repository source.
- Multi-source combining preserves the same initial contract and deduplicates only identical `repository + commit + type + source` identities. Distinct reusable assets at the same repository/commit/type remain distinct records.
- Searchability is implemented by rendering one Markdown document per knowledge record rather than mutating the initial record contract to fit the OSS parser.
- Windows compatibility is verified before generated-knowledge indexing and MCP execution; the pinned runtime may be repaired by the repository-managed compatibility layer and then reverified.
- Persisted BM25 retention is validated below the CLI display layer by loading the BM25 index directly, querying a known full commit ID, resolving the returned chunk through LanceDB, and confirming the actual indexed evidence.
- MCP validation requires real initialize/server-info/list-tools/tool-call exchange over stdio and return of known records.
- Cross-repository validation requires at least two distinct repository identities in the combined corpus and successful MCP retrieval of a known record from each.

## 6A. Verified external source admission boundary

The formal KB may admit a verified external asset only through the explicit accepted-source registry. This is a narrow deterministic path, not a generic semantic admission engine.

Current flow:

```text
config/accepted-knowledge-sources.json
  ↓
exact repository + commit + asset id + expected count
  ↓
canonical Git checkout bytes
  ↓
manifest SHA-256/size verification
  ↓
normal/user evidence must both pass
  ↓
exported function count verification
  ↓
one 8-field knowledge record per exported skill
  ↓
combine with pinned repository-derived records
  ↓
formal-kb.jsonl
  ↓
formal corpus/index
  ↓
real MCP retrieval gates
```

Rules:

- admission must be explicitly `verified` in the registry;
- source repository and commit are immutable inputs to one promotion run;
- on Windows, accepted source checkouts use `core.autocrlf=false` and a forced checkout/reset so manifest verification operates on canonical Git bytes rather than CRLF-transformed working-tree bytes;
- the manifest must use SHA-256 and required files must be present, size-correct, and hash-correct;
- evidence sections `normal` and `user` must explicitly report `passed=true`;
- the expected exported skill count must match the real exports;
- one exported function becomes one knowledge record with a distinct exact `source` identity;
- the evidence boundary is preserved literally. Admission never upgrades a source from “verified in local Skill Engine/repository tests” to “verified in real DebugAI LLM A/B” unless that evidence exists;
- generated accepted-source material remains outside Git under `F:\G-ACE-KB\data\knowledge-sources\accepted`;
- generic TGserver intake, semantic scoring, duplicate adjudication, supersession, and AI-assisted admission remain outside this implemented boundary.

## 7. Runtime / storage boundary

Local durable layout:

```text
F:\G-ACE-KB
├─ repo\
├─ data\
│  ├─ knowledge-records\
│  │  ├─ gace-dev-kb.jsonl
│  │  └─ formal-kb.jsonl
│  ├─ knowledge-sources\
│  │  └─ accepted\
│  └─ knowledge-search\
├─ runtime\
│  └─ mcp-vector-search\
├─ assets\
│  └─ accepted-*\
└─ .venv\
```

Git stores source, configuration, design, tests, and durable documentation. Large indexes, caches, runtime downloads, generated data, generated knowledge-record exports, secrets, and local environments stay outside Git unless a later explicit design decision changes that boundary.

Cross-repository E2E uses a temporary OS workspace for the second repository, combined records, temporary corpus, and temporary search index. The test removes that workspace after a successful run; it does not create a new persistent repository or production resource.

Knowledge-data extraction/normalization/admission from TGserver is not implemented in this repository. That processing system is a separate development scope and will integrate with TGserver and this KB later through explicit contracts.

## 8. Windows compatibility boundary

The pinned upstream runtime requires repository-managed Windows/runtime compatibility handling for measured defects:

- Unix-only `resource` import guard;
- result display fallback when original similarity is `None`;
- Kuzu cleanup path normalization;
- multiprocessing context: Windows must use `spawn`;
- MCP SDK compatibility: `mcp-vector-search` 4.1.14 uses MCP SDK 1.x decorator APIs while its dependency constraint permits installed MCP SDK 2.x; the repository bootstrap adapts the installed server to the 2.x constructor-handler API and current initialization-options path;
- embedding API compatibility: prefer the current embedding-dimension API and retain fallback only where required;
- atomic rebuild compatibility: reopen the final BM25/vector backend after the temporary Lance path is finalized on Windows;
- doc-only KG compatibility: do not attempt code-entity KG enrichment when the generated Markdown knowledge corpus contains no code entities;
- isolated trial safety may disable MVS multiprocessing through an explicit environment gate without changing normal formal-index behavior;
- canonical external-source checkout must disable CRLF rewriting before manifest byte verification.

Compatibility source alone is not enough. `tests/verify-mvs-windows.ps1` verifies the installed runtime and exact compatibility state. `scripts/index-knowledge-windows.ps1` then fails closed if the previously observed BM25 fallback, embedding deprecation, or doc-only KG entity-warning regressions reappear.

## 9. Future boundary

TGserver-linked knowledge processing/admission and any Astera-oriented KB architecture are separate future integration material. They must not be represented as current implementation until implemented and validated in their own scope and integrated through explicit contracts.

The verified ModuleCatalog admission path does not by itself implement generic intake, candidate review, confidence scoring, supersession, or rejection/audit workflows.

## 10. Current implementation boundary (2026-10-01)

Validated current capability:

- isolated OSS runtime under `F:\G-ACE-KB\runtime\mcp-vector-search`;
- repository-managed Windows bootstrap PASS;
- Windows compatibility verifier PASS;
- runtime multiprocessing context `spawn` PASS;
- MCP SDK 2.x server compatibility PASS;
- embedding dimension API compatibility PASS;
- atomic BM25 backend reopen compatibility PASS;
- doc-only KG enhancement compatibility PASS;
- deterministic repository adapter/renderer/combiner tests PASS;
- durable repository export defaults to full reachable Git history;
- formal repository revision pinned to `origin/main` commit `9520098d9666bdf33372bcd34f15758bb9c66f01`;
- formal repository export PASS: 94 records;
- accepted-source registry PASS: 1 source;
- canonical accepted-source checkout PASS with `AUTOCRLF=false`;
- accepted-source manifest preflight PASS: 13 records;
- accepted ModuleCatalog source pinned to `bd258ec91b6970853d14a7bf4e65731312a487e3`;
- accepted DebugAI reusable skills: 13 distinct records;
- formal combined knowledge PASS: 107 records / 2 repository identities;
- formal corpus PASS: 107 Markdown records;
- formal index PASS: 107/107 files, 1,167 chunks, 1,167 embeddings;
- formal knowledge graph PASS: 957 entities, 979 relationships;
- persisted BM25 index PASS;
- historical retention gate PASS for `74e8171...` and `4912a442...`;
- direct BM25 retention probe PASS for both known historical records;
- BM25 fallback-warning regression gate PASS;
- embedding deprecation-warning regression gate PASS;
- doc-only KG entity-warning regression gate PASS;
- MCP server metadata PASS: `SERVER=mcp-vector-search VERSION=0.4.0`;
- MCP repository-history retrieval PASS for `74e8171...` and `4912a442...` in BM25 mode;
- real MCP retrieval PASS for all 13 accepted DebugAI skill symbols;
- natural-language MCP skill discovery PASS for cross-file dependency tracing, false-pass detection, and targeted regression strategy;
- `GACE_DEBUGAI_SKILL_MCP_E2E=PASS RECORDS=13 NATURAL_CHECKS=3`;
- `GACE_KNOWLEDGE_INDEX=PASS RECORDS=107`;
- `GACE_FORMAL_KB_PROMOTION=PASS RECORDS=107`;
- historical cross-repository temporary E2E remains PASS: 90 records across `gace-dev-kb` and `Astera` with real MCP retrieval from both.

Local-only evidence intentionally left untouched:

- local `.gitignore` remains untracked;
- the pre-existing local `scripts/__pycache__/` remains untracked.

The current formal-KB boundary is closed for pinned repository-derived knowledge plus explicitly registered, already-verified external assets. Knowledge-data processing/admission from TGserver remains a separate development scope.
