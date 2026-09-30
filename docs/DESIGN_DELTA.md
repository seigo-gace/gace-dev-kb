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

**Status:** baseline established; no implementation delta yet.

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
