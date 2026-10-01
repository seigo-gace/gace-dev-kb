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
│  ├─ index-knowledge-windows.ps1
│  └─ test-mcp-knowledge-e2e-windows.ps1
├─ tests/
│  ├─ verify-mvs-windows.ps1
│  ├─ regression-mvs-windows.ps1
│  ├─ test_gace_knowledge_adapter.py
│  ├─ test_render_knowledge_corpus.py
│  └─ mcp_knowledge_client_e2e.py
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
Repository-managed Windows bootstrap for pinned `mcp-vector-search==4.1.14` plus measured compatibility changes. Current Windows handling includes the `resource` import guard, display fallback, Kuzu path compatibility, and multiprocessing `spawn` selection.

### `tests/verify-mvs-windows.ps1`
Verifies installed Windows compatibility state, CLI startup, and actual `_get_mp_context()` result. Current Master Windows result: `MVS_WINDOWS_MP_CONTEXT=spawn` and `MVS_WINDOWS_COMPAT_VERIFY=PASS`.

### `tests/regression-mvs-windows.ps1`
Runs the real tracked-KB-corpus regression: preflight, temporary `respect_gitignore` isolation, full reindex, knowledge-graph validation, status, two semantic searches, and restoration of the prior setting. Current Master Windows result: `MVS_REAL_REGRESSION=PASS`.

### `scripts/gace_knowledge_adapter.py`
Deterministic Git repository → G-ACE knowledge-record projection. Reads committed Git evidence and emits `type`, `repository`, `commit`, `summary`, `cause`, `fix`, `validation`, `source`. It does not create another MCP server and does not replace Git authority.

### `tests/test_gace_knowledge_adapter.py`
Standard-library unit tests for adapter classification, explicit evidence-marker parsing, tracked-tree cleanliness, handling of untracked local files, and JSONL contract output. Current Master Windows result: 5/5 PASS. Bytecode generation is suppressed for current test execution.

### `scripts/export-knowledge-windows.ps1`
Windows wrapper for the adapter. Writes generated JSONL outside Git source to `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl`. The latest full pipeline exported 47 records.

### `scripts/render_knowledge_corpus.py`
Converts generated JSONL records into one deterministic Markdown document per knowledge record under the external generated-data boundary. Missing evidence is represented without synthesis.

### `tests/test_render_knowledge_corpus.py`
Validates one-record-per-file rendering, contract preservation, evidence content, and fail-closed behavior for incomplete record shapes. Current Master Windows result: 2/2 PASS.

### `scripts/index-knowledge-windows.ps1`
Runs the real generated-knowledge pipeline: verify/repair pinned Windows MVS compatibility → export committed knowledge → render external Markdown corpus → initialize/reuse external `mcp-vector-search` project → force-index → verify exact indexed-file count → retrieve known Kuzu and G-ACE adapter records. Current Master Windows result: `GACE_KNOWLEDGE_INDEX=PASS RECORDS=47`, 47/47 files and 331 chunks.

### `tests/mcp_knowledge_client_e2e.py`
Real MCP protocol client test. Launches `mcp-vector-search` over stdio using the runtime Python, initializes an MCP `ClientSession`, lists tools, calls `get_project_status`, and calls `search_code` for the known `74e8171...` and `4912a442...` records. Source exists; Master Windows execution is pending.

### `scripts/test-mcp-knowledge-e2e-windows.ps1`
One-command Windows wrapper for the MCP stdio client E2E against `F:\G-ACE-KB\data\knowledge-search`. It does not reinstall or reindex the already validated knowledge corpus unless a later design explicitly adds such a requirement.

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

## Current validation boundary

Validated:

```text
repository → deterministic records → Markdown corpus → mcp-vector-search index → direct semantic retrieval
```

Pending real Windows validation:

```text
mcp-vector-search stdio server → MCP client initialize/list-tools/tool-call → knowledge retrieval
cross-repository knowledge reuse E2E
```

Do not create placeholder subsystems solely to make the tree look complete.
