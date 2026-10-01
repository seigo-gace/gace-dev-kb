# G-ACE Dev KB — Project Tree

This file is the navigation map for the repository. Update it when files are added, removed, moved, or when a major responsibility changes.

## Current repository tree

```text
gace-dev-kb/
├─ README.md
├─ docs/
│  ├─ CURRENT_DESIGN.md
│  ├─ PROJECT_TREE.md
│  └─ DESIGN_DELTA.md
├─ scripts/
│  ├─ bootstrap-mvs-windows.ps1
│  ├─ gace_knowledge_adapter.py
│  ├─ export-knowledge-windows.ps1
│  ├─ render_knowledge_corpus.py
│  └─ index-knowledge-windows.ps1
├─ tests/
│  ├─ verify-mvs-windows.ps1
│  ├─ regression-mvs-windows.ps1
│  ├─ test_gace_knowledge_adapter.py
│  └─ test_render_knowledge_corpus.py
└─ .gitignore                  # local untracked evidence; intentionally not modified here
```

## Responsibilities

### `README.md`
Mandatory entry point. Shows current validated status and links to design, tree, delta, and system documents.

### `docs/CURRENT_DESIGN.md`
Current design baseline and responsibility boundaries. Do not rewrite it merely to hide implementation drift.

### `docs/PROJECT_TREE.md`
Repository navigation and file/directory responsibilities.

### `docs/DESIGN_DELTA.md`
Append-only-style design change record: baseline difference, reason, evidence, and applying commit.

### `scripts/bootstrap-mvs-windows.ps1`
Repository-managed Windows bootstrap for pinned `mcp-vector-search==4.1.14` plus the measured Windows compatibility changes. The current bootstrap is verified on the Master Windows runtime.

### `tests/verify-mvs-windows.ps1`
Verifies installed Windows compatibility state and CLI startup. The current version has passed on the Master Windows runtime.

### `tests/regression-mvs-windows.ps1`
Runs the real tracked-KB-corpus regression: preflight, temporary `respect_gitignore` isolation, full reindex, knowledge-graph validation, status, two semantic searches, and restoration of the prior setting. The current version has produced `MVS_REAL_REGRESSION=PASS` on the Master Windows environment.

### `scripts/gace_knowledge_adapter.py`
Deterministic Git repository → G-ACE knowledge-record projection. Reads committed Git evidence and emits `type`, `repository`, `commit`, `summary`, `cause`, `fix`, `validation`, `source`. It does not create another MCP server and does not replace Git authority.

### `tests/test_gace_knowledge_adapter.py`
Standard-library unit tests for adapter classification, explicit evidence-marker parsing, tracked-tree cleanliness, handling of untracked local files, and JSONL contract output. The five-test suite has passed on the Master Windows environment. Bytecode generation is disabled so future test runs do not create a new repository `__pycache__` artifact.

### `scripts/export-knowledge-windows.ps1`
Windows wrapper for the adapter. Writes generated JSONL outside Git source to `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl`. A real Master Windows export has passed with 36 records.

### `scripts/render_knowledge_corpus.py`
Converts the generated JSONL records into one deterministic Markdown document per knowledge record under the external generated-data boundary. Missing evidence is rendered explicitly as `(not recorded)` rather than synthesized.

### `tests/test_render_knowledge_corpus.py`
Validates one-record-per-file rendering, contract preservation, evidence content, and fail-closed behavior for incomplete record shapes. Source exists; Master Windows execution is pending.

### `scripts/index-knowledge-windows.ps1`
Connects the real repository evidence pipeline end to end: export committed knowledge → render external Markdown corpus → initialize/reuse an external `mcp-vector-search` project → force-index it → verify indexed-file count → prove retrieval of the known Kuzu compatibility fix and G-ACE adapter records. Source exists; Master Windows runtime validation is pending.

## Local runtime / generated-data boundary

The runtime and generated data are intentionally outside this Git tree:

```text
F:\G-ACE-KB\
├─ repo\
├─ data\
│  ├─ knowledge-records\       # generated JSONL; not Git source
│  └─ knowledge-search\
│     ├─ records\              # generated Markdown corpus; not Git source
│     └─ .mcp-vector-search\   # generated search index/config; not Git source
├─ runtime\
│  └─ mcp-vector-search\       # mcp-vector-search 4.1.14 isolated runtime
├─ assets\
└─ .venv\
```

Runtime packages, model caches, generated vector/index data, generated knowledge records, secrets, and local environment files are not repository source unless a later explicit design decision changes that boundary.

## Planned only after implementation requires them

The following are not considered complete merely because source exists:

```text
Master Windows validation of generated-record → mcp-vector-search indexing
MCP server → AI client E2E
cross-repository knowledge reuse E2E
Astera-oriented future architecture
```

Do not create placeholder subsystems solely to make the tree look complete.
