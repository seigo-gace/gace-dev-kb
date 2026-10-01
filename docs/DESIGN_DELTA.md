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

**Status:** SOURCE IMPLEMENTED; MASTER WINDOWS CORPUS/INDEX/SEARCH VALIDATION PENDING.

### Implemented/new design

The initial JSONL contract remains the canonical generated record shape. A deterministic projection converts those records into Markdown solely as an OSS search input format, without changing or inventing knowledge fields.

Generated runtime boundary:

```text
F:\G-ACE-KB\data\
├─ knowledge-records\
│  └─ gace-dev-kb.jsonl
└─ knowledge-search\
   ├─ records\                 # one generated Markdown document per record
   └─ .mcp-vector-search\      # dedicated generated search config/index
```

The pipeline:

1. reruns the deterministic Git knowledge export;
2. renders one Markdown file per record;
3. initializes or reuses a dedicated `mcp-vector-search` project outside Git source;
4. force-indexes the generated corpus;
5. verifies indexed-file count equals exported record count;
6. searches for the known Kuzu Windows compatibility record (`74e8171...`);
7. searches for the known G-ACE adapter record (`4912a442...`).

### Applying implementation commits

- `8342c868a62be6dacc7922d526d6d40f59a99619` — deterministic JSONL → Markdown corpus renderer;
- `61cc0f903171f93412be0828c0dadc196424e260` — Windows generated knowledge indexing/retrieval wrapper;
- `1172ae12eccb1b159588940b621c93ffd5fd5b4d` — renderer contract tests;
- `3cdf008054f333e0fa56e82b0b6442457f9f14af` — prevent future adapter-test bytecode cache creation.

### Validation boundary

Source existence is not runtime PASS. The renderer tests, real generated corpus, dedicated MVS index, exact indexed-record count, and the two semantic retrieval gates must pass on the Master Windows environment before this pipeline is declared validated.
