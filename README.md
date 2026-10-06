# G-ACE Development Knowledge Base

G-ACE Dev KB is the runtime/search layer for reusing development knowledge and reusable development assets across G-ACE work.

It is **not Skill-only**. Reusable scope includes repository history, code, logic, architecture, design, contracts, capabilities, tests/cases, evidence, patterns, workflows, configuration, integration/remediation knowledge, and future reusable asset kinds.

> **Development starts here.** Before changing source, read the linked Current Design and Project Tree. Check Design Delta when work changes an existing design decision. Do not treat future design or unexecuted runtime work as current implementation.

## Development entry points

- [Current Design](docs/CURRENT_DESIGN.md) — current responsibilities, authority boundaries, runtime design, and completion gates.
- [Project Tree](docs/PROJECT_TREE.md) — repository navigation and file/directory responsibilities.
- [Design Delta](docs/DESIGN_DELTA.md) — intentional deviations from the design baseline with reasons/evidence.
- [ModuleCatalog KB intake/runtime](docs/MODULECATALOG_KB_INTAKE_RUNTIME.md) — transported reusable-asset receipt through existing KB runtime activation.
- [ModuleCatalog operational retention](docs/MODULECATALOG_KB_RETENTION.md) — bounded rollback/archive retention for long-running Windows operation.

## Authority and responsibility boundary

Authority is source-specific.

```text
Repository-derived history
  Git/GitHub commit evidence
        ↓
  G-ACE KB projection/search

ModuleCatalog reusable assets
  ModuleCatalog canonical Asset + verification
        ↓
  search-ready gace.reusable-asset.v1 KBData
        ↓
  transport
        ↓
──────────────── KB responsibility starts here ────────────────
        ↓
  receipt / integrity admission
        ↓
  local structured projection
        ↓
  existing BM25 / Vector / Knowledge Graph
        ↓
  existing MCP retrieval
        ↓
  Current activation / health / retention
```

The operational ModuleCatalog receive path **does not clone/fetch ModuleCatalog** and does not regenerate producer canonical data. Cross-repository checkout in GitHub Actions exists only as a producer/consumer contract test.

## Existing KB runtime

`mcp-vector-search` 4.1.14 remains the active OSS search/graph runtime. G-ACE-specific code adapts authoritative records and reusable assets into that existing runtime rather than building a second search engine.

The operational search surface is:

```text
Markdown search corpus
├─ BM25
├─ Vector search
├─ Hybrid search
├─ Knowledge Graph
└─ MCP stdio tools
```

Repository-managed Windows compatibility work includes Kuzu path handling, Windows multiprocessing behavior, MCP SDK compatibility, embedding-dimension compatibility, atomic BM25 reopen after rebuild, doc-only KG handling, and bounded indexing concurrency/memory behavior.

## Base Knowledge Record compatibility envelope

The long-standing record envelope remains:

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

This is now explicitly a **compatibility/search envelope**, not the complete reusable-asset model. Structured ModuleCatalog data is preserved separately rather than being flattened into eight fields.

## ModuleCatalog reusable-asset contract

Current producer format:

```text
gace.reusable-asset.v1
```

Transported delivery:

```text
<delivery-root>\
├─ manifest.json
└─ assets\
   └─ <asset-id>\
      ├─ asset.json
      ├─ knowledge-units.jsonl
      ├─ relationships.jsonl
      ├─ cases.jsonl
      └─ manifest.json
```

Current producer regression boundary from ModuleCatalog PR #4 is:

```text
80 Assets
720 Knowledge Units
160 test cases
```

Those cardinalities are a current regression fixture, **not hard-coded KB limits**. KB admission derives counts from the delivered manifest.

## KB-side receive and activation pipeline

Standard Windows inbox:

```text
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\
├─ ready\
├─ processing\
├─ processed\
└─ failed\
```

Operational flow:

```text
transported delivery
→ transport-completeness preflight
→ processing claim
→ cryptographic/schema/provenance admission
→ projection schema v2
→ ACCEPTED receipt
→ preserve existing non-Catalog rich corpus
→ replace prior ModuleCatalog reusable snapshot candidate
→ existing BM25 / Vector / KG staging index
→ existing repository-history MCP regression
→ reusable BM25 / Vector / Hybrid / KG gates
→ durable PREPARED activation journal
→ backup-backed Current cutover
→ post-cutover MCP against actual Current path
→ ACTIVE runtime-state / marker / receipt
→ processed archive
→ periodic Current health
→ bounded operational retention
```

`ACCEPTED` means the transported payload and derived local projection passed admission. It does **not** mean the data is operationally usable.

`ACTIVE` is emitted only after the existing KB runtime has indexed the data and post-cutover MCP verification succeeds.

## Projection schema v2

Accepted/Current reusable snapshots preserve:

```text
knowledge-records.jsonl        # eight-field compatibility envelopes
knowledge-metadata.jsonl       # full structured reusable metadata
relationships.jsonl            # producer relationship sidecar
cases.jsonl                    # producer reusable/test cases
records\*.md                   # existing MVS runtime corpus
delivery-manifest.json
acceptance-state.json
runtime-state.json             # Current snapshot only
```

Structured metadata retains identity, classification, discovery, applicability, contract, composition, implementation, verification, provenance, lifecycle, integrity, derivation and source-path/content information supplied by the producer.

Missing producer facts stay missing/unknown. KB runtime adaptation never promotes guessed information into canonical producer truth.

## Search and graph projection

Runtime-only YAML frontmatter enriches the derived Markdown corpus without modifying transported canonical files. Search/graph metadata includes stable Knowledge/Asset identity and tags such as:

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

Resolvable relationship/dependency targets are converted into deterministic `related:` links for the existing MVS Knowledge Graph. The full `relationships.jsonl` sidecar is also consulted so future producer relationship kinds can be projected without requiring the importer to silently invent or discard them.

Runtime activation proves:

- exact BM25 retrieval for every Knowledge Unit;
- representative natural retrieval for every Knowledge Kind through BM25, Vector and Hybrid modes;
- Case/Relationship identifiers are searchable;
- reusable runtime presence in the Knowledge Graph;
- producer relationship/dependency semantics are projected where resolvable;
- existing repository-history retrieval remains valid;
- the same MCP gates still work after switching the real Current path.

## Reliability / fail-closed behavior

The receive path includes:

- transport-completeness detection so partially copied deliveries remain pending;
- exact SHA-256/size/bundle/source-asset integrity verification;
- safe-path checks for transported manifest paths;
- duplicate identity/cardinality/relationship-target checks;
- `ready → processing → processed/failed` lifecycle;
- resumable single stranded `processing` delivery;
- retryable receiver-busy/timeout/health failures;
- full Windows receiver process-tree termination on timeout;
- preserved receiver stdout/stderr diagnostics;
- duplicate delivery-name replay archive without overwriting prior evidence;
- `ACTIVE_ARCHIVE_PENDING` handling when runtime activation succeeded but archive movement did not;
- receive/index/cutover serialization with locks;
- journal-backed hard-interruption recovery;
- rollback of formal records, search runtime, reusable snapshot, marker and receipt authority when cutover fails;
- rejection of ambiguous multiple complete deliveries until producer supplies explicit ordering authority.

## Continuous Windows receiver

`scripts/watch-modulecatalog-kb-inbox-windows.ps1` is the long-running consumer. It synchronously processes the inbox, applies retry backoff after transient failure, rotates its service JSONL, runs operational retention, and performs two independent Current health cadences while an ACTIVE snapshot exists:

```text
shallow runtime health     300 seconds by default
Deep MCP runtime health  21600 seconds (6 hours) by default
```

The shallow gate is low-cost but still fail-closed: it verifies authority/hash/count/index state and deterministically reconstructs the accepted Current snapshot's activation-time filename/link transformation, requiring the actual live ModuleCatalog Markdown projection to match byte-for-byte. The Deep gate additionally reopens MCP and exercises repository-history plus reusable BM25 / Vector / Hybrid / KG retrieval. Deep results are recorded as `DEEP_HEALTH_PASS` / `DEEP_HEALTH_FAILED` service events.

`scripts/configure-modulecatalog-kb-receiver-task-windows.ps1` configures a current-user Limited AtLogOn Scheduled Task:

```text
\G-ACE-KB-ModuleCatalogReceiver
```

The task installer persists both health cadences and verifies executable/arguments/working directory/principal SID plus a fresh watcher `STARTED` event and service-lock evidence after startup. For compatibility, explicitly setting `RuntimeHealthSeconds=0` without explicitly supplying `DeepRuntimeHealthSeconds` disables health as a whole; an explicit Deep value still supports deep-only operation. Repository code does **not** install the task automatically; Master-PC installation remains an explicit environment action after the real transported-data runtime gate.

## Runtime health

`scripts/check-modulecatalog-kb-runtime-windows.ps1` validates the active marker, receipt and runtime-state agreement, hashes/cardinalities, relationship/case sidecars, Current corpus, MVS indexed-file count, known BM25/vector degradation warnings, and the exact accepted-snapshot → live-runtime Markdown projection.

The exact projection gate rebuilds the only allowed activation-time runtime transform in memory — commit-prefixed filenames plus prefixed frontmatter `related:` targets — then requires filename set and file bytes to match the actual live `data\knowledge-search\records` projection. Matching record counts alone cannot hide silent Markdown drift.

`-Deep` additionally reruns existing-history and reusable-asset MCP retrieval gates. The watcher runs this Deep gate every 21600 seconds by default, independently of the 300-second shallow gate.

## Operational retention

Long-running receive/index operation creates rollback and archive material, so retention is bounded rather than left to grow forever.

Default policy:

```text
activation rollback backups     3 per class
processed delivery archives    20
failed delivery archives       20
accepted delivery snapshots     5
failed search-runtime backups   2
```

Current ACTIVE authority and immediate rollback evidence are protected regardless of age. Retention acquires the receive lock and skips cleanup while an activation transaction journal exists. Small per-commit receipt JSON files remain as audit records.

See [ModuleCatalog operational retention](docs/MODULECATALOG_KB_RETENTION.md).

## Local layout

```text
F:\G-ACE-KB
├─ repo\
├─ data\
│  ├─ knowledge-records\
│  ├─ knowledge-search\
│  ├─ knowledge-sources\accepted\
│  ├─ knowledge-intake\modulecatalog\
│  └─ knowledge-inbox\modulecatalog\
├─ runtime\mcp-vector-search\
├─ assets\
└─ .venv\
```

Generated runtime data, indexes, caches, secrets, accepted snapshots and local environments stay outside Git source.

## Previously validated formal KB baseline

Before the full reusable-asset receive pipeline, the Master Windows formal KB was validated with:

```text
repository-history records = 94
verified DebugAI reusable records = 13
formal records = 107
indexed files = 107/107
chunks / embeddings = 1167 / 1167
Knowledge Graph = 957 entities / 979 relationships
BM25 = PASS
MCP history retrieval = PASS
13/13 accepted reusable retrieval = PASS
GACE_FORMAL_KB_PROMOTION=PASS RECORDS=107
```

That remains the pre-full-Catalog runtime baseline. It must not be confused with proof that the new transported 80-Asset / 720-Knowledge-Unit snapshot has already been activated on the Master PC.

## Current feature status

Feature branch:

```text
feat/reusable-asset-kb-schema-20261001
```

PR #3 remains Draft and unmerged.

GitHub CI validates deterministic receipt/admission, transport readiness, retry/timeout/archive behavior, activation-journal recovery, runtime-health serialization, receiver service behavior/backoff, bounded retention, rich-corpus preservation, runtime graph projection, deterministic runtime-corpus hashing, accepted-to-live byte-exact runtime projection, periodic Deep-health invocation, importer/replay/tamper gates, existing-Knowledge regression, the real current 80-Asset producer contract, and an actual `windows-latest` Scheduled Task registration/startup/uninstall gate.

## Remaining environment-specific proof

GitHub source/CI verifies the new runtime-integrity and periodic-Deep behavior, but it cannot substitute for the actual installed Master-PC MVS runtime after ModuleCatalog genuinely transports a delivery.

Required final runtime path:

```text
real Catalog transport
→ KB ready/processing
→ full receive/admission
→ projection schema v2
→ existing BM25 / Vector / KG index on F:\G-ACE-KB
→ exact/natural MCP retrieval
→ Current cutover
→ post-cutover MCP
→ ACTIVE authority
→ processed archive
→ byte-exact Current projection health
→ Deep runtime health
→ periodic receiver/Scheduled Task actual-state verification when explicitly executed
```

Until that real transported-data Windows gate passes, do not claim the new full reusable-asset pipeline is Master-PC validated and do not merge PR #3 to main.


## TGserver ZERO P014 runtime logging

G-ACE KB search/exact completion and failure metadata is forwarded to TGserver ZERO project `P014` through the existing product-neutral Webhook Gateway Internal Event API.

Runtime path:

```text
Master-PC G-ACE KB
  -> Webhook Gateway POST /internal/events
  -> registered generic destination tgserver-zero-bulk
  -> existing Cloudflare Access protected TGserver ZERO POST /ingest/bulk
  -> P014 Telegram raw log + Meilisearch
```

The Master PC does not receive TGserver Cloudflare Access credentials. It holds only the scoped Gateway Internal Event API endpoint/token required for this trusted producer. TGserver Access credentials remain owned by the Gateway deployment.

Only bounded operational metadata is emitted: request ID, action (`search`/`exact`), PASS/FAIL, duration, and a bounded internal error code. Query text, knowledge IDs, KB content, search results, Case/Relationship content, arbitrary exception text, filesystem paths, and credentials are not forwarded.

Logging is fail-open for KB requests. If `GACE_EVENT_GATEWAY_URL` or `GACE_EVENT_GATEWAY_TOKEN` is absent, logging is disabled without changing the KB result. A log is considered accepted only after the Gateway returns its durable HTTP 202 receipt with `ok=true`.

TGserver ZERO registry ownership remains separate: `seigo-gace/gace-dev-kb/default -> P014` in G002. Topic provisioning, Gateway deployment configuration, Telegram raw persistence, and central Reader retrieval must each be verified independently before live delivery is claimed.
