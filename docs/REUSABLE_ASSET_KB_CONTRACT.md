# Reusable Asset KB Acceptance Contract v1

## Purpose

G-ACE KB accepts and operates **reusable development assets**, not only Skills.
Reusable value includes code, logic, architecture, design, contracts, capabilities, test cases, evidence, patterns, workflows, configuration, integrations, remediation knowledge, and future reusable asset kinds.

The contract is operational, not archival: a delivery is complete only when its data is accepted, indexed by the existing KB runtime, searchable through MCP, activated as Current, and represented by matching ACTIVE authority.

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
transport completeness preflight
admission / cryptographic re-verification
local runtime projection
BM25 / Vector / Knowledge Graph indexing
MCP retrieval verification
single-Current snapshot replacement
atomic cutover / rollback
ACTIVE receipt + marker + runtime-state
processed/failed/retryable lifecycle
ongoing runtime health
```

The operational KB receive path does not clone/fetch ModuleCatalog and does not regenerate producer authority. Cross-repository producer execution in GitHub Actions is a compatibility test only.

The KB never rewrites transported canonical data. Runtime-only tags, links, filename prefixes and search documents are derived local projections. Missing facts remain missing/unknown; derived information remains visibly derived.

## Transport format

The producer contract is `gace.reusable-asset.v1`:

```text
<delivery-root>/
├─ manifest.json
└─ assets/
   ├─ <asset-id>/
   │  ├─ asset.json
   │  ├─ knowledge-units.jsonl
   │  ├─ relationships.jsonl
   │  ├─ cases.jsonl
   │  └─ manifest.json
   └─ ...
```

The top-level manifest identifies the exact Catalog repository/commit and declares each Asset with its source Asset hash, bundle hash, Knowledge Unit count, relationship count and case count.

Each per-Asset manifest uses SHA-256 and covers:

```text
asset.json
knowledge-units.jsonl
relationships.jsonl
cases.jsonl
```

## Transport completion versus admission

Presence of the top-level `manifest.json` alone is not enough to claim a delivery.
Before moving a directory from `ready` to `processing`, the KB checks that declared Asset directories/manifests and their listed files are present and have at least the declared byte size. A visibly partial copy stays pending.

This is only a transport-completeness preflight. It does **not** replace admission. Once claimed, the authoritative importer rechecks exact size, SHA-256, bundle hash, source Asset hash, identity, provenance, cardinality and relationships. Oversized/corrupt/invalid data is therefore claimed and rejected rather than being mistaken for an in-progress transfer.

The preflight never follows rooted or traversal (`..`) paths outside the delivered Asset directory.

The transport side should ideally finish a bundle outside `ready` and atomically rename/move the completed directory into `ready`; the KB preflight remains a second line of defense against incomplete visibility.

## Asset and Knowledge Unit are different concepts

A ModuleCatalog Asset is the parent reusable package.
A Knowledge Unit is an independently searchable/reusable projection from that Asset.

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

Every Knowledge Unit keeps `parent_asset_id`, so search results remain traceable to the parent Asset and exact Catalog commit.

## `asset.json`

The KB requires the structured Reusable Asset Schema v1 sections:

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

Important boundaries:

- `asset_kind` may remain `unknown`; the KB does not invent a stronger type.
- classification fields remain semantically distinct rather than being collapsed into one tag list.
- applicability/contract fields may remain empty or unknown when the producer lacks canonical evidence.
- `verification.status` must be `verified` for admission; PASS scope is never widened beyond recorded evidence.
- origin provenance and Catalog provenance remain separate facts.
- lifecycle remains independent from verification.
- canonical sources and derived fields remain distinguishable.

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

`knowledge_kind` describes the searchable unit, for example:

```text
discovery
documentation
design
logic
architecture
evidence
code
test_case
```

It is intentionally distinct from the parent Asset's `asset_kind`.

## `relationships.jsonl`

Relationships are first-class reusable data, not disposable export metadata.
Current producer relations include Asset → Knowledge Unit `contains` edges and resolvable canonical dependency edges when present.

The KB verifies relationship IDs/endpoints and preserves the aggregated relationship sidecar through ACCEPTED and ACTIVE snapshots with independent SHA-256 and cardinality authority.

For the existing MVS 4.1.14 Knowledge Graph runtime, the KB also creates **derived runtime projections**:

```text
relation-<relation-type> tags
related: document links when endpoints resolve
depends-on-<asset-id> tags
```

This does not replace the canonical relationship sidecar and does not invent absent producer relations.

## `cases.jsonl`

Test data is both evidence and reusable knowledge. Case data may include:

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

Unknown scenario/input/actual values remain null when not deterministically available. Stable case IDs and real test content remain searchable. The structured case sidecar is retained through ACTIVE with hash/count authority.

## KB projection schema v2

For each accepted delivery, the KB creates a local projection:

```text
knowledge-records.jsonl
knowledge-metadata.jsonl
relationships.jsonl
cases.jsonl
records/*.md
```

The eight-field Knowledge Record is only the legacy compatibility envelope:

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

For generic reusable assets, `cause`/`fix` remain empty unless canonical source data really represents a cause/fix event.

Full reusable meaning remains in structured metadata/sidecars and rich Markdown, including identity, kind, lifecycle, verification, purpose, capabilities, applicability, contract, composition, source paths, provenance, integrity, cases and relationships.

## Runtime-only search enrichment

The transported bundle is never modified. The local Markdown projection receives deterministic YAML frontmatter for the already-installed MVS runtime, including:

```text
gace-reusable-asset
asset-<asset-id>
knowledge-kind-<kind>
lifecycle-<status>
verification-<status>
relation-<relation-type>
depends-on-<asset-id>
related: <resolved runtime document>
```

When activation prefixes Catalog runtime filenames to isolate them from the existing KB corpus, related-link targets are rewritten to the same prefix before indexing.

## Admission gates

A delivery fails closed when any required boundary fails, including:

```text
top-level format/schema/repository/commit
assetCount and actual Asset set
unique Asset IDs
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
relationship node resolution
projection hashes/cardinality
```

A replay is not trusted merely because a receipt already exists. The payload is re-imported/revalidated and replay-derived hashes must match accepted authority.

## Inbox and operational lifecycle

Default receive boundary:

```text
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\
├─ ready\
├─ processing\
├─ processed\
└─ failed\
```

Lifecycle:

```text
ready
→ transport-complete claim
→ processing
→ ACCEPTED
→ runtime activation
→ ACTIVE
→ processed
```

Failure classes are separated:

- permanent admission/activation failure → `failed` with diagnostics;
- transient receiver busy/health/timeout → stays in `processing` as `RETRYABLE`;
- ACTIVE runtime established but archive move failed → stays in `processing` as `ACTIVE_ARCHIVE_PENDING`;
- a stranded single `processing` delivery is resumed on the next run;
- more than one stranded processing delivery fails closed.

Receiver stdout/stderr are preserved with delivery evidence.

A duplicate delivery ID replay never overwrites an earlier processed archive; a unique replay archive name is used while the receiver still enforces Current/idempotency rules.

## Ordering authority

The active KB has one Current ModuleCatalog snapshot.
Until the producer contract supplies explicit ordering/predecessor authority, more than one complete delivery in `ready` is rejected with:

```text
MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY
```

Directory name, filesystem time and Git commit time are never used to guess newest order.

## Runtime activation

An ACCEPTED payload is not operational yet.
Activation uses the existing KB runtime:

```text
preserve existing non-Catalog runtime corpus
replace prior ModuleCatalog reusable snapshot
build staging corpus
BM25 / Vector / Knowledge Graph index
existing repository-history MCP regression
existing accepted-asset regression when present
reusable exact/natural/case/relationship/KG gates
write PREPARED activation journal
backup-backed Current cutover
post-cutover MCP against actual Current path
write matching ACTIVE runtime-state / marker / receipt
clear activation journal
archive delivery under processed
```

The legacy 13-record ModuleCatalog trial snapshot is replaced when the full Catalog snapshot becomes Current; stale Catalog snapshots are not accumulated in normal search.

## Search/use gates

Activation proves more than file ingestion:

```text
all Knowledge Units exact BM25 retrieval by stable ID
representative of every Knowledge Kind through BM25 / Vector / Hybrid natural retrieval
representative Case ID retrieval
representative Relationship ID retrieval
KG reusable-data tag query
KG relation-type tag query when semantics exist
KG dependency tag query when producer dependencies exist
KG LINKS_TO presence when resolvable producer relations exist
existing repository-history retrieval regression
post-cutover rerun against actual Current path
```

## Transaction / crash recovery

Before destructive Current cutover, the KB writes:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\activation-transaction.json
```

The PREPARED journal records current/backup/staging paths required for recovery. A subsequent receive first resolves an unfinished transaction:

- if marker + receipt + runtime-state already agree on target ACTIVE commit, recovery finalizes the committed activation;
- otherwise the last known Current state is restored from journaled backups;
- missing/unrecoverable authority fails closed rather than guessing.

## Concurrency and timeout boundaries

Locks serialize the unattended pipeline:

```text
receiver-service.lock   # single long-running watcher
processor.lock          # claim/archive lifecycle
receive.lock            # admission/index/cutover/runtime-health
```

The inbox processor bounds a receiver attempt (`ReceiverTimeoutSeconds`, default 7200 seconds). Timeout is retryable. On Windows it terminates the complete receiver process tree (`taskkill /T /F`) so MVS/Python descendants are not left mutating the runtime after the wrapper timed out.

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

States:

```text
ACCEPTED = admission + local projection passed
ACTIVE   = indexing + MCP + post-cutover Current verification passed
```

An old ACTIVE receipt alone is never sufficient to establish Current. Marker, receipt and runtime-state must agree on commit and runtime hashes.

## Ongoing runtime health

`check-modulecatalog-kb-runtime-windows.ps1` verifies Current marker/receipt/runtime-state agreement, formal/reusable/delivery/relationship/case hashes and counts, runtime frontmatter, MVS indexed cardinality and degraded-search warnings.

`-Deep` additionally reruns repository-history and reusable-asset MCP gates across BM25 / Vector / Hybrid / KG.

## Continuous Windows receiver

`watch-modulecatalog-kb-inbox-windows.ps1` polls synchronously with a singleton lock, heartbeat/failure JSONL log and bounded rotation.

`configure-modulecatalog-kb-receiver-task-windows.ps1` can register the watcher as a current-user Limited AtLogOn task. Task settings include bounded restart attempts for transient startup failures (default 12 restarts at a 1-minute interval), for example when the F: runtime is not immediately ready at logon.

Repository implementation does **not** install the task. Master-PC task installation is a separate explicit environment action.

## Current compatibility regression

The current cross-repository compatibility test is pinned to ModuleCatalog producer commit:

```text
224d96615d4cd3a4c87ca0de581d6124a871a3fd
```

Recorded regression boundary:

```text
80 Assets
720 Knowledge Units
160 test-case records
```

This pin exists only for CI contract verification. It is not the operational receive source and is not assumed to be merged canonical `main`.

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
processed archive contains ACTIVE receipt + receiver diagnostics
no unresolved activation transaction journal
runtime health PASS
no timed-out/orphan receiver process remains active
```

## Non-negotiable rule

G-ACE KB is not a Skill-only KB. Any verified reusable Code, Logic, Architecture, Design, Contract, Capability, Test Case, Evidence, Pattern or future reusable development asset may be operated when ModuleCatalog transports it without fabricating canonical facts.
