# G-ACE Development Knowledge Base

G-ACE Dev KB is the repository-centered knowledge base for reusing development knowledge across G-ACE projects.

> **Development starts here.** Before changing source, read the linked Current Design and Project Tree. Check Design Delta when the work touches an existing design decision. Do not treat future design as current implementation.

## Development entry points

- [Current Design](docs/CURRENT_DESIGN.md) — current design baseline, responsibilities, boundaries, and repository workflow.
- [Project Tree](docs/PROJECT_TREE.md) — current repository navigation and file/directory responsibilities.
- [Design Delta](docs/DESIGN_DELTA.md) — intentional differences from the baseline, why they changed, evidence, and applying commits.

## Mandatory repository routine

```text
README
→ Current Design / Project Tree / relevant Design Delta
→ implementation
→ test / debug / validation
→ commit = work/change record
→ documentation gate
→ completion gate
→ KB ingestion
```

Before declaring work complete, explicitly determine whether the change requires updates to:

- README
- Project Tree
- Design Delta
- a system/feature document

If an update is required but missing, the work is not complete.

### Design rule

Design is a baseline. Do **not** silently rewrite design merely because implementation differs. When an intentional implementation change differs from the baseline, record the difference, reason, evidence, and applying commit in Design Delta. Reflect completed and validated capability in README.

## Purpose

Capture and reuse repository-derived development knowledge, including:

- reusable implementation assets
- design and decision rationale
- successful outcomes
- failures and failure reasons
- root causes
- fixes
- tests and validation results
- commit/evidence references

The repository and Git history remain the primary development evidence. The KB is the reuse/search layer, not a replacement source of truth.

## Minimal implementation strategy

Build the shortest useful system:

1. use one suitable OSS core first;
2. reuse OSS functionality instead of rebuilding generic KB/search/MCP capability;
3. migrate only valuable G-ACE-specific parts from the former KB System;
4. add only the missing repository/knowledge adapter logic;
5. add another component only after a measured gap is confirmed.

`mcp-vector-search` 4.1.14 is the active OSS core. Windows real-environment validation has passed for installation, dependency health, repository indexing, embeddings, knowledge-graph build, and semantic retrieval. MCP client E2E and durable/reproducible Windows compatibility handling remain incomplete.

## Initial knowledge contract

Keep the first record shape small:

- `type`
- `repository`
- `commit`
- `summary`
- `cause`
- `fix`
- `validation`
- `source`

This must support at least reusable implementation, design/decision, failure/root-cause/fix, and validation knowledge without creating a separate subsystem for every type.

## Local layout

Primary local root:

```text
F:\G-ACE-KB
├─ repo\       # this repository
├─ data\       # local KB/index data
├─ runtime\    # OSS runtime
├─ assets\     # migration/input assets
└─ .venv\      # local environment from preparation
```

Only source, configuration, design, tests, and durable documentation belong in Git by default. Runtime downloads, generated indexes/data, caches, secrets, and local environments stay outside the repository unless a later design decision explicitly changes that boundary.

## Windows bootstrap

- `scripts/bootstrap-mvs-windows.ps1` installs the pinned OSS runtime and applies the two measured Windows/docs compatibility fixes.
- `tests/verify-mvs-windows.ps1` verifies the installed compatibility state and CLI startup.

## Current status

**OSS SEARCH CORE VALIDATED / G-ACE ADAPTER NOT YET IMPLEMENTED**

Completed:

- repository created;
- README established as the development entry point;
- Current Design established;
- Project Tree established;
- Design Delta established;
- local repository cloned under `F:\G-ACE-KB\repo`;
- `mcp-vector-search` 4.1.14 installed in the isolated local runtime;
- Windows CLI/doctor validation passed after local compatibility handling;
- real repository indexing passed: 4 files / 119 chunks / 119 embeddings;
- knowledge graph build passed: 44 entities / 43 relationships;
- semantic retrieval passed against known design and failure/root-cause/fix/validation content.

Implemented on the active feature branch, pending Windows real-runtime verification:

- repository-managed Windows bootstrap/compatibility scripts for `mcp-vector-search` 4.1.14.

Not yet completed:

- Windows real-runtime verification of the repository-managed bootstrap;
- MCP server → AI client E2E validation;
- G-ACE knowledge adapter implementation;
- repository-to-KB ingestion;
- end-to-end knowledge retrieval/reuse validation.

Do not report those incomplete items as implemented or validated.
