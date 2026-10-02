# G-ACE Dev KB — Project Tree

This file is the repository navigation map. Update it whenever files are added/removed/moved or a major responsibility changes.

## Current repository tree

```text
gace-dev-kb/
├─ README.md
├─ config/
│  └─ accepted-knowledge-sources.json
├─ docs/
│  ├─ CURRENT_DESIGN.md
│  ├─ PROJECT_TREE.md
│  ├─ DESIGN_DELTA.md
│  ├─ REUSABLE_ASSET_KB_CONTRACT.md
│  └─ MODULECATALOG_KB_INTAKE_RUNTIME.md
├─ .github/workflows/
│  └─ reusable-asset-kb-verify.yml
├─ scripts/
│  ├─ bootstrap-mvs-windows.ps1
│  ├─ patch-mvs-windows-trial-safety.ps1
│  ├─ gace_knowledge_adapter.py
│  ├─ export-knowledge-windows.ps1
│  ├─ combine_knowledge_records.py
│  ├─ render_knowledge_corpus.py
│  ├─ index-knowledge-windows.ps1
│  ├─ import_verified_modulecatalog_skills.py
│  ├─ promote-verified-skills-to-formal-kb-windows.ps1
│  ├─ test-debugai-verified-skill-kb-windows.ps1
│  ├─ test-mcp-knowledge-e2e-windows.ps1
│  ├─ test-cross-repo-reuse-windows.ps1
│  │
│  ├─ import_modulecatalog_reusable_export.py
│  ├─ import_reusable_asset_bundle.py
│  ├─ accept_modulecatalog_delivery.py
│  ├─ enrich_modulecatalog_search_corpus.py
│  ├─ copy_preserved_kb_runtime_corpus.py
│  ├─ prefix_modulecatalog_runtime_links.py
│  ├─ replace_modulecatalog_reusable_snapshot.py
│  ├─ receive-modulecatalog-kbdata-windows.ps1
│  ├─ process-modulecatalog-inbox-windows.ps1
│  ├─ activate-modulecatalog-accepted-windows.ps1
│  ├─ recover-modulecatalog-activation-windows.ps1
│  ├─ check-modulecatalog-kb-runtime-windows.ps1
│  ├─ watch-modulecatalog-kb-inbox-windows.ps1
│  ├─ configure-modulecatalog-kb-receiver-task-windows.ps1
│  │
│  ├─ run_modulecatalog_reusable_export.mjs          # producer compatibility test helper only
│  ├─ test-modulecatalog-reusable-export-windows.ps1 # isolated/contract test helper
│  └─ promote-modulecatalog-reusable-export-to-formal-kb-windows.ps1 # pre-runtime transition helper; not inbox runtime entry
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
│  ├─ mcp_cross_repo_reuse_e2e.py
│  │
│  ├─ mcp_reusable_asset_e2e.py
│  ├─ test_import_modulecatalog_reusable_export.py
│  ├─ test_import_reusable_asset_bundle.py
│  ├─ test_accept_modulecatalog_delivery.py
│  ├─ test_replace_modulecatalog_reusable_snapshot.py
│  ├─ test_enrich_modulecatalog_search_corpus.py
│  ├─ test_copy_preserved_kb_runtime_corpus.py
│  ├─ test_prefix_modulecatalog_runtime_links.py
│  ├─ test_modulecatalog_inbox_lifecycle.ps1
│  ├─ test_modulecatalog_transport_readiness.ps1
│  ├─ test_modulecatalog_receiver_timeout.ps1
│  ├─ test_modulecatalog_duplicate_delivery_archive.ps1
│  ├─ test_modulecatalog_activation_recovery.ps1
│  ├─ test_modulecatalog_runtime_health_lock.ps1
│  └─ test_modulecatalog_receiver_service.ps1
└─ .gitignore                  # local untracked evidence on Master PC; intentionally untouched
```

## Entry documents

### `README.md`
Mandatory entry point. Separates historical Master-PC validated baseline from the generalized transported-asset branch status.

### `docs/CURRENT_DESIGN.md`
Current design baseline. Defines producer/consumer authority, single-Current runtime, projection v2, transport lifecycle, activation/rollback and health boundaries.

### `docs/DESIGN_DELTA.md`
Historical design-change record. Do not rewrite older evidence merely because the current design moved forward.

### `docs/REUSABLE_ASSET_KB_CONTRACT.md`
Detailed `gace.reusable-asset.v1` consumer contract: data semantics, admission, runtime projection, Current authority and completion definition.

### `docs/MODULECATALOG_KB_INTAKE_RUNTIME.md`
Operational Windows receive-to-runtime specification: inbox lifecycle, locks, timeout/retry, receiver service, activation transaction and health commands.

## Baseline repository/history path

### `scripts/gace_knowledge_adapter.py`
Deterministic committed-Git → eight-field Knowledge Record adapter. Git remains repository-history authority.

### `scripts/export-knowledge-windows.ps1`
Writes repository-derived generated JSONL outside Git source.

### `scripts/combine_knowledge_records.py`
Combines formal record inputs while preserving distinct source identity.

### `scripts/render_knowledge_corpus.py`
Deterministic eight-field record → Markdown runtime projection.

### `scripts/index-knowledge-windows.ps1`
Formal Windows index pipeline using the existing pinned MVS runtime and real MCP retrieval gates.

### `scripts/bootstrap-mvs-windows.ps1` / `scripts/patch-mvs-windows-trial-safety.ps1`
Install/repair/verify measured MVS Windows compatibility and bounded trial/runtime execution behavior.

## Legacy verified-source path

### `config/accepted-knowledge-sources.json`
Explicit legacy accepted-source registry used by the already-validated 13-record DebugAI source path. It is not the generalized ModuleCatalog transport inbox.

### `scripts/import_verified_modulecatalog_skills.py`
Conservative importer for the previously verified 13 exported symbols.

### `scripts/promote-verified-skills-to-formal-kb-windows.ps1`
Previously validated 107-record formal promotion wrapper. Historical baseline, not the generalized transport receiver.

### `scripts/test-debugai-verified-skill-kb-windows.ps1` / `tests/mcp_verified_skill_trial_e2e.py`
Isolated real-Windows reusable retrieval proof for the legacy 13-record source.

## Generalized ModuleCatalog reusable-asset receive path

### `scripts/import_modulecatalog_reusable_export.py`
Authoritative `gace.reusable-asset.v1` consumer/importer. Re-verifies manifests/hashes/schema/provenance/cardinality/relations and builds rich Knowledge Unit metadata + compatibility records + Markdown corpus.

### `scripts/import_reusable_asset_bundle.py`
Generic reusable-asset bundle compatibility importer used by contract/regression coverage.

### `scripts/accept_modulecatalog_delivery.py`
KB admission boundary for an already-transported delivery. Produces projection schema v2 and an ACCEPTED receipt/state only after full validation. Replays are revalidated instead of trusting cached authority.

### `scripts/enrich_modulecatalog_search_corpus.py`
Adds runtime-only MVS frontmatter/tags/related links to the local derived corpus. Canonical transported files remain unchanged.

### `scripts/copy_preserved_kb_runtime_corpus.py`
Copies the existing non-Catalog runtime corpus into staging without degrading rich existing Markdown content.

### `scripts/prefix_modulecatalog_runtime_links.py`
Rewrites runtime-only `related:` link targets after Catalog filename prefixing so MVS KG links resolve in the staged/current corpus.

### `scripts/replace_modulecatalog_reusable_snapshot.py`
Builds the next formal record set while keeping one Current ModuleCatalog reusable snapshot and preserving non-Catalog knowledge.

### `scripts/receive-modulecatalog-kbdata-windows.ps1`
One-delivery receive orchestrator. Owns `receive.lock`, recovery-before-activation, stale replay rejection, idempotent ACTIVE deep health, activation and final Current health.

### `scripts/process-modulecatalog-inbox-windows.ps1`
Standard inbox processor. Owns transport-completeness preflight, `ready → processing`, resume/retry/failure/processed archive lifecycle, bounded receiver timeout, Windows process-tree termination, duplicate delivery replay archive preservation and processor serialization.

### `scripts/activate-modulecatalog-accepted-windows.ps1`
Uses the existing BM25/Vector/KG/MCP runtime to build staging, run regressions, replace Current atomically, preserve structured relationship/case authority and perform post-cutover MCP verification.

### `scripts/recover-modulecatalog-activation-windows.ps1`
Resolves an interrupted PREPARED activation transaction before another activation proceeds.

### `scripts/check-modulecatalog-kb-runtime-windows.ps1`
Non-mutating Current integrity/health gate. `-Deep` reruns repository-history and reusable BM25/Vector/Hybrid/KG MCP checks.

### `scripts/watch-modulecatalog-kb-inbox-windows.ps1`
Continuous singleton inbox consumer with heartbeat/failure JSONL and bounded log rotation.

### `scripts/configure-modulecatalog-kb-receiver-task-windows.ps1`
Windows scheduled-task installer source. Registers a current-user Limited AtLogOn receiver with bounded restart behavior. Repository presence does not mean the Master-PC task is installed.

## Producer compatibility helpers — not operational receive path

### `scripts/run_modulecatalog_reusable_export.mjs`
Invokes the ModuleCatalog producer for CI/compatibility testing at an exact commit. Operational KB receipt does not call this helper.

### `scripts/test-modulecatalog-reusable-export-windows.ps1`
Earlier isolated Windows producer/consumer trial helper. Not the unattended inbox entry.

### `scripts/promote-modulecatalog-reusable-export-to-formal-kb-windows.ps1`
Transition-era promotion helper retained for regression/history. The current design's operational entry is transported delivery → receive/inbox lifecycle.

## Generalized receive/runtime tests

### `tests/mcp_reusable_asset_e2e.py`
Real MCP gate for reusable data: exact BM25 all units; representative natural BM25/Vector/Hybrid; case/relationship search; KG tag/relation/dependency/links checks.

### `tests/test_accept_modulecatalog_delivery.py`
Admission, idempotency, tamper/replay and projection-v2 contract tests.

### `tests/test_modulecatalog_inbox_lifecycle.ps1`
Claim/resume/failure/retry/archive lifecycle and lock behavior.

### `tests/test_modulecatalog_transport_readiness.ps1`
Proves partially copied deliveries stay pending and do not create false multi-ready ambiguity.

### `tests/test_modulecatalog_receiver_timeout.ps1`
Proves bounded receiver timeout remains retryable and can resume successfully.

### `tests/test_modulecatalog_duplicate_delivery_archive.ps1`
Proves duplicate delivery ID replay preserves the original processed archive.

### `tests/test_modulecatalog_activation_recovery.ps1`
Hard-interruption PREPARED transaction recovery tests.

### `tests/test_modulecatalog_runtime_health_lock.ps1`
Verifies runtime health/receive lock ownership and internal inherited-lock mode.

### `tests/test_modulecatalog_receiver_service.ps1`
Continuous receiver one-shot/singleton/log-rotation behavior.

### Search projection tests

- `tests/test_enrich_modulecatalog_search_corpus.py` — frontmatter, relation/dependency projection.
- `tests/test_copy_preserved_kb_runtime_corpus.py` — non-Catalog rich-corpus preservation.
- `tests/test_prefix_modulecatalog_runtime_links.py` — runtime link target alignment.
- `tests/test_replace_modulecatalog_reusable_snapshot.py` — single-Current record replacement and legacy transition.
- `tests/test_import_modulecatalog_reusable_export.py` / `tests/test_import_reusable_asset_bundle.py` — actual/generic contract import gates.

## Workflow

### `.github/workflows/reusable-asset-kb-verify.yml`
Feature-branch CI. Covers syntax, transport/inbox reliability, activation recovery, receiver service, projection/search regressions, legacy KB regressions and a pinned real ModuleCatalog producer compatibility contract.

CI is not a substitute for the final genuine-transport Master-PC MVS runtime gate.

## Local runtime / generated-data boundary

```text
F:\G-ACE-KB\
├─ repo\
├─ data\
│  ├─ knowledge-records\
│  ├─ knowledge-search\
│  ├─ knowledge-sources\accepted\
│  ├─ knowledge-inbox\modulecatalog\
│  └─ knowledge-intake\modulecatalog\
├─ runtime\mcp-vector-search\
├─ assets\
└─ .venv\
```

Generated data, inbox/archive state, indexes, runtime downloads and local environments stay outside Git source.

Do not create placeholder subsystems merely to make the tree look complete.
