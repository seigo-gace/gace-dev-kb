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

`mcp-vector-search` 4.1.14 is the active OSS search/index/MCP core. Repository-managed Windows compatibility, repository regression, deterministic repository-to-record adaptation, generated knowledge-corpus indexing, and semantic retrieval have passed on the Master Windows environment. The next runtime gate is retrieval through the real MCP stdio protocol rather than direct CLI search.

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
semantic retrieval
  ↓
MCP stdio server
  ↓
AI/MCP client
```

Adapter and retrieval rules:

- Git remains authority; the adapter only projects committed evidence.
- Generic MCP/search capability stays in `mcp-vector-search`; do not build a second MCP server for the adapter.
- Record generation must be deterministic and must not invent missing cause, fix, validation, or source evidence.
- Explicit commit-body markers (`Cause:`, `Fix:`, `Validation:`, `Source:`) may populate corresponding fields.
- When a field is not supported by committed evidence, it remains empty rather than being synthesized.
- Modified or staged tracked files block normal export so uncommitted work is not represented as durable knowledge.
- Untracked local-only files do not block export.
- Generated JSONL, rendered corpus, MVS config, and MVS index stay outside repository source under `F:\G-ACE-KB\data`.
- Searchability is implemented by rendering one Markdown document per knowledge record rather than mutating the initial record contract to fit the OSS parser.
- Windows compatibility is verified before generated-knowledge indexing; the pipeline may repair the pinned runtime compatibility layer and then reverify it.
- MCP E2E must prove a real initialize/list-tools/tool-call exchange over stdio and return known commit-backed records before MCP integration is called validated.

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
├─ runtime\
│  └─ mcp-vector-search\       # pinned 4.1.14 runtime with measured Windows compatibility layer
├─ assets\
└─ .venv\
```

Git stores source, configuration, design, tests, and durable documentation. Large indexes, caches, runtime downloads, generated data, generated knowledge-record exports, secrets, and local environments stay outside Git unless a later explicit design decision changes that boundary.

## 8. Windows compatibility boundary

The pinned upstream runtime currently requires repository-managed Windows compatibility handling for measured defects:

- Unix-only `resource` import guard;
- result display fallback when original similarity is `None`;
- Kuzu cleanup path normalization;
- multiprocessing context: Windows must use `spawn`, not upstream's non-macOS `fork` default.

Compatibility source alone is not enough: `tests/verify-mvs-windows.ps1` verifies the installed runtime and executes `_get_mp_context()` to require `spawn` on Windows.

## 9. Future boundary

Astera-based KB architecture is future implementation material. It must not be represented as current implementation until implemented and validated. Future design material must remain clearly separated from the current baseline.

## 10. Current implementation boundary (2026-10-01)

Validated current capability:

- isolated OSS runtime under `F:\G-ACE-KB\runtime\mcp-vector-search`;
- repository-managed Windows bootstrap PASS;
- Windows compatibility verifier PASS;
- runtime multiprocessing context `spawn` PASS;
- repository tracked-corpus reindex PASS: 4 files, 161 chunks, 161 embeddings;
- repository knowledge graph PASS: 58 entities, 57 relationships;
- repository semantic design and failure/root-cause/fix/validation retrieval PASS;
- real repository regression gate PASS;
- G-ACE knowledge adapter unit tests PASS: 5/5;
- renderer tests PASS: 2/2;
- latest full knowledge export PASS: 47 records;
- generated knowledge corpus PASS: 47 Markdown records;
- generated knowledge index PASS: 47/47 files, 331 chunks, 331 embeddings;
- generated knowledge graph PASS: 282 entities, 281 relationships;
- semantic retrieval of Kuzu compatibility record `74e8171...` PASS and ranked first;
- semantic retrieval of G-ACE adapter record `4912a442...` PASS and ranked first;
- `GACE_KNOWLEDGE_INDEX=PASS RECORDS=47`.

Observed but not closed:

- BM25 index build emits a non-fatal Lance warning and hybrid mode falls back to vector-only;
- semantic searches emit entity-matching warnings despite returning the required records;
- the embedding library emits a deprecation `FutureWarning` for `get_sentence_embedding_dimension`;
- local `.gitignore` remains untracked and is intentionally not mutated by repository automation;
- the pre-existing local `scripts/__pycache__/` remains untouched; current Python test commands suppress new bytecode generation.

Implemented in repository source, pending Windows runtime validation:

- MCP stdio server → MCP Python client E2E;
- MCP initialize and tool-list verification;
- MCP `get_project_status` call;
- MCP `search_code` retrieval gates for `74e8171...` and `4912a442...`.

Not yet completed or not yet validated:

- Master Windows `GACE_MCP_CLIENT_E2E=PASS`;
- cross-repository knowledge reuse E2E.
