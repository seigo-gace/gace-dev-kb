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

**Status:** INSTALL + CLI + DOCTOR PASS; index/search/MCP E2E still pending.

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

This patch currently lives in the local installed OSS runtime, not in the G-ACE repository source and not upstream. Reinstallation/upgrading the package can overwrite it; reproducibility must be addressed before this runtime is treated as durable production infrastructure.

### Validation after patch

- `mcp-vector-search --help`: PASS
- `mcp-vector-search doctor`: PASS
- doctor result: all checked dependencies available

### Current decision

Continue with `mcp-vector-search` as the active OSS-core candidate. Do not add another OSS core while this candidate is passing the current gates.

### Remaining gates before adoption is complete

1. initialize/index the real `F:\G-ACE-KB\repo` repository;
2. prove retrieval against known README/design content;
3. prove index data remains outside Git source as designed;
4. prove MCP server operation usable by an AI client;
5. make the Windows compatibility handling reproducible rather than relying on an undocumented manual site-packages edit;
6. update README/Project Tree/system documentation according to the Documentation Gate after those capabilities are actually validated.

### Applying commit

This documentation commit records the measured Windows installation/compatibility result. It does not claim the remaining index/search/MCP gates have passed.
