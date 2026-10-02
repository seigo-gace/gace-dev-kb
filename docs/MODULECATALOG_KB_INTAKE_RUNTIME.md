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
├─ processing\
├─ processed\
└─ failed\
```

The transport side should build a complete delivery outside `ready` and atomically move/rename it into `ready` when possible.

The KB nevertheless performs a transport-completeness preflight before claiming a directory. It requires the top-level manifest, declared Asset directories/manifests, every listed bundle file, and at least the declared byte size. A file that is still shorter than its manifest declaration remains `PENDING`; it is not moved to `processing` and is not falsely classified as a failed KB admission.

The preflight never follows rooted or `..` manifest paths outside an Asset directory. It is deliberately **not** the integrity authority: malformed/oversized/corrupt payloads are claimable so the full admission gate can reject and archive them deterministically using exact size/hash/schema/provenance checks.

The active KB is a single-current-snapshot runtime. Until the producer supplies explicit monotonic ordering/predecessor authority, more than one complete ready delivery is rejected with `MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY`. Directory names, filesystem timestamps and Git commit time are never used to guess which snapshot is newer.

## Claim, retry and archive lifecycle

```text
ready
→ processing
→ ACTIVE
→ processed
```

A single stranded `processing` delivery is resumed before any new ready delivery. More than one stranded processing delivery fails closed.

Failure classes are intentionally separated:

```text
permanent admission / activation failure → failed\<unique-name>\
transient receiver busy / health / timeout → processing + kb-retryable.json
runtime ACTIVE but archive move failed      → processing + kb-archive-pending.json
```

Every receiver attempt stores its stdout/stderr inside the claimed delivery. Successful processed archives also contain `kb-active-receipt.json`; permanent failures contain machine-readable `kb-failure.json` pointing to the attempt logs.

A repeated transport may reuse the same delivery ID. Existing processed evidence is never overwritten: a successful replay is archived under a unique `-replay-<timestamp>-<id>` directory while Current/idempotency rules remain enforced by the receiver.

## Receive and health serialization

Three locks protect different boundaries:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receiver-service.lock
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\processor.lock
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receive.lock
```

`receiver-service.lock` prevents two watchers. `processor.lock` serializes claim/archive lifecycle. `receive.lock` serializes admission/index/cutover and Current runtime health inspection.

The health checker may use `-AssumeReceiveLockHeld` only when invoked internally by the receiver that already owns `receive.lock`; this avoids self-deadlock without weakening external serialization.

## Receiver timeout and process-tree recovery

`process-modulecatalog-inbox-windows.ps1` bounds one receiver attempt with `ReceiverTimeoutSeconds` (default 7200 seconds).

Timeout is `RETRYABLE`, not a permanent failure. The claimed delivery remains in `processing` for the next run.

On Windows, timeout terminates the receiver process tree with `taskkill.exe /T /F`, because a receiver may own Python/MVS descendants. Killing only the PowerShell wrapper could otherwise leave an orphan indexer mutating the runtime while the next retry begins. Non-Windows test environments use the normal forced process termination fallback.

## Continuous Windows receiver

`watch-modulecatalog-kb-inbox-windows.ps1` is the continuous KB-side consumer. It invokes the inbox processor synchronously, so one BM25/Vector/KG activation must finish before another delivery is considered.

Service events are written to:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receiver-service.jsonl
```

Idle PASS logging is heartbeat-throttled and the JSONL is bounded by rotation.

One-shot verification:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\watch-modulecatalog-kb-inbox-windows.ps1 `
  -Once
```

## Windows scheduled receiver task

`configure-modulecatalog-kb-receiver-task-windows.ps1` can register the receiver as the current user, Limited, AtLogOn task:

```text
\G-ACE-KB-ModuleCatalogReceiver
```

The installer verifies persisted executable, arguments, working directory and principal, starts the task and requires it to remain Running.

It also configures bounded restart behavior for transient startup failure, defaulting to 12 restart attempts at a 1-minute interval. This covers cases such as delayed availability of the F: runtime at logon without creating an infinite restart loop.

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

Repository implementation does not install this task. Installation remains an explicit Master-PC environment action after the real runtime gate.

## Receipts and Current authority

Per-commit receipts:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receipts\<catalog-commit>.json
```

States:

```text
ACCEPTED = transport payload passed admission and local derived projection exists
ACTIVE   = indexing + MCP + post-cutover Current verification passed
```

Current authority:

```text
F:\G-ACE-KB\data\knowledge-records\modulecatalog-reusable-active.json
```

The current reusable snapshot also contains `runtime-state.json`. ACTIVE receipt, activation marker and runtime-state must agree on Catalog commit and runtime hashes. An old ACTIVE receipt alone is never accepted as Current authority.

A replay of the Current ACTIVE commit revalidates the transported payload and then reruns deep runtime health before returning idempotent success.

## Accepted projection and existing KB features

The eight-field Knowledge Record remains only a compatibility envelope. Projection schema v2 preserves:

```text
knowledge-records.jsonl
knowledge-metadata.jsonl
relationships.jsonl
cases.jsonl
records/*.md
```

`relationships.jsonl` and `cases.jsonl` remain structured sidecars with independent SHA-256 and cardinality verification through acceptance, activation and health checks.

Runtime-only derived frontmatter exposes stable reusable-asset metadata and graph semantics without modifying transported canonical files. Tags include:

```text
gace-reusable-asset
asset-<asset-id>
knowledge-kind-<kind>
lifecycle-<status>
verification-<status>
relation-<relation-type>
depends-on-<asset-id>
```

Resolvable producer relationships/dependencies also create deterministic `related:` document links. Activation prefixes ModuleCatalog runtime filenames and rewrites these related targets to the same prefix before indexing.

The existing `mcp-vector-search 4.1.14` runtime remains the only search/graph runtime:

```text
BM25
Vector
Hybrid
Knowledge Graph
MCP
```

## Runtime search/use gates

Activation requires:

```text
all Knowledge Units exact BM25 retrieval by stable ID
representative of every Knowledge Kind via BM25 / Vector / Hybrid natural retrieval
representative Case ID retrieval
representative Relationship ID retrieval
KG reusable-data tag query
KG relation-type query when relationship semantics exist
KG dependency query when producer dependencies exist
KG LINKS_TO presence when resolvable producer relations exist
existing repository-history MCP regression
existing accepted-asset regression when present
post-cutover rerun against the actual Current runtime path
```

No producer relationship or dependency is invented when absent.

## Operational pipeline

```text
transported delivery
→ ready
→ transport-completeness preflight
→ processing claim
→ full admission / integrity verification
→ projection schema v2
→ relationship/case sidecars retained
→ runtime-only search/KG enrichment
→ ACCEPTED receipt
→ preserve non-Catalog Current corpus
→ replace prior ModuleCatalog reusable snapshot candidate
→ existing BM25 / Vector / KG staging index
→ existing-history MCP regression
→ reusable BM25 / Vector / Hybrid / KG gates
→ durable PREPARED activation journal
→ backup-backed Current cutover
→ post-cutover MCP from actual Current path
→ matching ACTIVE runtime-state / marker / receipt
→ clear journal
→ processed archive with ACTIVE receipt + receiver logs
→ ongoing health
```

## Cutover crash recovery

Before destructive cutover, activation writes:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\activation-transaction.json
```

The PREPARED journal records every current/backup/staging path required for recovery.

`recover-modulecatalog-activation-windows.ps1` runs automatically before a new activation:

- if ACTIVE marker + receipt + runtime-state already agree on the target commit, the previous activation had committed and recovery finalizes it;
- otherwise the prior fully-known Current search/formal/reusable/authority state is restored;
- missing required recovery evidence fails closed.

The journal is removed only after successful finalization or completed rollback.

## Data retention

Normal search contains one Current ModuleCatalog reusable snapshot, not every historic Catalog snapshot. Existing repository-history Knowledge and non-ModuleCatalog accepted data are preserved.

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

Processed/failed delivery archives are operational evidence and are not automatically deleted by the receiver. No retention deletion policy is implied by this branch.

## Runtime health verification

`check-modulecatalog-kb-runtime-windows.ps1` verifies:

```text
ACTIVE marker / receipt / runtime-state agreement
formal KB hash
reusable records/metadata hashes
relationship/case hashes + counts
delivery manifest hash
Current corpus counts and runtime tags
MVS indexed-file cardinality
absence of known degraded vector-only/BM25 warnings
```

`-Deep` reruns repository-history plus reusable MCP BM25/Vector/Hybrid/KG gates.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\check-modulecatalog-kb-runtime-windows.ps1 `
  -Deep
```

## Manual commands

Process one already-transported bundle:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\receive-modulecatalog-kbdata-windows.ps1 `
  -DeliveryRoot '<transported-delivery-directory>'
```

Process/resume the standard inbox:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\process-modulecatalog-inbox-windows.ps1
```

Manual activation-journal recovery is available, although normal receive invokes it automatically:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\recover-modulecatalog-activation-windows.ps1
```

## Completion definition

A transported Catalog payload is not operational merely because it was copied or ACCEPTED.

Completion requires:

```text
transport completeness proved before claim
full cryptographic/semantic admission PASS
projection schema v2 complete
structured relationship/case hashes + counts intact
existing BM25 / Vector / Hybrid gates PASS
existing Knowledge Graph gates PASS where applicable
post-cutover MCP PASS on actual Current path
ACTIVE receipt + Current marker + runtime-state agree
processed archive contains ACTIVE receipt + receiver diagnostics
no unresolved activation transaction journal
runtime health PASS
no timed-out/orphan receiver process remains active
```

The remaining environment-specific proof is the real Master-PC MVS runtime after ModuleCatalog genuinely transports a delivery. GitHub contract tests do not substitute for that Windows runtime proof.
