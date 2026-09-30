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

`mcp-vector-search` 4.1.14 is the active OSS search/index core. Windows real-environment validation has passed for installation, dependency health, repository indexing, embedding generation, knowledge-graph build, and semantic retrieval. This does not yet establish MCP client E2E, automatic repository-to-KB ingestion, or cross-repository reuse E2E.

## 6. Runtime / storage boundary

Local root:

```text
F:\G-ACE-KB
├─ repo\       # this Git repository
├─ data\       # local KB/index data; not Git source
├─ runtime\    # OSS runtime; not Git source unless explicitly vendored later
├─ assets\     # local migration/input assets
└─ .venv\      # local environment from earlier preparation; not Git source
```

Git stores source, configuration, design, tests, and durable documentation. Large indexes, caches, runtime downloads, generated data, secrets, and local environments stay outside Git unless a later design decision explicitly changes that boundary.

## 7. Future boundary

Astera-based KB architecture is future implementation material. It must not be represented as current implementation until implemented and validated. Future design material must remain clearly separated from the current baseline.


## 8. Current implementation boundary (2026-09-30)

Validated current capability:

- isolated OSS runtime under `F:\G-ACE-KB\runtime\mcp-vector-search`;
- Windows CLI and dependency doctor pass after a local compatibility patch;
- real repository index pass: 4 files, 119 chunks, 119 embeddings;
- knowledge graph build pass: 44 entities, 43 relationships;
- semantic retrieval pass against known design and failure/root-cause/fix/validation content.

Not yet implemented or not yet validated:

- repository-managed reproducible Windows compatibility/bootstrap handling;
- G-ACE repository/knowledge adapter;
- automatic repository-to-KB ingestion;
- MCP server to AI-client E2E;
- cross-repository knowledge reuse E2E.

The local OSS runtime and generated index remain outside Git source. Runtime-local manual patches are evidence of compatibility work, not durable repository implementation.
