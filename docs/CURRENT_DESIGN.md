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
  ├─ README update required?
  ├─ Project Tree update required?
  ├─ Design Delta update required?
  └─ System document update required?
  ↓
Completion Gate
  ↓
Knowledge ingestion
  ↓
Search / reuse in later repository development
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

The first useful version must preserve and retrieve the development knowledge needed for reuse:

- reusable implementation
- design and decision rationale
- successful outcomes
- failures and failure reasons
- root causes
- fixes
- tests and validation results
- commit/evidence references

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

`mcp-vector-search` 4.1.14 is the active OSS search/index core. The repository-managed Windows bootstrap, compatibility verification, real full reindex, knowledge-graph build, semantic retrieval regression, deterministic repository-to-record adapter, and real JSONL export have passed on the Master Windows environment. Generated-record indexing source now exists and is the next runtime gate.

## 6. G-ACE repository / knowledge adapter boundary

The adapter sits between committed repository evidence and the generic OSS search layer:

```text
Git repository / committed evidence
  ↓
G-ACE Knowledge Adapter
  ↓
initial knowledge record
  ├─ type
  ├─ repository
  ├─ commit
  ├─ summary
  ├─ cause
  ├─ fix
  ├─ validation
  └─ source
  ↓
generated JSONL outside Git source
  ↓
deterministic Markdown knowledge corpus outside Git source
  ↓
dedicated mcp-vector-search knowledge index
  ↓
semantic retrieval / later reuse
```

Adapter rules:

- Git remains authority; the adapter only projects committed evidence.
- Generic MCP/search capability stays in `mcp-vector-search`; do not build a second MCP server for the adapter.
- Record generation must be deterministic and must not invent missing cause, fix, validation, or source evidence.
- Explicit commit-body markers (`Cause:`, `Fix:`, `Validation:`, `Source:`) may populate corresponding fields.
- When a field is not supported by committed evidence, it remains empty rather than being synthesized.
- Modified or staged tracked files block normal export so uncommitted work is not represented as durable knowledge.
- Untracked local-only files do not block export.
- Generated JSONL, rendered corpus, MVS config, and MVS index stay outside the repository source tree under `F:\G-ACE-KB\data`.
- Searchability is implemented by rendering one Markdown document per knowledge record rather than changing the initial knowledge contract merely to match an OSS input format.

Master Windows evidence has validated the adapter unit tests and a real 36-record JSONL export. The generated Markdown corpus/index/retrieval pipeline is implemented in source but not yet runtime PASS.

## 7. Runtime / storage boundary

Local root:

```text
F:\G-ACE-KB
├─ repo\       # this Git repository
├─ data\
│  ├─ knowledge-records\       # generated JSONL; not Git source
│  └─ knowledge-search\
│     ├─ records\              # rendered Markdown corpus; not Git source
│     └─ .mcp-vector-search\   # generated search config/index; not Git source
├─ runtime\    # OSS runtime; not Git source unless explicitly vendored later
├─ assets\     # local migration/input assets
└─ .venv\      # local environment from earlier preparation; not Git source
```

Git stores source, configuration, design, tests, and durable documentation. Large indexes, caches, runtime downloads, generated data, generated knowledge-record exports, secrets, and local environments stay outside Git unless a later design decision explicitly changes that boundary.

## 8. Future boundary

Astera-based KB architecture is future implementation material. It must not be represented as current implementation until implemented and validated. Future design material must remain clearly separated from the current baseline.

## 9. Current implementation boundary (2026-10-01)

Validated current capability:

- isolated OSS runtime under `F:\G-ACE-KB\runtime\mcp-vector-search`;
- repository-managed Windows bootstrap PASS;
- Windows compatibility verifier PASS;
- full tracked-corpus reindex PASS: 4 files, 161 chunks, 161 embeddings;
- knowledge graph build PASS: 58 entities, 57 relationships;
- status PASS: 4/4 indexed with mcp-vector-search 4.1.14;
- semantic design retrieval PASS;
- semantic failure/root-cause/fix/validation retrieval PASS;
- real Windows regression gate PASS;
- temporary regression override of `respect_gitignore` restored to its original `true` value;
- G-ACE knowledge adapter unit tests PASS: 5/5;
- real G-ACE JSONL export PASS: 36 records;
- Windows export wrapper PASS: 36 records.

Observed but not closed:

- BM25 index build emitted a non-fatal warning and hybrid search fell back to vector-only mode during repository regression;
- semantic searches emitted entity-matching warnings despite returning the required results;
- local `.gitignore` remains untracked and is intentionally not mutated by repository automation;
- the first adapter test run created local `scripts/__pycache__/`; future test execution disables bytecode generation, while the existing local cache remains untouched pending explicit cleanup.

Implemented in repository source, pending Windows runtime validation:

- deterministic JSONL → Markdown knowledge corpus renderer;
- renderer tests;
- generated-record → dedicated `mcp-vector-search` knowledge indexing wrapper;
- known-record retrieval gates for the Kuzu Windows-path fix and G-ACE adapter implementation.

Not yet implemented or not yet validated:

- Windows real-runtime knowledge corpus/index/retrieval PASS;
- MCP server to AI-client E2E;
- cross-repository knowledge reuse E2E.
