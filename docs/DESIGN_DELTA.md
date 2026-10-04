# G-ACE Dev KB — Design Delta

## Purpose

Record intentional differences from the design baseline without erasing the history of why the design changed.

For each accepted design change, record:

- date
- affected baseline / responsibility
- previous design
- implemented/new design
- reason for the change
- evidence / validation
- applying commit

Do not record unimplemented ideas as completed changes.

---

## 2026-09-30 — Repository bootstrap baseline

**Status:** baseline established.

The new `gace-dev-kb` repository was created to replace the ambiguous old `kb-system` direction with a repository-development knowledge reuse purpose.

Current baseline decisions:

- repository work is the source of development knowledge;
- README is the mandatory entry point;
- design is preserved as a baseline rather than silently overwritten to match code drift;
- implementation differences must be recorded here with reason and commit;
- completed/validated capability is reflected in README;
- Project Tree is updated for structural/responsibility changes;
- generic KB/search/MCP capability should be obtained from OSS where practical;
- only G-ACE-specific knowledge/repository integration is custom-built;
- Astera-oriented architecture remains future work until actually implemented and validated.

This entry establishes the baseline and is not evidence that the OSS runtime or KB ingestion is implemented.

---

## 2026-09-30 — OSS core candidate changed after Windows precheck

**Status:** superseded by the validated installation/CLI gate below.

### Previous design candidate

Stratum was the first OSS-core candidate, subject to Windows real-environment validation.

### Real-environment evidence

Master's Windows precheck reported:

- `rustc`: not installed
- `cargo`: not installed
- `rustup`: not installed
- `cl`: not installed
- `cmake`: not installed
- `make`: not installed
- Git: available
- existing D-drive Python and Node runtimes are already available from prior precheck
- `F:` has approximately 948 GB free

### Decision

Do not install a Rust/Windows native build toolchain solely to adopt Stratum. That would violate the shortest-path implementation rule.

Return `mcp-vector-search` to the first implementation candidate because its installation is available through PyPI, it provides MCP integration and semantic repository/code search, and it can use the already-present Python runtime.

---

## 2026-09-30 — mcp-vector-search Windows installation and CLI compatibility gate

**Status:** INSTALL + CLI + DOCTOR PASS; later entries supersede the remaining index/regression state.

### Installed runtime

- local isolated runtime: `F:\G-ACE-KB\runtime\mcp-vector-search`
- Python: 3.13.15
- `mcp-vector-search`: 4.1.14
- dependency installation: PASS
- LanceDB: available
- Sentence Transformers: available
- Tree-sitter / language pack: available
- Typer / Rich / Pydantic / Watchdog / Loguru: available

### Upstream Windows defect found

The installed upstream CLI imported Python's Unix-only `resource` module unconditionally in `mcp_vector_search/cli/main.py`.

Observed failure:

`ModuleNotFoundError: No module named 'resource'`

The same upstream file already contains a Windows guard in `_raise_file_descriptor_limit()` because Windows does not use `RLIMIT_NOFILE`. The unconditional module-level import prevented execution from ever reaching that guard.

### Local compatibility patch

The runtime copy was minimally patched so `resource` is imported only when `sys.platform != "win32"`.

A backup of the original installed file was retained as `main.py.gace-original`.

This patch originally lived only in the local installed OSS runtime. A later design delta records the repository-managed bootstrap that made the compatibility handling reproducible.

### Validation after patch

- `mcp-vector-search --help`: PASS
- `mcp-vector-search doctor`: PASS
- doctor result: all checked dependencies available

### Current decision

Continue with `mcp-vector-search` as the active OSS-core candidate. Do not add another OSS core while this candidate is passing the current gates.

---

## 2026-09-30 — mcp-vector-search real index and semantic retrieval validated

**Status:** superseded by the 2026-10-01 managed regression evidence below.

### Evidence at this point

Windows real-environment execution against `F:\G-ACE-KB\repo` produced:

- mcp-vector-search 4.1.14;
- indexed files: 4/4;
- chunks: 119;
- embeddings: 119;
- embedding model: `sentence-transformers/all-MiniLM-L6-v2`;
- knowledge graph: 44 entities / 43 relationships;
- semantic design query returned `CURRENT_DESIGN.md` as the first result;
- semantic failure/root-cause/fix/validation query returned relevant repository knowledge.

### Compatibility findings

Two runtime-local compatibility issues were encountered:

1. upstream CLI imported the Unix-only Python `resource` module on Windows;
2. search-result rendering attempted percentage formatting when the original similarity value was `None`.

Both were minimally patched in the isolated installed runtime and the resulting CLI/search gates passed.

A Windows-path knowledge-graph delete warning and entity-matching warnings were also observed. The graph subsequently completed successfully. These warnings were retained as unresolved compatibility evidence rather than being reported as fixed.

### Current design decision

Adopt `mcp-vector-search` as the active OSS search/index core for the current implementation path. Do not add another generic search/KB core without a measured gap.

---

## 2026-09-30 — repository-managed Windows compatibility bootstrap added

**Status:** superseded by the verified 2026-10-01 runtime result below.

### Change

Added a repository-managed PowerShell bootstrap for pinned `mcp-vector-search==4.1.14` plus verification/regression scripts. The bootstrap reproduces the measured compatibility changes and later gained Windows Kuzu path handling.

### Boundary

Repository source removed the dependence on undocumented manual site-packages edits, but runtime PASS still required execution on the Master Windows environment. That execution is recorded below.

---

## 2026-10-01 — repository-managed Windows bootstrap and real regression validated

**Status:** PASS for the current Windows OSS-core regression boundary.

### Implemented/new design

The Windows compatibility path is now repository-managed rather than dependent on one-off manual edits. The active feature branch contains:

- pinned `mcp-vector-search==4.1.14` bootstrap;
- Windows `resource` import guard handling;
- result-rendering fallback when original similarity is `None`;
- Kuzu Windows path normalization for knowledge-graph cleanup;
- installed-runtime compatibility verifier;
- real regression gate that isolates the tracked KB corpus from local `.gitignore` behavior, performs a force reindex, validates KG/status/search, then restores the original `respect_gitignore` value.

### Applying implementation commits

- `fde697702ae7b8caff7c95fa6dc47fb22b28963a` — make Kuzu runtime patch robust to line-ending/indent differences;
- `f996f7541ead13ec69d942ee6b67af023b9aa2b3` — avoid PowerShell native-warning false failures in regression;
- `71da8659e3bc5ad517ade089278facc479e7b598` — stream regression progress and bound execution with timeouts;
- `a1067814fd4ce9da3b0b432cbe5316a910de1d9e` — isolate tracked-corpus regression from local `.gitignore` and restore settings.

### Real Windows evidence

Master Windows execution produced:

- `MVS_WINDOWS_BOOTSTRAP=PASS`;
- `MVS_WINDOWS_COMPAT_VERIFY=PASS`;
- tracked KB documents: 4;
- full reindex: 4 files / 161 chunks / 161 embeddings;
- embedding model: `sentence-transformers/all-MiniLM-L6-v2`;
- knowledge graph: 58 entities / 57 relationships;
- status: 4/4 indexed, mcp-vector-search 4.1.14;
- semantic design query: `CURRENT_DESIGN.md` ranked first;
- semantic failure/root-cause/fix/validation query: expected repository knowledge returned;
- `MVS_REAL_REGRESSION=PASS`;
- `respect_gitignore` restored to its original `true` value after regression.

### Retained unresolved evidence

The gate passed, but the following warnings are intentionally retained as follow-up evidence:

- BM25 index build emitted a non-fatal Lance file warning, causing hybrid search to fall back to vector-only mode;
- semantic searches emitted `Could not find entity matching ...` warnings while still returning the required results;
- local `.gitignore` remains untracked and is intentionally not modified by the repository automation.

These warnings are not reclassified as fixed merely because the current regression passes.

### Current decision

The generic OSS search/index core and its repository-managed Windows regression boundary are validated for the current repository corpus. The next custom work is limited to G-ACE-specific repository/knowledge adaptation and then automatic ingestion/reuse E2E.

---

## 2026-10-01 — deterministic G-ACE repository knowledge adapter source added

**Status:** superseded by the real Windows adapter validation below.

### Previous design

The repository defined the initial knowledge contract and stated that only G-ACE-specific repository/knowledge integration should be custom-built, but no durable adapter source existed.

### Implemented/new design

Added a deterministic Git-based adapter that projects committed repository evidence into the initial contract:

- `type`
- `repository`
- `commit`
- `summary`
- `cause`
- `fix`
- `validation`
- `source`

Rules:

- Git remains source of truth;
- no AI synthesis is used to fill missing evidence;
- explicit commit-body markers `Cause:`, `Fix:`, `Validation:`, and `Source:` populate corresponding fields when present;
- missing evidence remains empty;
- conventional commit prefix and changed paths provide deterministic record classification;
- modified/staged tracked files block normal export;
- untracked files do not block export;
- generated JSONL is written outside Git source under `F:\G-ACE-KB\data\knowledge-records`;
- the adapter does not create another MCP server; generic MCP/search remains the responsibility of `mcp-vector-search`.

### Applying implementation commits

- `4912a442fc44be5fd2bd8e8796af8bd807e954c8` — deterministic knowledge adapter;
- `daa68d5611d6fdb7aa48b6c6703ec997a835d79f` — adapter contract/unit tests;
- `9ef50415772bef11961fe709a836239f34af5cf7` — Windows export wrapper.

---

## 2026-10-01 — G-ACE adapter and real JSONL export validated

**Status:** PASS for repository → deterministic knowledge-record export.

### Real Windows evidence

Master Windows execution at `2652adc797af18c76742680ee85ab1eb7b1e242d` produced:

- adapter unit suite: 5 tests executed, all `OK`;
- `GACE_KNOWLEDGE_EXPORT=PASS`;
- exported records: 36;
- `GACE_KNOWLEDGE_WINDOWS_EXPORT=PASS`;
- output: `F:\G-ACE-KB\data\knowledge-records\gace-dev-kb.jsonl`;
- sampled records contained the required contract keys and real repository/commit/source values;
- local repository state remained otherwise unchanged except the pre-existing untracked `.gitignore` and a Python `scripts/__pycache__/` created by the first test execution.

### Follow-up correction

The adapter unit test was changed to disable bytecode generation so future executions do not create a new `__pycache__` artifact. The existing local cache is not deleted automatically because it is local state, not repository source.

### Current decision

The repository → knowledge-record stage is now validated. The next runtime gate is generated record → searchable OSS knowledge index.

---

## 2026-10-01 — generated knowledge corpus and OSS indexing pipeline source added

**Status:** superseded by the real Windows generated-index validation below.

### Implemented/new design

The initial JSONL contract remains the canonical generated record shape. A deterministic projection converts those records into Markdown solely as an OSS search input format, without changing or inventing knowledge fields.

Generated runtime boundary:

```text
F:\G-ACE-KB\data\
├─ knowledge-records\
│  └─ gace-dev-kb.jsonl
└─ knowledge-search\
   ├─ records\
   └─ .mcp-vector-search\
```

The pipeline reruns the deterministic Git knowledge export, renders one Markdown file per record, initializes/reuses a dedicated `mcp-vector-search` project outside Git source, force-indexes the generated corpus, verifies exact indexed-file count, and searches for known Kuzu and adapter records.

### Applying implementation commits

- `8342c868a62be6dacc7922d526d6d40f59a99619` — deterministic JSONL → Markdown corpus renderer;
- `61cc0f903171f93412be0828c0dadc196424e260` — Windows generated knowledge indexing/retrieval wrapper;
- `1172ae12eccb1b159588940b621c93ffd5fd5b4d` — renderer contract tests;
- `3cdf008054f333e0fa56e82b0b6442457f9f14af` — prevent future adapter-test bytecode cache creation.

---

## 2026-10-01 — generated knowledge index and retrieval validated

**Status:** PASS for repository records → rendered corpus → OSS index → direct retrieval.

### Runtime compatibility added during validation

Real Windows indexing exposed an upstream multiprocessing defect: `mcp-vector-search` 4.1.14 selected `fork` for every non-macOS platform, while Windows requires `spawn`.

Repository-managed compatibility was extended so Windows returns `spawn`, the verifier executes the real context probe, and the index pipeline self-repairs/reverifies before indexing.

### Applying compatibility commits

- `68a2d6c...` — use `spawn` multiprocessing context on Windows;
- `e566e1c...` — verify Windows multiprocessing compatibility;
- `511ec3672b2253dec8e224b10fb9b8067ddd7c19` — self-heal Windows MVS compatibility before knowledge indexing.

### Real Windows evidence

The latest validated run produced:

- `MVS_WINDOWS_MP_CONTEXT=spawn`;
- `MVS_WINDOWS_COMPAT_VERIFY=PASS`;
- `GACE_KNOWLEDGE_EXPORT=PASS RECORDS=47`;
- `GACE_KNOWLEDGE_CORPUS=PASS RECORDS=47`;
- full generated-corpus reindex: 47 files / 331 chunks / 331 embeddings;
- generated knowledge graph: 282 entities / 281 relationships;
- status: 47/47 indexed;
- Kuzu compatibility knowledge `74e8171...` retrieved first;
- adapter knowledge `4912a442...` retrieved first;
- `GACE_KNOWLEDGE_INDEX=PASS RECORDS=47`.

### Retained warnings

- BM25 build still emits a non-fatal Lance missing-file warning and hybrid search falls back to vector-only;
- entity-matching warnings still appear during semantic search;
- the embedding library still emits a deprecation `FutureWarning`.

These warnings remain follow-up evidence and are not hidden by the PASS result.

---

## 2026-10-01 — MCP SDK 2.x compatibility and real MCP client E2E validated

**Status:** PASS for generated knowledge retrieval through the real MCP stdio protocol.

### Defect found

`mcp-vector-search` 4.1.14 declares `mcp>=1.12.4` without an upper bound and the installed runtime resolved MCP SDK 2.2.0. The upstream server still used the older decorator registration API (`server.list_tools()` / `server.call_tool()`), causing the stdio child process to close during client initialization.

### Implemented compatibility adaptation

The repository-managed bootstrap now adapts the installed pinned runtime to the MCP SDK 2.x constructor-handler interface and uses the current server initialization-options path. The verifier checks the patched source and performs real server creation. PowerShell probe handling was also corrected so informational stderr does not become a false `NativeCommandError` under `$ErrorActionPreference='Stop'`.

### Applying implementation/fix commits

- `04a05afae8c74bab7985af1db066026ea20e26c1` — adapt MVS MCP server to MCP SDK 2.x;
- `ba737f815a522c66f18d2351cc113dd18bc7a400` — verify MCP SDK 2 server compatibility;
- `82b85794c85b67c7a09daf3d25d980e41532a095` — self-heal MCP runtime compatibility before E2E;
- `f101873dd20b5427dd6c64abb75d56aa2767dc5b` — surface MCP server stderr on stdio failure;
- `9ec32b74ab90a1433b3cf940b327012ee2fe2328` — tolerate informational MCP probe stderr in bootstrap;
- `4621ddfe9a255e0624653220f23b1d210966111b` — apply the same correct probe behavior in verifier.

### Real Windows evidence

Master Windows execution at `4621ddfe9a255e0624653220f23b1d210966111b` produced:

- `MVS_WINDOWS_MP_CONTEXT=spawn`;
- `MVS_MCP_SDK2_COMPAT=PASS`;
- `MVS_WINDOWS_COMPAT_VERIFY=PASS`;
- `MCP_INITIALIZE=PASS`;
- `MCP_LIST_TOOLS=PASS COUNT=28`;
- `MCP_PROJECT_STATUS=PASS`;
- `MCP_SEARCH_KUZU=PASS COMMIT=74e8171`;
- `MCP_SEARCH_ADAPTER=PASS COMMIT=4912a442`;
- `GACE_MCP_CLIENT_E2E=PASS`;
- `GACE_MCP_WINDOWS_E2E=PASS`.

Client-side output reported server name/version as `unknown`; initialization itself succeeded. That display detail was later closed by reading MCP SDK 2 `server_info` correctly.

### Current decision

The first repository can now move from committed Git evidence through deterministic record projection, generated indexing, and real MCP client retrieval. The remaining first-version proof is cross-repository reuse.

---

## 2026-10-01 — cross-repository knowledge reuse E2E source added

**Status:** superseded by the validated Master Windows cross-repository E2E below.

### Implemented/new design

Cross-repository reuse is tested without creating a new persistent repository or production resource. The Windows E2E uses a temporary OS workspace:

1. verify/repair the existing pinned MVS/MCP runtime;
2. shallow-clone public `seigo-gace/Astera` into the temporary workspace;
3. export deterministic records from current `gace-dev-kb` and Astera;
4. combine them without changing the initial record contract or reconciling missing/conflicting evidence;
5. render and index a temporary combined corpus;
6. verify exact indexed-record count;
7. launch the real MCP stdio server/client path;
8. retrieve a known `gace-dev-kb` record and Astera commit `5ef89073...`;
9. require two distinct repository identities;
10. remove the temporary workspace after success.

### Applying implementation commits

- `a017c934fcf32db617853995416ff830c181ae36` — deterministic multi-repository record combiner;
- `521aef8c31e5ad8e7ab2e447e8df594f214b66b4` — combiner tests;
- `c5fa4be11c8145bcab0c261572fe26630a329cdd` — real MCP cross-repository retrieval client;
- `e46e654c5ecd26f6f94967365fe5574e96d2ad28` — one-command Windows cross-repository reuse E2E;
- `633e2dcf0fb173123d75a4408b2db77fc9a63a93` — remove snippet-dependent repository assertion;
- `5d1835d944df047cd8615f1d66c869872781fa91` — verify repository identities before MCP retrieval;
- `de7f0888335978b6570ae78aadcd90237e1dc257` — harden combined-record repository identity checks;
- `d188c97ff9254922be9dfb3aee1b6119e13cf650` — use a real stderr file for Windows MCP subprocess handling.

---

## 2026-10-01 — cross-repository knowledge reuse E2E validated

**Status:** PASS for first-version cross-repository reuse.

### Real Windows evidence

The validated run used public `seigo-gace/Astera` as the second repository and produced:

- deterministic combiner tests: 3/3 PASS;
- 70 current-repository records + 20 Astera records = 90 combined records;
- 90/90 indexed files;
- 633 chunks / 633 embeddings;
- 540 knowledge-graph entities / 539 relationships;
- real MCP retrieval from `seigo-gace/gace-dev-kb` commit `a017c934...`: PASS;
- real MCP retrieval from `seigo-gace/Astera` commit `5ef89073...`: PASS;
- `GACE_CROSS_REPO_MCP_REUSE=PASS CHECKS=2 REPOSITORIES=2`;
- `GACE_CROSS_REPO_REUSE_E2E=PASS RECORDS=90 REPOSITORIES=2`;
- `CROSS_REPO_TEMP_CLEANUP=PASS`.

### Decision

The first-version repository → knowledge → index → MCP → cross-repository reuse boundary is closed. Further work in this repository must be measured quality hardening or an explicitly approved new scope.

---

## 2026-10-01 — full-history retention and Windows search-quality hardening validated

**Status:** PASS for durable full-history retention, persisted BM25 evidence, warning regression protection, and MCP retrieval.

### Problem found

The initial Windows export/index wrapper bounded the durable export to the newest records. As the repository grew, older but still-valid knowledge such as `74e8171...` could fall outside the generated corpus even though Git still contained it. During the same hardening phase, real runtime evidence also showed:

- atomic rebuild could leave BM25 bound to a temporary Lance path;
- the installed embedding library emitted the `get_sentence_embedding_dimension` deprecation warning;
- doc-only Markdown knowledge search attempted code-entity KG enhancement and emitted `Could not find entity matching ...` warnings;
- MCP SDK 2 server metadata was displayed as `unknown` by the client despite successful initialization;
- CLI rendering behavior was not a reliable authority for persisted BM25 retention.

### Implemented/new design

- durable adapter/export defaults to all commits reachable from the requested revision; positive `--max-count` is explicit bounded behavior only;
- generated indexing verifies historical commit retention before rendering;
- Windows runtime compatibility reopens the final BM25/vector backend after atomic rebuild finalization;
- embedding-dimension compatibility prefers the current API;
- code-entity KG enhancement is skipped for doc-only knowledge corpora with zero code entities;
- MCP client reads SDK 2 `server_info` correctly;
- `scripts/index-knowledge-windows.ps1` fails closed if the prior BM25 fallback, embedding deprecation, or doc-only KG warning classes reappear;
- persisted BM25 retention is validated directly below CLI rendering by `tests/bm25_knowledge_retention_probe.py`, which loads `bm25_index.pkl`, queries a full commit ID, resolves the returned chunk through LanceDB, and verifies the actual chunk content.

### Applying implementation/fix commits

- `8a0fce9` — harden Windows atomic rebuild and embedding API compatibility;
- `62ca6c5` — verify atomic BM25 and embedding API compatibility;
- `cc99410` — read MCP SDK 2 server metadata;
- `f60a23e` — fail closed on BM25 and embedding warning regressions;
- `e5ffa101` / `0dcb553b` / `90e69f56` — full-history retention semantics and export behavior;
- `c94d745b` / `cffaeeab` — doc-only KG search compatibility and verification;
- `cee23eb8` / `c0c8ad32` — deterministic retention/search hardening;
- `1177ffcc8c86d605429744d58166eeb4f3b33609` — direct BM25 knowledge-retention probe;
- `e76bcb32bb6244af57d9b2c0e9af3eed515454c5` — use direct BM25 retention validation below CLI rendering.

### Final Master Windows evidence

Execution at `e76bcb32bb6244af57d9b2c0e9af3eed515454c5` produced:

- `MVS_WINDOWS_MP_CONTEXT=spawn`;
- `MVS_MCP_SDK2_COMPAT=PASS`;
- `MVS_EMBEDDING_DIMENSION_API=PASS`;
- `MVS_ATOMIC_BM25_BACKEND_REOPEN=PASS`;
- `MVS_DOC_ONLY_KG_ENHANCEMENT=PASS`;
- `MVS_WINDOWS_COMPAT_VERIFY=PASS`;
- `GACE_KNOWLEDGE_WINDOWS_EXPORT=PASS RECORDS=89 MODE=FULL_HISTORY`;
- historical retention PASS for `74e8171...` and `4912a442...`;
- generated corpus: 89 records;
- full reindex: 89 files / 625 chunks / 625 embeddings;
- generated knowledge graph: 534 entities / 533 relationships;
- `MVS_BM25_INDEX=PASS`;
- direct BM25 probe `WINDOWS_KUZU_FIX`: 1 result, expected `74e8171...` record;
- direct BM25 probe `GACE_ADAPTER`: 1 result, expected `4912a442...` record;
- `MVS_BM25_WARNING_REGRESSION=PASS`;
- `MVS_EMBEDDING_FUTUREWARNING_REGRESSION=PASS`;
- `MVS_DOC_ONLY_KG_WARNING_REGRESSION=PASS`;
- `GACE_KNOWLEDGE_INDEX=PASS RECORDS=89`;
- `MCP_INITIALIZE=PASS SERVER=mcp-vector-search VERSION=0.4.0`;
- `MCP_SERVER_INFO=PASS`;
- `MCP_LIST_TOOLS=PASS COUNT=28`;
- `MCP_PROJECT_STATUS=PASS`;
- `MCP_SEARCH_KUZU=PASS COMMIT=74e8171 MODE=bm25`;
- `MCP_SEARCH_ADAPTER=PASS COMMIT=4912a442 MODE=bm25`;
- `MCP_DOC_ONLY_KG_WARNING_REGRESSION=PASS`;
- `GACE_MCP_CLIENT_E2E=PASS`;
- `GACE_MCP_WINDOWS_E2E=PASS`.

### Current decision

The measured Windows quality-hardening boundary is closed. The repository now retains full reachable Git history by default, proves persisted BM25 evidence directly, and validates real MCP retrieval independently of CLI presentation behavior. Local untracked `.gitignore` and pre-existing `scripts/__pycache__/` remain intentionally untouched.

Knowledge-data processing/admission from TGserver is a separate development scope and is not added here.

## 2026-10-05 — Explicit TGserver evidence admission and PC event outbox

Baseline difference: extend the former future TGserver integration boundary with an explicit candidate admission adapter and KB activity producer. Preserve the initial KnowledgeRecord fields, existing Git adapter/full-history corpus and MVS/MCP engine. Do not store raw logs as knowledge.

Reason: Task authorizes evidence-backed knowledge promotion and a unified Producer -> Gateway -> TGserver route. Admission requires raw correlation, actual Git identity/commit/test blobs, real exact-revision GitHub CI readback and explicit reusable knowledge fields. Producer reuses the identical TGserver stdlib outbox; no new search/MCP subsystem is built. A measured combiner gap is closed by rejecting different evidence under the same repository/commit/type key instead of silently discarding it.

Evidence: standard-library Git/admission/privacy/renderer/conflict tests and real HTTP/SQLite retry/reopen tests. PC F: runtime, actual promoted knowledge index/MCP and second-project reuse are not verified by these local tests. ZERO mapping for gace-dev-kb is absent and remains a blocker; no P number is inferred.

Applying commit: feature-branch implementation commit touching this Delta and `scripts/promote_tgserver_knowledge.py`; exact revision is retained by Git/PR.

Compatibility/rollback: existing Git export/render/MVS/MCP behavior is retained; admission/PC emission are explicit commands and can be disabled without dropping pending outbox/canonical knowledge. Generated data stay outside Git. No model download, secret registration, shared registry write, provider change, main merge or production deploy is performed.
