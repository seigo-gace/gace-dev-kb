# ModuleCatalog KBData receive-to-runtime boundary

## 1. Responsibility boundary

ModuleCatalog owns reusable-asset creation, verification, search-ready KBData generation and transport.

G-ACE KB starts at **receipt of a transported `gace.reusable-asset.v1` delivery**.

The operational KB path must not clone/fetch ModuleCatalog or regenerate producer canonical data. KB-side adaptation is allowed only as a derived projection required by the existing G-ACE KB runtime; transported canonical files remain unchanged.

```text
ModuleCatalog
create / verify / shape KBData / transport
        ↓
──────────── responsibility boundary ────────────
        ↓
G-ACE KB
receipt / admission / projection
        ↓
existing BM25 / Vector / Hybrid / KG / MCP
        ↓
Current activation / health / retention
```

## 2. Inbox contract

Default Windows inbox:

```text
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\
├─ ready\<delivery-id>\
├─ processing\
├─ processed\
└─ failed\
```

The transport side should construct a complete delivery outside `ready` and atomically move/rename it into `ready` when possible.

The KB nevertheless performs a transport-completeness preflight before claiming a directory. It requires the top-level manifest, declared Asset directories/manifests, every listed bundle file, and at least each declared byte size.

A file still shorter than its declaration remains `PENDING`; it is not moved to `processing` and is not falsely classified as failed admission.

The preflight rejects rooted/out-of-tree manifest paths. It is deliberately not the final integrity authority: a complete but malformed/oversized/hash-invalid delivery is claimable so the full admission gate can reject it deterministically and preserve failure evidence.

## 3. Ordering boundary

The active KB is a single-Current-snapshot runtime.

Until the producer supplies explicit monotonic sequence/predecessor/supersession authority, more than one complete delivery in `ready` fails closed with:

```text
MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY
```

Directory name, filesystem time and Git commit time are never used to guess ordering.

## 4. Claim / retry / archive lifecycle

Normal flow:

```text
ready
→ processing
→ ACCEPTED
→ ACTIVE
→ processed
```

One stranded `processing` delivery is resumed before any new `ready` delivery is considered. More than one stranded processing delivery fails closed.

Failure classes:

```text
permanent admission/activation failure
→ failed\<unique-name>\

transient receiver busy / health / timeout
→ processing + kb-retryable.json

runtime ACTIVE but processed-archive move failed
→ processing + kb-archive-pending.json
```

Each receiver attempt preserves stdout/stderr inside the claimed delivery. Successful archives contain `kb-active-receipt.json`. Permanent failures contain machine-readable `kb-failure.json` pointing to attempt logs.

A repeated transport may reuse the same delivery ID. Existing processed evidence is never overwritten; replay is archived under a unique replay directory while Current/idempotency rules are still enforced by the receiver.

## 5. Receive and health serialization

Three locks protect distinct boundaries:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receiver-service.lock
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\processor.lock
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receive.lock
```

- `receiver-service.lock` prevents multiple continuous watchers.
- `processor.lock` serializes claim/archive lifecycle.
- `receive.lock` serializes admission/index/cutover, Current health inspection and operational retention.

`check-modulecatalog-kb-runtime-windows.ps1 -AssumeReceiveLockHeld` is allowed only when an internal caller already owns the receive lock.

## 6. Receiver timeout / orphan prevention

`process-modulecatalog-inbox-windows.ps1` bounds one receiver attempt with `ReceiverTimeoutSeconds` (default 7200 seconds).

Timeout is retryable rather than permanent. The delivery remains recoverable in `processing`.

On Windows, timeout terminates the complete receiver process tree with `taskkill.exe /T /F`, preventing orphan Python/MVS indexers from mutating the KB after the wrapper has timed out. Non-Windows CI fixtures use the normal forced-process fallback.

## 7. Admission and accepted projection

Acceptance validates at least:

```text
format / schema version
Catalog repository + exact commit
Asset count / Knowledge Unit count / relationship count / case count
per-Asset manifest membership
file sizes and SHA-256
bundle hash
source Asset hash
Asset identity / provenance
verification status
Knowledge Unit identity/parent linkage
Case identity/parent linkage
Relationship identity/endpoints
global duplicate IDs
unknown relationship targets
```

Missing producer facts remain missing/unknown. The KB does not manufacture canonical values.

Projection schema v2 preserves:

```text
knowledge-records.jsonl
knowledge-metadata.jsonl
relationships.jsonl
cases.jsonl
records\*.md
```

The eight-field Knowledge Record is a compatibility envelope only. Full reusable metadata remains structured.

## 8. Search / graph runtime projection

The existing `mcp-vector-search 4.1.14` runtime remains the only search/graph runtime:

```text
BM25
Vector
Hybrid
Knowledge Graph
MCP
```

Runtime-only YAML frontmatter exposes stable identity and graph metadata without modifying transported canonical files. Tags include:

```text
gace-reusable-asset
asset-<asset-id>
knowledge-kind-<kind>
lifecycle-<status>
verification-<status>
relation-<relation-type>
relationship-id-<relationship-id>
depends-on-<asset-id>
```

The full accepted `relationships.jsonl` sidecar is consulted during runtime enrichment, not only the relationship subset already embedded in individual metadata rows. Therefore future producer relationship kinds can reach the existing graph projection without changing Canonical data or silently dropping Asset-level edges.

Resolvable producer relationship/dependency targets create deterministic `related:` document links. Runtime filename prefixing rewrites those targets consistently before indexing.

## 9. Runtime search/use gates

Activation requires:

```text
all Knowledge Units exact BM25 retrieval by stable ID
representative of each Knowledge Kind by natural BM25 / Vector / Hybrid retrieval
representative Case ID retrieval
representative Relationship ID retrieval
KG reusable-data tag query
KG relation/dependency semantics when producer data supplies them
existing repository-history MCP regression
existing non-Catalog accepted Knowledge preservation
post-cutover rerun against the actual Current search path
```

No relationship/dependency is invented when absent.

## 10. Existing Knowledge preservation

When replacing a ModuleCatalog snapshot, the candidate formal set removes the previous ModuleCatalog reusable snapshot but preserves repository-history and non-Catalog Knowledge.

The corresponding non-Catalog Current Markdown corpus is copied byte-for-byte into Staging before adding the new prefixed ModuleCatalog runtime corpus. This avoids flattening future rich non-Catalog Knowledge through a legacy renderer during Catalog refresh.

## 11. ACCEPTED vs ACTIVE

Per-commit receipts are stored under:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receipts\<catalog-commit>.json
```

Meanings:

```text
ACCEPTED
= transport payload passed admission and local derived projection exists

ACTIVE
= staging index + MCP gates + Current cutover + post-cutover verification passed
```

Current authority:

```text
F:\G-ACE-KB\data\knowledge-records\modulecatalog-reusable-active.json
```

The Current reusable snapshot also contains `runtime-state.json`. ACTIVE receipt, activation marker and runtime-state must agree on commit and runtime hashes. An old ACTIVE receipt alone is never Current authority.

A replay of the Current commit revalidates the transported bytes and reruns Deep Current health before idempotent success.

## 12. Atomic cutover and crash recovery

Before destructive cutover, activation writes:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\activation-transaction.json
```

The PREPARED journal records every Current/backup/staging path needed for recovery.

`recover-modulecatalog-activation-windows.ps1` runs before a new activation:

- if ACTIVE marker + receipt + runtime-state already agree on the target, the prior activation had committed and recovery finalizes it;
- otherwise the prior fully-known search/formal/reusable/authority state is restored;
- missing required recovery evidence fails closed.

The journal is removed only after successful finalization or completed rollback.

## 13. Continuous Windows receiver

`watch-modulecatalog-kb-inbox-windows.ps1` is the continuous consumer. One activation finishes before another delivery is considered.

The watcher performs two independent Current-health cadences whenever an ACTIVE marker exists:

```text
RuntimeHealthSeconds      = 300   # shallow health, default 5 minutes
DeepRuntimeHealthSeconds  = 21600 # Deep MCP health, default 6 hours
```

The shallow gate is intentionally lower cost, but it is not count-only. It verifies Current authority/hashes/cardinalities/index warnings and accepted-snapshot → actual live ModuleCatalog Markdown byte-exact projection integrity.

The Deep gate invokes the same health script with `-Deep`, reopening MCP and exercising repository-history plus reusable BM25 / Vector / Hybrid / KG retrieval. Successful/failed Deep executions are emitted as `DEEP_HEALTH_PASS` / `DEEP_HEALTH_FAILED` service events. A Deep PASS also refreshes the shallow-health timestamp because it includes the shallow gate first.

Compatibility behavior is explicit: when the Scheduled Task configurator receives `RuntimeHealthSeconds=0` and `DeepRuntimeHealthSeconds` was not explicitly supplied, health is treated as disabled as a whole and Deep is also set to 0. Supplying an explicit Deep value overrides that compatibility behavior and permits deep-only operation.

Service events are stored at:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receiver-service.jsonl
```

Idle PASS logging is heartbeat-throttled and the JSONL is bounded by rotation. Failures use retry backoff rather than a tight retry loop.

## 14. Windows Scheduled Task

`configure-modulecatalog-kb-receiver-task-windows.ps1` can register:

```text
\G-ACE-KB-ModuleCatalogReceiver
```

as the current user, Limited, AtLogOn.

Installer verification covers executable, complete arguments, working directory, principal SID, Running state, receiver service lock and a fresh watcher `STARTED` event. Existing running task instances are stopped before replacement so stale command-line settings are not silently retained through `MultipleInstances=IgnoreNew`.

The task carries shallow health, Deep health, retention cadence and retention limits into the watcher and configures bounded restart attempts for transient startup failure.

Repository code does **not** install the task automatically. Master-PC installation remains an explicit environment action after the genuine transported-data runtime gate.

## 15. Operational retention

The receiver no longer leaves operational archives/backups unbounded.

Default retention:

```text
activation rollback backups     3 per class
processed delivery archives    20
failed delivery archives       20
accepted delivery snapshots     5
failed search-runtime backups   2
```

Retention runs hourly by default from the continuous watcher.

Before deletion it acquires `receive.lock`. If another receive/index/health operation owns that lock, cleanup skips safely. Cleanup also skips while an activation journal exists.

Protected regardless of age/rank:

```text
Current accepted snapshot
ACTIVE backupFormal
ACTIVE backupSearch
ACTIVE backupReusable when recorded
immediate reusable rollback sibling derived from backupSearch timestamp for older ACTIVE marker schema
```

Only known paths below the G-ACE KB data roots are eligible for deletion, and path-root checks run before removal. Transaction scratch is removable only while the receive lock is held and no activation journal exists.

Small per-commit receipt JSON files are kept as audit records.

Detailed policy: [MODULECATALOG_KB_RETENTION.md](MODULECATALOG_KB_RETENTION.md).

## 16. Runtime health verification

`check-modulecatalog-kb-runtime-windows.ps1` verifies:

```text
ACTIVE marker / receipt / runtime-state agreement
formal KB hash
reusable records/metadata hashes
relationship/case hashes + counts
delivery manifest hash
Current corpus counts/runtime tags
accepted-snapshot → live-runtime byte-exact ModuleCatalog Markdown projection
MVS indexed-file cardinality
absence of known BM25/vector degraded-mode warnings
no unresolved activation journal
```

The exact projection check uses `scripts/verify_modulecatalog_runtime_projection.py`. Its source is the accepted Current reusable `records/*.md`. It deterministically reproduces the only activation-time live transform:

```text
original accepted filename
→ accepted-modulecatalog-reusable-<commit12>-<filename>

frontmatter related: <target.md>
→ related: accepted-modulecatalog-reusable-<commit12>-<target.md>
```

It requires the live prefixed filename set and each file's bytes to match exactly. `scripts/runtime_corpus_integrity.py` supplies deterministic sorted filename/size/SHA-256 manifesting and aggregate SHA-256 support. Missing/extra files, wrong count, empty matching set or content drift fail closed even if MVS still reports the expected indexed-file count.

`-Deep` reruns repository-history plus reusable MCP BM25/Vector/Hybrid/KG gates after the complete shallow integrity gate.

## 17. Manual commands

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

One-shot watcher verification:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\watch-modulecatalog-kb-inbox-windows.ps1 `
  -Once
```

Deep Current health:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\check-modulecatalog-kb-runtime-windows.ps1 `
  -Deep
```

Retention dry run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\prune-modulecatalog-kb-retention-windows.ps1 `
  -DryRun
```

Scheduled receiver install/start:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\configure-modulecatalog-kb-receiver-task-windows.ps1
```

## 18. Completion definition

A transported Catalog payload is not operational merely because it was copied or ACCEPTED.

Completion requires:

```text
transport completeness proved before claim
full cryptographic/semantic admission PASS
projection schema v2 complete
structured relationships/cases retained with hashes + counts
existing BM25 / Vector / Hybrid gates PASS
existing Knowledge Graph gates PASS where applicable
existing Knowledge regression PASS
post-cutover MCP PASS on actual Current path
ACTIVE receipt + marker + runtime-state agreement
processed archive contains ACTIVE receipt + receiver diagnostics
no unresolved activation transaction
Current runtime shallow health PASS including byte-exact live projection
Deep MCP runtime health PASS
continuous receiver shallow/Deep configuration verified on the target PC when installed
bounded operational retention enabled
no timed-out/orphan receiver process remains active
```

The remaining environment-specific proof is the real Master-PC MVS runtime after ModuleCatalog genuinely transports a delivery. GitHub contract tests do not substitute for that Windows runtime proof.
