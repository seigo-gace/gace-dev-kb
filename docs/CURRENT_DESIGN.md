# G-ACE Dev KB — Current Design Baseline

## 1. Purpose

G-ACE Dev KB is the runtime/search layer for reusing development knowledge and reusable development assets across G-ACE work.

Reusable scope is not Skill-only. It includes repository history, code, logic, architecture, design, contracts, capabilities, tests/cases, evidence, patterns, workflows, configuration, integration/remediation knowledge, and future reusable asset kinds.

Authority is source-specific:

- committed repository evidence remains authoritative for repository-derived history;
- ModuleCatalog is authoritative for Catalog reusable-asset content through verified/search-ready KBData generation and transport;
- G-ACE KB owns receipt onward and never silently upgrades runtime-derived data into producer canonical truth.

## 2. Mandatory development routine

```text
README
→ Current Design / Project Tree / relevant Design Delta
→ implementation
→ test / debug / validation
→ commit
→ documentation gate
→ completion gate
```

Design is a baseline. Intentional design changes require a Design Delta; file/responsibility changes require Project Tree updates; validated current capability belongs in README/system documentation.

## 3. Existing runtime strategy

`mcp-vector-search` 4.1.14 is the active OSS search/index/MCP core. G-ACE does not build a second generic search engine or second Knowledge Graph for ModuleCatalog data.

```text
Markdown corpus
→ BM25
→ Vector semantic search
→ Hybrid search
→ Knowledge Graph
→ MCP stdio
→ AI/MCP client retrieval
```

Repository-managed Windows compatibility covers measured upstream/runtime gaps and is verified before formal indexing.

## 4. Legacy eight-field Knowledge Record

The original common record contract remains:

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

This is a compatibility/search envelope only. Rich reusable-asset data must not be truncated to it. Unsupported `cause`/`fix` remain empty rather than fabricated.

## 5. Repository-derived knowledge path

```text
Git committed evidence
→ gace_knowledge_adapter.py
→ eight-field records
→ deterministic Markdown
→ formal KB runtime
→ BM25 / Vector / KG / MCP
```

Rules:

- committed Git evidence is authority;
- missing evidence stays empty;
- tracked dirty state blocks normal durable export;
- durable export defaults to full reachable history;
- formal repository knowledge is pinned to an explicit revision;
- generated data/indexes stay outside Git source.

## 6. Previously validated formal baseline

Before the generalized Catalog receive path, Master Windows validated:

```text
repository records: 94
verified external records: 13
formal records: 107
formal corpus/index: 107/107
MCP repository-history retrieval: PASS
MCP all-13 reusable retrieval: PASS
natural reusable discovery: PASS
```

This is historical/pre-full-Catalog runtime evidence. The generalized ModuleCatalog snapshot replaces the legacy 13-record Catalog snapshot when genuinely transported data is activated; it does not retain both as simultaneous Current Catalog versions.

## 7. ModuleCatalog producer / KB consumer boundary

ModuleCatalog responsibility:

```text
Reusable Asset creation
→ verification
→ Canonical / Derived boundary
→ search-ready gace.reusable-asset.v1 KBData
→ integrity manifests
→ transport to Master PC KB boundary
```

G-ACE KB responsibility:

```text
transported delivery receipt
→ transport-completeness preflight
→ full fail-closed admission
→ projection schema v2
→ existing BM25 / Vector / KG staging runtime
→ existing-history + reusable MCP gates
→ single-Current snapshot replacement
→ transaction-journaled cutover / rollback
→ post-cutover MCP verification
→ ACTIVE marker / receipt / runtime-state
→ processed archive
→ ongoing runtime health
→ bounded operational retention
```

The operational receive path never clones/fetches ModuleCatalog and never runs the producer exporter to manufacture its own payload. Cross-repository producer execution in CI is contract verification only.

## 8. Transport contract

Accepted format:

```text
gace.reusable-asset.v1
```

Layout:

```text
<delivery>/
├─ manifest.json
└─ assets\<asset-id>\
   ├─ asset.json
   ├─ knowledge-units.jsonl
   ├─ relationships.jsonl
   ├─ cases.jsonl
   └─ manifest.json
```

Default receive lifecycle:

```text
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\
├─ ready\
├─ processing\
├─ processed\
└─ failed\
```

A top-level manifest alone does not prove copy completion. Before claim, the processor checks declared Asset directories/manifests and listed file availability/declared byte size. Partial transport remains pending. Unsafe rooted/traversal paths are never followed by preflight.

Full cryptographic/schema/provenance checks remain authoritative after claim.

## 9. Reusable projection schema v2

Accepted data is projected locally into:

```text
knowledge-records.jsonl       # compatibility envelope
knowledge-metadata.jsonl      # full structured reusable metadata
relationships.jsonl           # structured producer relationships
cases.jsonl                   # structured reusable/test cases
records/*.md                  # existing MVS runtime search projection
```

Every searchable Knowledge Unit keeps parent Asset identity and exact Catalog commit/source provenance.

Canonical transport data is not modified. Runtime-only frontmatter/tags/related links are generated only in the derived Markdown projection.

## 10. Search and Knowledge Graph use

Reusable data is not merely stored. Activation must prove use through the existing runtime:

```text
all Knowledge Units exact BM25 retrieval
representative each Knowledge Kind via BM25 / Vector / Hybrid
Case ID retrieval
Relationship ID retrieval
KG reusable-data tag query
KG relation/dependency/containment projection when producer relations exist
existing repository-history retrieval regression
post-cutover retrieval from actual Current runtime path
```

The runtime projection consults the full accepted `relationships.jsonl` sidecar as well as per-unit embedded relations. Asset-level future producer relationships therefore remain eligible for deterministic tag/link projection instead of being silently lost because an importer did not yet know that relation kind.

Structured relationship/case sidecars survive into Current independently of the MVS projection and are hash/count checked during acceptance, activation and health.

## 11. Single-Current snapshot rule

Normal runtime search has one Current ModuleCatalog reusable snapshot.

A new accepted snapshot replaces the prior Catalog snapshot while preserving repository-history and non-Catalog Knowledge. Historic Catalog snapshots remain evidence/rollback material rather than coexisting normal search candidates.

Until producer transport includes explicit sequence/predecessor authority, multiple complete `ready` deliveries are rejected rather than ordered by directory name, filesystem time or Git commit timestamp.

## 12. Receive reliability

Locks:

```text
receiver-service.lock
processor.lock
receive.lock
```

They serialize watcher, claim/archive, and admission/index/cutover/health/retention respectively.

Operational failure handling:

- exactly one stranded `processing` delivery resumes;
- permanent failure archives under `failed` with machine-readable evidence and receiver logs;
- transient busy/health/timeout remains `RETRYABLE` in processing;
- ACTIVE-but-not-archived remains `ACTIVE_ARCHIVE_PENDING`;
- duplicate delivery ID replay preserves prior processed archive and uses a unique replay archive;
- receiver timeout is bounded (default 7200 seconds);
- Windows timeout kills the complete receiver process tree to prevent orphan MVS/Python mutation after timeout.

## 13. Atomic activation and crash recovery

Before destructive Current cutover, activation writes a durable PREPARED journal:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\activation-transaction.json
```

The journal records all Current/backup/staging paths needed for deterministic recovery.

Recovery occurs before another activation:

- if marker + receipt + runtime-state prove the target already ACTIVE, finalize the committed transaction;
- otherwise restore the prior fully-known Current from backups;
- missing recovery authority fails closed.

Current authority requires agreement between:

```text
modulecatalog-reusable-active.json
current reusable runtime-state.json
receipts\<catalog-commit>.json
```

## 14. Continuous receiver

`watch-modulecatalog-kb-inbox-windows.ps1` is a singleton polling receiver with bounded JSONL logging, heartbeat throttling, retry backoff, periodic Current health and periodic retention.

Default cadences:

```text
poll                 10 seconds
retry backoff        60 seconds
heartbeat           300 seconds
runtime health      300 seconds
retention          3600 seconds
```

`configure-modulecatalog-kb-receiver-task-windows.ps1` can register it as a current-user Limited AtLogOn task and persists these operational settings. Task settings include bounded restart attempts for transient startup failures such as delayed F: availability.

Repository implementation does not install the task itself. Installation is a separate Master-PC action after the real transported-data runtime gate.

## 15. Runtime health

`check-modulecatalog-kb-runtime-windows.ps1` verifies marker/receipt/runtime-state authority, formal/reusable/delivery/relationship/case hashes and counts, Current corpus tags, MVS indexed cardinality and known degraded-search warnings.

`-Deep` reruns repository-history and reusable BM25/Vector/Hybrid/KG MCP gates.

Health checks serialize against receive/cutover so they cannot certify a runtime while it is being replaced.

## 16. Operational retention

Receive/index operation creates large transport archives, accepted snapshots and rollback/search backups. These are bounded so a continuously running PC KB does not grow without limit.

Default policy:

```text
activation rollback backups     3 per class
processed delivery archives    20
failed delivery archives       20
accepted delivery snapshots     5
failed search-runtime backups   2
```

Retention:

- runs from the continuous watcher every 3600 seconds by default;
- acquires `receive.lock` and skips if another receive/index/health operation is active;
- skips while an activation transaction journal exists;
- always protects the Current accepted snapshot;
- protects the ACTIVE marker's formal/search/reusable rollback paths;
- for older marker schema without `backupReusable`, derives the exact reusable rollback sibling from the shared activation timestamp and protects it;
- removes only known paths under approved `F:\G-ACE-KB\data` roots;
- may clean stale transaction scratch only while the receive lock is held and no activation journal exists;
- keeps small per-commit receipt JSON files as audit evidence.

See `docs/MODULECATALOG_KB_RETENTION.md`.

## 17. Storage boundary

```text
F:\G-ACE-KB\
├─ repo\                         # source/docs/tests only
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

Generated records, transport data, indexes, archives, runtime downloads, caches and local environments stay outside Git source.

## 18. Current implementation boundary (2026-10-02)

Proven on Master Windows before generalized transport:

- pinned MVS 4.1.14 Windows compatibility: PASS;
- formal 107-record baseline index/retrieval: PASS;
- repository-history MCP: PASS;
- 13 verified reusable records MCP + natural discovery: PASS.

Implemented and GitHub-CI covered on the generalized receive branch:

- current `gace.reusable-asset.v1` producer compatibility;
- current regression fixture: 80 Assets / 720 Knowledge Units / 160 cases;
- admission/integrity/idempotent replay validation;
- projection schema v2 with full structured metadata/relationship/case retention;
- partial transport/path safety;
- inbox claim/resume/retry/failure/archive lifecycle;
- timeout/process-tree cleanup;
- duplicate delivery replay archive preservation;
- single-Current replacement logic;
- byte-exact preservation of non-Catalog rich runtime corpus;
- runtime filename/link alignment;
- full relationship sidecar graph projection;
- activation transaction rollback/recovery;
- receiver/health/retention serialization;
- continuous receiver retry/backoff/health/retention;
- bounded operational archives/backups;
- actual Windows Scheduled Task registration/startup/uninstall CI gate;
- existing BM25/Vector/Hybrid/KG/MCP reusable gates.

Not yet claimed as real-PC PASS:

The generalized transported Catalog snapshot has not yet been genuinely delivered and activated through the installed Master-PC MVS runtime. Scheduled receiver task installation has also not been performed on Master PC.

Those environment-specific gates remain required before PR #3 can be complete/merge-ready.

## 19. Future boundary

TGserver-linked generic knowledge processing/admission and unrelated Astera-oriented KB architecture remain separate scopes unless explicitly integrated through a verified contract.

Do not infer those systems from the ModuleCatalog reusable-asset intake path.
