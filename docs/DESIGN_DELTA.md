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

**Status:** candidate selection updated; installation not yet validated.

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

Return `mcp-vector-search` to the first implementation candidate because its documented recommended installation is via PyPI (`pip install mcp-vector-search`), it provides MCP integration and semantic repository/code search, and it can use the already-present Python runtime.

### Important boundary

This is a candidate-selection decision only. `mcp-vector-search` is not considered adopted, installed, or validated until the Windows real-environment install/doctor/index/search checks pass.

### Applying commit

This document update records the decision; the commit containing this entry is the applying documentation commit.
