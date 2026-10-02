# ModuleCatalog KBData receive-to-runtime boundary

## Responsibility boundary

ModuleCatalog owns reusable-asset creation, verification, search-ready KBData generation and transport.
G-ACE KB starts at **receipt of a transported `gace.reusable-asset.v1` delivery**.
The operational KB path must not clone/fetch ModuleCatalog or regenerate producer canonical data.

KB-side runtime adaptation is allowed only as a derived projection required by the existing KB runtime. Canonical transported files remain unchanged.

## Inbox contract

Default Windows inbox:

```text
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\
├─ ready\<delivery-id>\
│  ├─ manifest.json
│  └─ assets\...
├─ processing\
├─ processed\
└─ failed\
```

A directory without `manifest.json` is incomplete/pending and is not consumed. The transport side should finish a delivery outside `ready`, then atomically move/rename the complete directory into `ready`.

The active KB is a **single-current-snapshot** runtime. Until the producer manifest carries explicit monotonic ordering / predecessor authority, more than one complete ready delivery is rejected with `MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY`. Directory names, filesystem time, or Git commit time are never used to guess which Catalog snapshot is newer.

Before processing, the KB claims one complete delivery by moving it from `ready` to `processing`. Success moves it to `processed`; failure moves it to `failed` with a timestamp suffix. Successful archives contain `kb-active-receipt.json`. Every receiver attempt also keeps its own `kb-receiver-<attempt>.stdout.log` / `kb-receiver-<attempt>.stderr.log`, so Task Scheduler or background execution never becomes the only place where activation diagnostics existed. Failed archives additionally contain machine-readable `kb-failure.json` pointing to those logs.

If a prior process/PC interruption left exactly one delivery under `processing`, the next inbox run resumes that claimed delivery before considering new ready data. More than one stranded processing delivery fails closed and requires explicit recovery.

The transport side may use another delivery directory only when it explicitly invokes the receiver with `-DeliveryRoot`.

## Receive and health serialization

Three levels of serialization protect the receive service and current KB state:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receiver-service.lock
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\processor.lock
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receive.lock
```

`receiver-service.lock` prevents two long-running inbox watchers from running concurrently, including a manual watcher accidentally started while the scheduled receiver is already running. `processor.lock` serializes inbox claim/archive lifecycle. `receive.lock` serializes admission/index/cutover **and current-runtime health inspection**. A deep/shallow health check therefore cannot race a current snapshot replacement.

## Continuous Windows receiver

`watch-modulecatalog-kb-inbox-windows.ps1` is the continuous KB-side consumer. It invokes the inbox processor synchronously, so one potentially long BM25/Vector/KG activation must finish before another delivery can be considered. It uses an exclusive service lock and therefore fails closed with `MODULECATALOG_RECEIVER_SERVICE_BUSY` when another watcher already owns the receive loop.

Service events are written to:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receiver-service.jsonl
```

Successful idle polling is heartbeat-throttled (default 300 seconds rather than every 10-second poll). The service log is bounded by rotation (default 5 MiB per file, five rotated files) so unattended operation does not grow one JSONL forever.

One-shot service verification:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\watch-modulecatalog-kb-inbox-windows.ps1 `
  -Once
```

For unattended startup, `configure-modulecatalog-kb-receiver-task-windows.ps1` registers a current-user, Limited, AtLogOn task in the root Task Scheduler folder:

```text
\G-ACE-KB-ModuleCatalogReceiver
```

The installer avoids relying on a pre-created custom scheduler folder, verifies the persisted executable/arguments/working directory/principal after registration, starts the task, and requires it to remain `Running` rather than accepting an immediately-dead `Ready` task as success.

Install/start:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\configure-modulecatalog-kb-receiver-task-windows.ps1
```

Uninstall/stop:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\configure-modulecatalog-kb-receiver-task-windows.ps1 `
  -Uninstall
```

The scheduled task is code/configuration in this branch only until the Master-PC real-runtime gate explicitly installs it; repository changes do not create the PC task by themselves.

## Receipts and current authority

Per-commit receipts are stored at:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receipts\<catalog-commit>.json
```

States:

```text
ACCEPTED = transport payload passed admission and the local derived projection exists.
ACTIVE   = existing KB indexing + MCP + post-cutover verification passed and this is current.
```

Current authority is:

```text
F:\G-ACE-KB\data\knowledge-records\modulecatalog-reusable-active.json
```

The current reusable snapshot also contains `runtime-state.json`. ACTIVE receipt, activation marker and runtime-state must agree on the same Catalog commit and runtime hashes. An old ACTIVE receipt alone is never accepted as current authority, preventing replay of a previously-active commit from silently rolling the KB backward.

## Accepted projection and existing KB features

The eight-field Knowledge Record remains only the legacy compatibility envelope. The accepted projection schema is currently `projectionSchemaVersion=2` and preserves:

```text
knowledge-records.jsonl
knowledge-metadata.jsonl
relationships.jsonl
cases.jsonl
records/*.md
```

`relationships.jsonl` and `cases.jsonl` are retained as structured sidecars with independent SHA-256 + cardinality verification through acceptance, activation and runtime health checks. They are not discarded after the Markdown search projection is built.

At acceptance time, the KB adds **runtime-only derived frontmatter** to its local Markdown projection. The transported/canonical ModuleCatalog bundle is not modified. Frontmatter exposes stable reusable-asset / parent-asset / knowledge-kind / lifecycle / verification metadata plus relationship/dependency semantics needed by the existing MVS Knowledge Graph.

Runtime tags currently include:

```text
gace-reusable-asset
asset-<asset-id>
knowledge-kind-<kind>
lifecycle-<status>
verification-<status>
relation-<relation-type>
depends-on-<asset-id>
```

Resolvable relationships/dependencies also produce deterministic `related:` document links. Explicit producer `asset contains knowledge-unit` relationships are projected from the Asset discovery document to the explicitly-contained unit documents, so the current Catalog containment graph is not reduced to archival JSON. Other cross-unit/cross-asset relationships and dependencies produce links only when their targets resolve; absent producer relationships are never invented.

Activation prefixes ModuleCatalog runtime filenames to isolate them from the pre-existing KB corpus, so the receiver rewrites `related:` targets to the same prefix before indexing. This keeps existing MVS graph links aligned with the actual runtime filenames.

This uses the already-installed `mcp-vector-search 4.1.14` runtime through:

```text
BM25
Vector semantic search
Hybrid search
Knowledge Graph
MCP
```

No second search engine or second graph database is introduced for ModuleCatalog data.

## Runtime search/use gates

The runtime gate proves more than file ingestion:

```text
all Knowledge Units exact BM25 retrieval by stable ID
representative of every Knowledge Kind through BM25 / Vector / Hybrid natural retrieval
representative Case ID retrieval
representative Relationship ID retrieval
KG base reusable-data tag query
KG relation-type tag query when relationship semantics exist
KG dependency tag query when Catalog dependencies exist
KG LINKS_TO relationship presence when resolvable producer relationships exist
existing repository-history MCP regression
existing accepted-asset MCP regression when present
post-cutover rerun against the actual current runtime path
```

The current producer contract has no Catalog dependencies among the 80 regression Assets, so dependency KG lookup is fail-safe skipped for that dataset. Relation semantics are still present through the canonical `contains` relationships and are projected/queryable without inventing new producer facts.

## Operational pipeline

```text
transported delivery
→ ready
→ continuous receiver / one-shot processor
→ atomic claim into processing
→ acceptance / integrity verification
→ projection schema v2
→ structured relationships/cases retained
→ runtime-only search/KG enrichment
→ runtime related-link filename alignment
→ ACCEPTED receipt
→ active-snapshot replacement candidate
→ staging search corpus
→ existing BM25 / Vector / Knowledge Graph index
→ repository-history MCP regression
→ existing accepted-asset MCP regression
→ reusable exact/natural/case/relationship/KG gates
→ durable activation transaction journal
→ backup-backed current cutover
→ post-cutover MCP verification from the actual current path
→ atomic ACTIVE marker / receipt / runtime-state
→ clear transaction journal
→ archive delivery under processed with receiver stdout/stderr + ACTIVE receipt
```

## Cutover crash recovery

In-process exceptions roll back formal records, search runtime, reusable snapshot, activation marker and receipt. Hard process/PC termination is handled separately with:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\activation-transaction.json
```

Before destructive cutover, `activate-modulecatalog-accepted-windows.ps1` writes a durable `PREPARED` transaction journal containing the target commit and every current/backup/staging path required for recovery.

`recover-modulecatalog-activation-windows.ps1` is run automatically before a new activation starts:

- if ACTIVE marker + receipt + runtime-state all agree on the target commit, the prior activation had already committed and recovery finalizes it without rolling back a healthy current runtime;
- otherwise the last fully-known current search/formal/reusable/authority state is restored from journaled backups;
- unrecoverable/missing required backups fail closed rather than guessing.

The journal is removed only after a successful commit/finalization or completed rollback.

## Data retention

The active runtime keeps one current ModuleCatalog reusable snapshot rather than accumulating old Catalog commits in the active search index. Repository-history Knowledge and non-ModuleCatalog accepted source types are preserved.

Current reusable snapshot:

```text
knowledge-records.jsonl
knowledge-metadata.jsonl
relationships.jsonl
cases.jsonl
records/*.md
delivery-manifest.json
acceptance-state.json
runtime-state.json
```

Search/use therefore remains traceable to parent Asset, exact Catalog commit, source paths, relationship/case data, verification, lifecycle, integrity and derivation boundary.

## Runtime health verification

`check-modulecatalog-kb-runtime-windows.ps1` is non-mutating but acquires the same receive lock as activation. It cross-checks activation marker, ACTIVE receipt and current `runtime-state.json`; verifies formal/reusable/delivery/relationship/case hashes and cardinalities; confirms runtime frontmatter; and confirms MVS indexed-file cardinality without degraded vector-only warnings.

`-Deep` additionally reruns repository-history MCP plus the full reusable MCP gate, including BM25 / Vector / Hybrid and Knowledge Graph checks.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\check-modulecatalog-kb-runtime-windows.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\check-modulecatalog-kb-runtime-windows.ps1 `
  -Deep
```

## Commands

Process one already-transported bundle through the full KB runtime:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\receive-modulecatalog-kbdata-windows.ps1 `
  -DeliveryRoot '<transported-delivery-directory>'
```

Process/resume the single current delivery in the standard inbox:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\process-modulecatalog-inbox-windows.ps1
```

Manual activation-journal recovery is also available, although normal activation invokes it automatically:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\recover-modulecatalog-activation-windows.ps1
```

## Completion definition

A transported Catalog payload is not operational merely because it was copied or ACCEPTED.

Completion requires all of the following:

```text
ACTIVE receipt
matching current activation marker
matching runtime-state
structured relationship/case hashes + counts intact
existing BM25 / Vector / Hybrid retrieval gates PASS
existing Knowledge Graph reusable/relation/dependency/containment gates PASS where applicable
post-cutover MCP PASS on the actual current path
delivery archived under processed with receiver diagnostic logs
no unresolved activation transaction journal
runtime health PASS
```

For unattended operation, the Master-PC receiver task must additionally prove its persisted action/principal and remain Running after start. The remaining environment-specific gate is the real Master-PC installed MVS runtime after ModuleCatalog genuinely transports a delivery. GitHub contract tests do not substitute for that Windows runtime proof.
