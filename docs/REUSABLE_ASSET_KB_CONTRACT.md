# Reusable Asset KB Acceptance Contract v1

## Purpose

G-ACE KB accepts and operates **reusable development assets**, not only Skills.
Reusable value includes code, logic, architecture, design, contracts, capabilities, test cases, evidence, patterns, workflows, configuration, integrations, remediation knowledge, and future reusable asset kinds.

The contract is operational, not archival: a delivery is complete only when its data is accepted, indexed by the existing KB runtime, searchable through MCP, activated as Current, continuously health-checkable, and protected by bounded rollback/archive retention.

## Producer / consumer boundary

ModuleCatalog owns:

```text
asset creation
verification
canonical/derived boundary
search-ready KBData generation
export integrity
transport to the KB receive boundary
```

G-ACE KB owns **receipt onward**:

```text
transport-completeness preflight
admission / cryptographic re-verification
local runtime projection
BM25 / Vector / Hybrid / Knowledge Graph indexing
MCP retrieval verification
single-Current snapshot replacement
atomic cutover / rollback
ACTIVE receipt + marker + runtime-state
processed/failed/retryable lifecycle
ongoing runtime health
bounded operational retention
```

The operational KB receive path does not clone/fetch ModuleCatalog and does not regenerate producer authority. Cross-repository producer execution in GitHub Actions is a compatibility test only.

The KB never rewrites transported canonical data. Runtime-only tags, links, filename prefixes and search documents are derived local projections. Missing facts remain missing/unknown; derived information remains visibly derived.

## Transport format

Producer contract:

```text
gace.reusable-asset.v1
```

```text
<delivery-root>/
├─ manifest.json
└─ assets/
   └─ <asset-id>/
      ├─ asset.json
      ├─ knowledge-units.jsonl
      ├─ relationships.jsonl
      ├─ cases.jsonl
      └─ manifest.json
```

The top-level manifest identifies the exact Catalog repository/commit and declares each Asset with source Asset hash, bundle hash, Knowledge Unit count, relationship count and case count.

Each per-Asset SHA-256 manifest covers:

```text
asset.json
knowledge-units.jsonl
relationships.jsonl
cases.jsonl
```

## Transport completion versus admission

Presence of top-level `manifest.json` alone is not enough to claim a delivery.

Before `ready → processing`, KB checks declared Asset directories/manifests and listed file availability/declared byte size. A visibly partial copy remains pending.

This is only a transport-completeness preflight. Once claimed, admission rechecks exact size, SHA-256, bundle hash, source Asset hash, identity, provenance, cardinality, cases and relationship topology.

Preflight never follows rooted or traversal paths outside the delivery Asset directory.

Transport should ideally build outside `ready` and atomically move/rename the completed directory into `ready`; preflight remains a second line of defense.

## Asset and Knowledge Unit

A ModuleCatalog Asset is the parent reusable package. A Knowledge Unit is an independently searchable projection from that Asset.

One Asset may produce many Knowledge Units:

```text
Asset
├─ discovery / overview
├─ documentation
├─ design
├─ logic
├─ architecture
├─ evidence
├─ code unit(s)
└─ test-case unit(s)
```

Every Knowledge Unit keeps `parent_asset_id` and exact Catalog provenance.

## `asset.json`

Required structured sections:

```text
identity
classification
discovery
applicability
contract
composition
implementation
verification
provenance
lifecycle
integrity
derivation
```

Rules:

- `asset_kind` may remain `unknown`; KB does not invent a stronger type.
- classification dimensions remain distinct rather than collapsed into one tag list.
- applicability/contract may remain empty or unknown without canonical evidence.
- `verification.status` must be `verified` for admission; PASS scope is not widened.
- origin provenance and Catalog provenance remain separate.
- lifecycle remains independent from verification.
- canonical and derived data remain distinguishable.

## `knowledge-units.jsonl`

Each searchable unit contains at least:

```text
schema_version
knowledge_id
parent_asset_id
knowledge_kind
title
content
source_paths
content_status
derivation
```

`knowledge_kind` is intentionally distinct from parent `asset_kind`.

## `relationships.jsonl`

Relationships are first-class reusable data.

KB validates relationship identity and endpoints, aggregates the full producer sidecar, and retains it through ACCEPTED and ACTIVE snapshots with independent SHA-256/cardinality authority.

The existing MVS runtime receives a deterministic **derived** graph/search projection:

```text
relation-<relation-type> tag
relationship-id-<stable-id> tag
depends-on-<asset-id> tag
related: <resolved runtime document>
```

Runtime enrichment consults the complete accepted sidecar, not only relations already embedded in a Knowledge Unit metadata row. Therefore future producer Asset-level relation kinds remain projectable without importer-specific special casing.

No absent relationship is inferred.

## `cases.jsonl`

Test data is both verification evidence and reusable knowledge. Case data may include:

```text
case_id
parent_asset_id
case_type
scenario
input
expected
actual
result
source_test
test_content
extraction_status
derivation
```

Unknown values remain null when not deterministically available. Stable Case IDs and actual test content remain searchable. The structured sidecar is retained through ACTIVE with hash/count authority.

## Projection schema v2

Accepted delivery creates:

```text
knowledge-records.jsonl
knowledge-metadata.jsonl
relationships.jsonl
cases.jsonl
records/*.md
```

The eight-field Knowledge Record remains a compatibility envelope:

```text
type
repository
commit
summary
cause
fix
validation
source
```

Generic reusable assets do not receive fabricated `cause`/`fix` values.

Full reusable meaning remains in structured metadata/sidecars and rich Markdown.

## Runtime-only search enrichment

Transported canonical files are unchanged. Derived Markdown receives MVS-compatible YAML frontmatter including:

```text
gace-reusable-asset
asset-<asset-id>
knowledge-kind-<kind>
lifecycle-<status>
verification-<status>
relation-<relation-type>
relationship-id-<stable-id>
depends-on-<asset-id>
related: <resolved runtime document>
```

When activation prefixes Catalog runtime filenames, `related:` targets are rewritten to the same prefix before indexing.

## Admission gates

Fail closed on any required boundary failure, including:

```text
top-level format/schema/repository/commit
assetCount and actual Asset set
unique/safe Asset IDs
per-Asset SHA-256 manifest
per-Asset bundle hash
source Asset hash
required bundle files
Asset required sections
verification.status=verified
Catalog provenance / commit / asset path
unique Knowledge IDs
parent_asset_id integrity
Knowledge Unit / relationship / case counts
global relationship ID uniqueness
relationship node resolution
projection hashes/cardinality
```

A replay is never trusted merely because a receipt exists. Payload is re-imported/revalidated and replay-derived hashes must match accepted authority.

## Inbox lifecycle

```text
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\
├─ ready\
├─ processing\
├─ processed\
└─ failed\
```

```text
ready
→ transport-complete claim
→ processing
→ ACCEPTED
→ runtime activation
→ ACTIVE
→ processed
```

Failure classes:

- permanent admission/activation failure → `failed` with diagnostics;
- transient receiver busy/health/timeout → `processing` as `RETRYABLE`;
- ACTIVE established but archive move failed → `processing` as `ACTIVE_ARCHIVE_PENDING`;
- exactly one stranded processing delivery resumes;
- multiple stranded processing deliveries fail closed;
- duplicate delivery ID replay cannot overwrite prior processed evidence.

Receiver stdout/stderr remains delivery evidence.

## Ordering authority

Normal runtime has one Current ModuleCatalog snapshot.

Until producer contract supplies explicit ordering/predecessor authority, more than one complete `ready` delivery fails closed:

```text
MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY
```

Directory name, filesystem time and Git commit time never decide newest order.

## Runtime activation

An ACCEPTED payload is not operational.

```text
preserve existing non-Catalog rich runtime corpus byte-for-byte
replace prior ModuleCatalog reusable snapshot candidate
build staging corpus
BM25 / Vector / Hybrid / Knowledge Graph index
existing repository-history MCP regression
reusable exact/natural/case/relationship/KG gates
write PREPARED activation journal
backup-backed Current cutover
post-cutover MCP against actual Current path
verify structured relationship/case sidecars
write matching ACTIVE runtime-state / marker / receipt
clear activation journal
archive delivery under processed
```

The legacy 13-record ModuleCatalog trial snapshot is replaced when the full Catalog snapshot becomes Current; stale Catalog versions are not accumulated in normal search.

## Search/use gates

Activation proves more than file ingestion:

```text
all Knowledge Units exact BM25 retrieval
representative each Knowledge Kind natural BM25 / Vector / Hybrid retrieval
representative Case ID retrieval
representative Relationship ID retrieval
KG reusable-data tag query
KG relation/dependency/link presence when producer semantics exist
existing repository-history retrieval regression
post-cutover rerun against actual Current path
```

## Transaction / crash recovery

Before destructive Current cutover:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\activation-transaction.json
```

records current/backup/staging paths.

A subsequent receive resolves unfinished PREPARED work before starting another activation:

- if marker + receipt + runtime-state prove target ACTIVE, finalize committed activation;
- otherwise restore prior Current from journaled backups;
- missing required recovery evidence fails closed.

## Concurrency and timeout

```text
receiver-service.lock   # singleton watcher
processor.lock          # claim/archive lifecycle
receive.lock            # admission/index/cutover/health/retention
```

One receiver attempt is bounded by `ReceiverTimeoutSeconds` (default 7200 seconds). Timeout is retryable. On Windows, complete process-tree termination prevents orphan MVS/Python descendants from continuing to mutate runtime.

## Current authority and receipts

Per-commit receipt:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receipts\<catalog-commit>.json
```

Current authority:

```text
F:\G-ACE-KB\data\knowledge-records\modulecatalog-reusable-active.json
```

Current reusable snapshot also contains `runtime-state.json`.

```text
ACCEPTED = admission + local projection passed
ACTIVE   = indexing + MCP + post-cutover Current verification passed
```

An old ACTIVE receipt alone never establishes Current. Marker, receipt and runtime-state must agree.

## Ongoing runtime health

`check-modulecatalog-kb-runtime-windows.ps1` verifies Current authority agreement, formal/reusable/delivery/relationship/case hashes/counts, runtime frontmatter, accepted-snapshot → live-runtime byte-exact ModuleCatalog Markdown projection, MVS indexed cardinality and known degraded-search warnings.

The exact projection gate reconstructs the activation-time runtime transform from the accepted Current `records/*.md`: commit-prefixed filenames plus prefixed frontmatter `related:` targets. The live prefixed filename set and bytes must match exactly, so count/status agreement cannot hide silent runtime Markdown drift.

`-Deep` reruns repository-history and reusable BM25/Vector/Hybrid/KG MCP gates after the complete shallow integrity gate.

The continuous receiver uses two independent default cadences while an ACTIVE snapshot exists:

```text
shallow health  300 seconds
Deep MCP health 21600 seconds (6 hours)
```

Deep executions emit `DEEP_HEALTH_PASS` / `DEEP_HEALTH_FAILED`. Health serializes with `receive.lock` so no check can certify a runtime during replacement.

## Continuous Windows receiver

`watch-modulecatalog-kb-inbox-windows.ps1` polls synchronously with singleton locking, bounded JSONL rotation, heartbeat throttling, retry backoff, periodic shallow Current health, lower-frequency periodic Deep MCP health and periodic retention.

`configure-modulecatalog-kb-receiver-task-windows.ps1` can register a current-user Limited AtLogOn task with bounded restart attempts. Installer validates executable, persisted arguments, working directory, principal SID, Running state and a fresh watcher STARTED event/service lock, and persists both health cadences.

Compatibility rule: explicitly setting `RuntimeHealthSeconds=0` without explicitly supplying `DeepRuntimeHealthSeconds` disables health as a whole and therefore persists Deep as 0. An explicit Deep value takes precedence and permits deep-only operation.

Repository implementation does not install that task automatically.

## Operational retention

Long-running receive/index operation generates rollback and archive material. It is bounded by `prune-modulecatalog-kb-retention-windows.ps1`.

Default policy:

```text
activation rollback backups     3 per class
processed delivery archives    20
failed delivery archives       20
accepted delivery snapshots     5
failed search-runtime backups   2
```

Retention acquires `receive.lock`, skips during an activation journal, and protects Current accepted state plus immediate rollback authority regardless of age/ranking. Older ACTIVE-marker schema without explicit `backupReusable` is handled by deriving the exact reusable sibling from the shared activation timestamp.

Deletion is restricted to known operational paths under approved KB data roots. Small per-commit receipt JSON files remain as audit evidence.

See `MODULECATALOG_KB_RETENTION.md`.

## Current compatibility regression

Current CI contract producer pin:

```text
224d96615d4cd3a4c87ca0de581d6124a871a3fd
```

Current regression fixture:

```text
80 Assets
720 Knowledge Units
160 test cases
```

This is CI contract verification only; it is not the operational receive source and is not assumed merged to ModuleCatalog main.

## Completion definition

A delivered Catalog payload is operational only when all applicable conditions hold:

```text
transport completed and claimed safely
cryptographic/semantic admission PASS
projection schema v2 complete
structured relationship/case hashes and counts intact
existing BM25 / Vector / Hybrid gates PASS
existing Knowledge Graph gates PASS
post-cutover MCP PASS on actual Current path
ACTIVE receipt + marker + runtime-state agree
processed archive contains ACTIVE receipt + diagnostics
no unresolved activation transaction
shallow runtime health PASS including byte-exact live projection
Deep MCP runtime health PASS
bounded retention enabled for continuous operation
no timed-out/orphan receiver process remains active
continuous receiver/task shallow+Deep policy verified on target PC when installed
```

## Non-negotiable rule

G-ACE KB is not a Skill-only KB. Any verified reusable Code, Logic, Architecture, Design, Contract, Capability, Test Case, Evidence, Pattern or future reusable development asset may be operated when ModuleCatalog transports it without fabricating canonical facts.
