# G-ACE Dev KB — Project Tree

This file is the navigation map for the repository. Update it when files are added, removed, moved, or when a major responsibility changes.

## Current repository tree

```text
gace-dev-kb/
├─ README.md
├─ config/
│  └─ accepted-knowledge-sources.json
├─ docs/
│  ├─ CURRENT_DESIGN.md
│  ├─ PROJECT_TREE.md
│  └─ DESIGN_DELTA.md
├─ scripts/
│  ├─ bootstrap-mvs-windows.ps1
│  ├─ gace_knowledge_adapter.py
│  ├─ export-knowledge-windows.ps1
│  ├─ combine_knowledge_records.py
│  ├─ import_verified_modulecatalog_skills.py
│  ├─ render_knowledge_corpus.py
│  ├─ index-knowledge-windows.ps1
│  ├─ patch-mvs-windows-trial-safety.ps1
│  ├─ promote-verified-skills-to-formal-kb-windows.ps1
│  ├─ test-debugai-verified-skill-kb-windows.ps1
│  ├─ test-mcp-knowledge-e2e-windows.ps1
│  └─ test-cross-repo-reuse-windows.ps1
├─ tests/
│  ├─ verify-mvs-windows.ps1
│  ├─ regression-mvs-windows.ps1
│  ├─ test_gace_knowledge_adapter.py
│  ├─ test_combine_knowledge_records.py
│  ├─ test_import_verified_modulecatalog_skills.py
│  ├─ test_render_knowledge_corpus.py
│  ├─ bm25_knowledge_retention_probe.py
│  ├─ mcp_knowledge_client_e2e.py
│  ├─ mcp_verified_skill_trial_e2e.py
│  └─ mcp_cross_repo_reuse_e2e.py
└─ .gitignore                  # local untracked evidence; intentionally not modified here
```

## Responsibilities

### `README.md`
Mandatory entry point. Shows current validated status and links to design, tree, delta, and system documents.

### `config/accepted-knowledge-sources.json`
Explicit registry of external sources that are allowed into the formal KB. Each source pins its repository, exact commit, asset ID, expected exported-skill count, admission state, and validation boundary. This is not a generic admission queue.

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
Windows wrapper for the adapter. Writes generated JSONL outside Git source to `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl`. The durable default is full reachable history. Formal promotion may pin the export revision through `GACE_KNOWLEDGE_REVISION` so feature-branch implementation commits are not ingested as formal knowledge before merge.

### `scripts/combine_knowledge_records.py`
Deterministically combines multiple G-ACE knowledge JSONL inputs, preserves the initial knowledge contract, and treats `repository + commit + type + source` as record identity. This preserves multiple distinct reusable skills from one source commit while still suppressing true duplicates. It fails if the resulting corpus does not contain at least two repository identities and never synthesizes or reconciles evidence.

### `tests/test_combine_knowledge_records.py`
Unit tests for two-repository combining, duplicate suppression, distinct-source preservation at the same repository/commit/type, and fail-closed contract/repository-count behavior. Current formal-promotion preflight result: 4/4 PASS.

### `scripts/import_verified_modulecatalog_skills.py`
Conservative importer for an explicitly registered verified ModuleCatalog asset. It executes no asset code. It verifies SHA-256 manifest entries and required files, requires normal/user evidence `passed=true`, verifies expected exported-function count, preserves the eight-field G-ACE contract, and emits one separate record/Markdown document per exported skill symbol.

### `tests/test_import_verified_modulecatalog_skills.py`
Fail-closed importer tests covering successful 13-skill import, manifest tamper rejection, unpassed-evidence rejection, and wrong-skill-count rejection. Current formal-promotion preflight result: 4/4 PASS.

### `scripts/render_knowledge_corpus.py`
Converts generated JSONL records into one deterministic Markdown document per knowledge record under the external generated-data boundary. Missing evidence is represented without synthesis.

### `tests/test_render_knowledge_corpus.py`
Validates one-record-per-file rendering, contract preservation, evidence content, and fail-closed behavior for incomplete record shapes. Current Master Windows result: 2/2 PASS.

### `tests/bm25_knowledge_retention_probe.py`
Directly loads the persisted BM25 index below the CLI rendering layer, searches for a known full commit ID, resolves the returned chunk in LanceDB, and verifies that the actual indexed chunk contains the expected commit evidence. This separates durable BM25 retention validation from CLI display behavior.

### `scripts/index-knowledge-windows.ps1`
Runs the formal generated-knowledge pipeline: verify/repair pinned Windows MVS compatibility → export the pinned repository revision → load the accepted-source registry → checkout and import each exact verified source → assemble `formal-kb.jsonl` → render repository knowledge plus rich accepted-source Markdown → force-index the formal corpus → verify exact indexed-file count and BM25 persistence → run direct historical BM25 probes → run real MCP history retrieval → run real MCP accepted-skill retrieval. It fails closed on count, contract, compatibility, warning-regression, manifest, evidence, and MCP retrieval failures.

Latest Master Windows formal result: 94 repository records + 13 verified external skill records = 107 formal records, 107/107 indexed files, 1,167 chunks/embeddings, 957 KG entities / 979 relationships, both historical BM25 probes PASS, repository-history MCP PASS, all 13 skill-symbol MCP checks PASS, three natural-language skill-discovery checks PASS, and `GACE_KNOWLEDGE_INDEX=PASS RECORDS=107`.

### `scripts/patch-mvs-windows-trial-safety.ps1`
Opt-in isolated-trial safety patch for the pinned runtime. It recognizes `MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING=1` and disables semantic-indexer multiprocessing only for the trial path. Normal formal-KB indexing is unchanged when the variable is absent.

### `scripts/test-debugai-verified-skill-kb-windows.ps1`
Isolated Windows trial for the verified DebugAI skill pack. It pins ModuleCatalog commit `bd258ec...`, verifies the Windows MVS compatibility state, imports exactly 13 verified skills into `F:\G-ACE-KB\data\debugai-skill-trial`, builds an isolated index, and proves all 13 skills plus three natural-language queries through the real MCP stdio path. Current result: `GACE_DEBUGAI_VERIFIED_SKILL_TRIAL=PASS SKILLS=13` with the formal KB unchanged during the trial.

### `tests/mcp_verified_skill_trial_e2e.py`
Real MCP stdio retrieval gate for accepted skill records. It checks every imported skill symbol via BM25 and separately verifies natural-language retrieval for cross-file dependency tracing, false-pass detection, and targeted regression strategy. Current formal-KB result: `GACE_DEBUGAI_SKILL_MCP_E2E=PASS RECORDS=13 NATURAL_CHECKS=3`.

### `scripts/promote-verified-skills-to-formal-kb-windows.ps1`
Formal promotion gate for verified external skills. It requires a clean tracked tree, pins repository-derived knowledge to `origin/main` by default, validates the accepted-source registry, prepares canonical Windows source checkouts with `core.autocrlf=false`, performs manifest/evidence/count preflight before expensive indexing, runs unit regressions, invokes the full formal index, and requires a non-empty formal output. Current result: `GACE_FORMAL_KB_PROMOTION=PASS RECORDS=107`.

### `tests/mcp_knowledge_client_e2e.py`
Real MCP protocol client test. Launches `mcp-vector-search` over stdio using the runtime Python, initializes an MCP `ClientSession`, validates server metadata, lists tools, calls `get_project_status`, and calls `search_code` for known `74e8171...` and `4912a442...` records. Current Master Windows result: `GACE_MCP_CLIENT_E2E=PASS`.

### `scripts/test-mcp-knowledge-e2e-windows.ps1`
One-command Windows wrapper for the MCP stdio client E2E against `F:\G-ACE-KB\data\knowledge-search`. Current Master Windows result: `GACE_MCP_WINDOWS_E2E=PASS`.

### `tests/mcp_cross_repo_reuse_e2e.py`
Generic real MCP stdio cross-repository retrieval test. It accepts repeated query/commit/repository checks and requires successful retrieval from at least two distinct repository identities. The Windows child-process stderr path uses a real temporary file so the test is compatible with Windows subprocess handle requirements.

### `scripts/test-cross-repo-reuse-windows.ps1`
One-command temporary cross-repository E2E. It verifies the runtime, shallow-clones public `seigo-gace/Astera` into an OS temp directory, exports the current repository plus Astera, combines records, renders and indexes a temporary corpus, verifies exact index count, retrieves a known record from each repository through real MCP, and removes the temporary workspace on completion. Historical Master Windows result: `GACE_CROSS_REPO_REUSE_E2E=PASS RECORDS=90 REPOSITORIES=2` and `CROSS_REPO_TEMP_CLEANUP=PASS`.

## Local runtime / generated-data boundary

Durable runtime/generated data remain outside Git:

```text
F:\G-ACE-KB\
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

Cross-repository validation uses an OS temporary directory and cleans it after a successful run. Accepted external source clones are local generated/input assets outside Git source and are pinned to exact commits during promotion.

Knowledge-data processing/admission from TGserver is a separate development scope; this repository currently owns repository-derived knowledge plus explicit verified-source admission and the reusable KB/search/MCP side.

## Current validation boundary

Validated:

```text
pinned origin/main repository history
→ deterministic repository records
+
explicit accepted source registry
→ canonical exact-commit checkout
→ manifest/evidence/count verification
→ separate skill records
↓
formal record combine
→ formal-kb.jsonl
→ 107-document Markdown corpus
→ mcp-vector-search index
→ persisted BM25 + vector + KG
→ direct historical BM25 probes
→ MCP repository-history retrieval
→ MCP all-13 accepted-skill retrieval
→ MCP natural-language skill discovery
```

The current formal-KB boundary is closed for pinned repository-derived knowledge plus explicitly registered, already-verified external assets. TGserver-linked generic knowledge processing/admission remains intentionally separate work.

Do not create placeholder subsystems solely to make the tree look complete.
