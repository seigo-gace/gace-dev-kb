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
│  ├─ combine_knowledge_records.py
│  ├─ render_knowledge_corpus.py
│  ├─ index-knowledge-windows.ps1
│  ├─ test-mcp-knowledge-e2e-windows.ps1
│  └─ test-cross-repo-reuse-windows.ps1
├─ tests/
│  ├─ verify-mvs-windows.ps1
│  ├─ regression-mvs-windows.ps1
│  ├─ test_gace_knowledge_adapter.py
│  ├─ test_combine_knowledge_records.py
│  ├─ test_render_knowledge_corpus.py
│  ├─ bm25_knowledge_retention_probe.py
│  ├─ mcp_knowledge_client_e2e.py
│  └─ mcp_cross_repo_reuse_e2e.py
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
Repository-managed Windows bootstrap for pinned `mcp-vector-search==4.1.14` plus measured compatibility changes. Current handling includes the `resource` guard, display fallback, Kuzu path compatibility, Windows multiprocessing `spawn`, MCP SDK 2.x compatibility, embedding-dimension API compatibility, atomic BM25 backend reopen after rebuild, and doc-only KG search compatibility.

### `tests/verify-mvs-windows.ps1`
Verifies installed Windows compatibility state, CLI startup, actual `_get_mp_context()` result, MCP server creation compatibility, embedding API patch, atomic BM25 reopen patch, and doc-only KG patch. Current Master Windows result includes `MVS_WINDOWS_MP_CONTEXT=spawn`, `MVS_MCP_SDK2_COMPAT=PASS`, `MVS_EMBEDDING_DIMENSION_API=PASS`, `MVS_ATOMIC_BM25_BACKEND_REOPEN=PASS`, `MVS_DOC_ONLY_KG_ENHANCEMENT=PASS`, and `MVS_WINDOWS_COMPAT_VERIFY=PASS`.

### `tests/regression-mvs-windows.ps1`
Runs the real tracked-KB-corpus regression: preflight, temporary `respect_gitignore` isolation, full reindex, knowledge-graph validation, status, two semantic searches, and restoration of the prior setting. Current Master Windows result: `MVS_REAL_REGRESSION=PASS`.

### `scripts/gace_knowledge_adapter.py`
Deterministic Git repository → G-ACE knowledge-record projection. Reads committed Git evidence and emits `type`, `repository`, `commit`, `summary`, `cause`, `fix`, `validation`, `source`. Full repository history is exported by default; bounded `--max-count` is only explicit test/temporary behavior. It does not create another MCP server and does not replace Git authority.

### `tests/test_gace_knowledge_adapter.py`
Standard-library unit tests for adapter classification, explicit evidence-marker parsing, tracked-tree cleanliness, handling of untracked local files, JSONL contract output, and full-history retention semantics.

### `scripts/export-knowledge-windows.ps1`
Windows wrapper for the adapter. Writes generated JSONL outside Git source to `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl`. The durable default is full reachable history.

### `scripts/combine_knowledge_records.py`
Deterministically combines multiple G-ACE JSONL exports, preserves the initial knowledge contract, deduplicates identical repository/commit/type records, and fails if the resulting corpus does not contain at least two repository identities. It does not synthesize or reconcile evidence.

### `tests/test_combine_knowledge_records.py`
Unit tests for two-repository combining, duplicate suppression, and fail-closed contract/repository-count behavior. Current Master Windows result: 3/3 PASS.

### `scripts/render_knowledge_corpus.py`
Converts generated JSONL records into one deterministic Markdown document per knowledge record under the external generated-data boundary. Missing evidence is represented without synthesis.

### `tests/test_render_knowledge_corpus.py`
Validates one-record-per-file rendering, contract preservation, evidence content, and fail-closed behavior for incomplete record shapes. Current Master Windows result: 2/2 PASS.

### `tests/bm25_knowledge_retention_probe.py`
Directly loads the persisted BM25 index below the CLI rendering layer, searches for a known full commit ID, resolves the returned chunk in LanceDB, and verifies that the actual indexed chunk contains the expected commit evidence. This separates durable BM25 retention validation from CLI display behavior.

### `scripts/index-knowledge-windows.ps1`
Runs the real generated-knowledge pipeline: verify/repair pinned Windows MVS compatibility → export full committed knowledge history → render external Markdown corpus → initialize/reuse external `mcp-vector-search` project → force-index → verify exact indexed-file count → require BM25 index → run direct BM25 retention probes for the known Kuzu and G-ACE adapter records → fail closed on previously observed warning regressions.

Latest Master Windows result: 89 records, 89/89 indexed files, 625 chunks/embeddings, 534 KG entities / 533 relationships, both direct BM25 probes PASS, all three warning regression gates PASS, and `GACE_KNOWLEDGE_INDEX=PASS RECORDS=89`.

### `tests/mcp_knowledge_client_e2e.py`
Real MCP protocol client test. Launches `mcp-vector-search` over stdio using the runtime Python, initializes an MCP `ClientSession`, validates server metadata, lists tools, calls `get_project_status`, and calls `search_code` for known `74e8171...` and `4912a442...` records. Current Master Windows result: `GACE_MCP_CLIENT_E2E=PASS`.

### `scripts/test-mcp-knowledge-e2e-windows.ps1`
One-command Windows wrapper for the MCP stdio client E2E against `F:\G-ACE-KB\data\knowledge-search`. Current Master Windows result: `GACE_MCP_WINDOWS_E2E=PASS`.

### `tests/mcp_cross_repo_reuse_e2e.py`
Generic real MCP stdio cross-repository retrieval test. It accepts repeated query/commit/repository checks and requires successful retrieval from at least two distinct repository identities. The Windows child-process stderr path uses a real temporary file so the test is compatible with Windows subprocess handle requirements.

### `scripts/test-cross-repo-reuse-windows.ps1`
One-command temporary cross-repository E2E. It verifies the runtime, shallow-clones public `seigo-gace/Astera` into an OS temp directory, exports the current repository plus Astera, combines records, renders and indexes a temporary corpus, verifies exact index count, retrieves a known record from each repository through real MCP, and removes the temporary workspace on completion. Current Master Windows result: `GACE_CROSS_REPO_REUSE_E2E=PASS RECORDS=90 REPOSITORIES=2` and `CROSS_REPO_TEMP_CLEANUP=PASS`.

## Local runtime / generated-data boundary

Durable runtime/generated data remain outside Git:

```text
F:\G-ACE-KB\
├─ repo\
├─ data\
│  ├─ knowledge-records\
│  └─ knowledge-search\
├─ runtime\
│  └─ mcp-vector-search\
├─ assets\
└─ .venv\
```

Cross-repository validation uses an OS temporary directory and cleans it after a successful run.

Knowledge-data processing/admission from TGserver is a separate development scope; this repository owns the reusable KB/search/MCP side and later integration contract only.

## Current validation boundary

Validated:

```text
repository full history
→ deterministic records
→ Markdown corpus
→ mcp-vector-search index
→ persisted BM25 index
→ direct BM25 commit-evidence probe
→ MCP stdio server
→ MCP client initialize/server-info/list-tools/status/search
→ commit-backed semantic knowledge retrieval
→ multi-repository combine
→ temporary combined index
→ real MCP retrieval from both repositories
→ temporary workspace cleanup
```

The first-version repository knowledge reuse E2E and the measured Windows quality-hardening gates are closed. TGserver-linked knowledge processing/admission remains intentionally separate work.

Do not create placeholder subsystems solely to make the tree look complete.
