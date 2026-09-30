# G-ACE Development Knowledge Base

G-ACE Dev KB is a repository-centered development knowledge base for reusing implementation knowledge across projects.

## Purpose

Capture and reuse development knowledge derived from repository work, including:

- reusable implementation assets
- design and decision rationale
- successful outcomes
- failures and failure reasons
- root causes
- fixes
- tests and validation results
- commit/evidence references

## Current architecture baseline

The target architecture is:

```text
Repository development routine
        ↓
G-ACE Knowledge Adapter
        ↓
Stratum core
        ↓
local knowledge / code index / search / MCP
        ↓
ChatGPT / Codex / DebugAI / other AI consumers
```

The implementation rule is to keep this as small as possible:

- one OSS core first
- reuse existing OSS capabilities instead of rebuilding them
- add only G-ACE-specific metadata / ingestion logic that the OSS does not provide
- add another component only after a real measured gap is confirmed

## Repository workflow integration

The KB is downstream of the repository development loop:

```text
README
→ Design / Project Tree / Design Delta
→ implementation
→ test / debug / validation
→ commit
→ documentation gate
→ completion gate
→ KB ingestion
```

Repository files and Git history remain the primary development evidence. The KB is the reuse/search layer, not a replacement source of truth.

## Planned knowledge fields

Initial G-ACE-specific fields are intentionally minimal:

- `type`
- `repository`
- `commit`
- `summary`
- `cause`
- `fix`
- `validation`
- `source`

Types will cover at least reusable implementation, design/decision, failure/root-cause/fix, and validation knowledge without creating separate subsystems for each.

## Local target

Primary local data location:

```text
F:\G-ACE-KB
```

The Git repository contains source, configuration, design and tests. Large local indexes / runtime data should remain outside Git unless explicitly required.

## Status

Current status: **bootstrap / design baseline only**.

Stratum has been selected as the first OSS core candidate. It still requires Windows real-environment validation before being treated as the final core.
