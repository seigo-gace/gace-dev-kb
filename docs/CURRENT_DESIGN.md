# G-ACE Dev KB — Current Design Baseline

## 1. Purpose

G-ACE Dev KB is the runtime/search layer for reusing development knowledge and reusable development assets across G-ACE work.

Reusable scope is not Skill-only. It includes repository history, code, logic, architecture, design, contracts, capabilities, tests/cases, evidence, patterns, workflows, configuration, integration/remediation knowledge, and future reusable asset kinds.

Authority is source-specific:

- committed repository evidence remains authoritative for repository-derived history;
- ModuleCatalog is authoritative for Catalog reusable-asset content up through verified/search-ready KBData generation and transport;
- G-ACE KB owns receipt onward and never silently upgrades derived runtime data into producer canonical truth.

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

Existing runtime capabilities used by formal knowledge are:

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

This contract remains a compatibility/search envelope. It is **not** allowed to truncate rich reusable-asset data.

For generic reusable assets, unsupported `cause`/`fix` remain empty rather than being fabricated.

## 5. Repository-derived knowledge path

```text
Git committed evidence
→ gace_knowledge_adapter.py
→ eight-field records
→ deterministic Markdown
→ formal KB runtime
→ BM25 / Vector / KG / MCP
```

Rules remain:

- committed Git evidence is authority;
- missing evidence stays empty;
- tracked dirty state blocks normal durable export;
- durable export defaults to full reachable history;
- formal repository knowledge is pinned to an explicit revision (current historical baseline: `origin/main`);
- generated data/indexes stay outside Git source.

## 6. Previously validated verified-source path

The earlier verified DebugAI ModuleCatalog source established that the formal KB can preserve multiple distinct reusable records from one source commit and retrieve them through the real Windows MCP runtime.

Validated baseline before the generalized Catalog receive path:

```text
repository records: 94
verified external records: 13
formal records: 107
formal corpus/index: 107/107
MCP repository-history retrieval: PASS
MCP all-13 reusable retrieval: PASS
natural reusable discovery: PASS
```

This remains historical evidence. The generalized ModuleCatalog snapshot path replaces the legacy 13-record Catalog snapshot when the full transported Catalog snapshot is eventually activated; it does not keep both as simultaneous Current Catalog versions.

## 7. ModuleCatalog producer / KB consumer boundary

### ModuleCatalog responsibility

```text
Reusable Asset creation
→ verification
→ Canonical / Derived boundary
→ search-ready gace.reusable-asset.v1 KBData
→ integrity manifest
→ transport to Master PC KB boundary
```

### G-ACE KB responsibility

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
```

The operational KB path never clones/fetches ModuleCatalog and does not run the producer exporter to manufacture its own operational payload. Cross-repository producer execution in CI is contract verification only.

## 8. Transport contract

Accepted producer format:

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

Full cryptographic/schema/provenance checks remain the authoritative admission gate after claim.

## 9. Reusable projection schema v2

Accepted Catalog data is projected locally into:

```text
knowledge-records.jsonl       # compatibility envelope
knowledge-metadata.jsonl      # full structured reusable metadata
relationships.jsonl           # structured relationship authority
cases.jsonl                   # structured reusable/test-case authority
records/*.md                  # existing MVS runtime search projection
```

Every searchable Knowledge Unit keeps its parent Asset and exact Catalog commit/source path.

Canonical transport data is not modified. Runtime-only frontmatter/tags/related links are generated only in the local derived Markdown projection.

## 10. Search and Knowledge Graph use

Reusable data is not merely stored. Activation must prove use through the existing runtime:

```text
all Knowledge Units exact BM25 retrieval
representative each Knowledge Kind via BM25 / Vector / Hybrid
Case ID retrieval
Relationship ID retrieval
KG reusable-data tag query
KG relation/dependency/containment projection where canonical relations exist
existing repository-history retrieval regression
post-cutover retrieval from actual Current runtime path
```

Structured relationship/case sidecars survive into Current independently of the MVS projection and are hash/count checked during acceptance, activation and health.

## 11. Single-Current snapshot rule

Normal runtime search has one Current ModuleCatalog reusable snapshot.

A newer accepted snapshot replaces the prior Catalog snapshot while preserving non-Catalog repository/history knowledge. Historic Catalog snapshots remain evidence/backups rather than coexisting as normal Current search candidates.

Until producer transport includes explicit sequence/predecessor authority, multiple complete `ready` deliveries are rejected rather than ordered by directory name, filesystem time or Git commit timestamp.

## 12. Receive reliability

Locks:

```text
receiver-service.lock
processor.lock
receive.lock
```

They serialize watcher, claim/archive, and admission/index/cutover/health respectively.

Operational failure handling:

- exactly one stranded `processing` delivery resumes;
- permanent failure archives under `failed` with machine-readable evidence and receiver logs;
- transient busy/health/timeout remains `RETRYABLE` in processing;
- ACTIVE-but-not-archived remains `ACTIVE_ARCHIVE_PENDING`;
- duplicate delivery ID replay preserves prior processed archive and uses a unique replay archive;
- receiver timeout is bounded (default 7200 seconds);
- Windows timeout kills the complete receiver process tree to avoid orphan MVS/Python mutation after timeout.

## 13. Atomic activation and crash recovery

Before destructive Current cutover, activation writes a durable PREPARED journal:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\activation-transaction.json
```

The journal records current/backup/staging paths. Recovery occurs before another activation:

- if marker + receipt + runtime-state already prove target ACTIVE, finalize;
- otherwise restore last known Current from backups;
- missing recovery authority fails closed.

Current authority is not a receipt alone. These must agree:

```text
modulecatalog-reusable-active.json
current reusable runtime-state.json
receipts\<catalog-commit>.json
```

## 14. Continuous receiver

`watch-modulecatalog-kb-inbox-windows.ps1` provides a singleton polling receiver with bounded JSONL logging and heartbeat throttling.

`configure-modulecatalog-kb-receiver-task-windows.ps1` can register it as a current-user Limited AtLogOn task. Task settings include bounded restart attempts (default 12, one-minute interval) for transient startup failures such as delayed F: availability.

Repository implementation does not itself install that task. Installation is a separate Master-PC action after the real runtime gate.

## 15. Runtime health

`check-modulecatalog-kb-runtime-windows.ps1` verifies marker/receipt/runtime-state authority, formal/reusable/delivery/relationship/case hashes and counts, Current corpus tags, MVS indexed cardinality and known degraded-search warnings.

`-Deep` reruns repository-history and reusable BM25/Vector/Hybrid/KG MCP gates.

Health checks serialize against receive/cutover so they cannot certify a runtime while it is being replaced.

## 16. Storage boundary

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

Processed/failed delivery evidence has no automatic deletion policy in this design. Retention cleanup must be an explicit later policy rather than silent destructive behavior.

## 17. Current implementation boundary (2026-10-02)

### Proven on Master Windows before generalized transport

- pinned MVS 4.1.14 Windows compatibility: PASS;
- formal 107-record baseline index/retrieval: PASS;
- repository-history MCP: PASS;
- 13 verified reusable records MCP + natural discovery: PASS.

### Implemented and GitHub-CI validated on the generalized receive branch

- real current ModuleCatalog `gace.reusable-asset.v1` producer compatibility contract;
- current regression boundary: 80 Assets / 720 Knowledge Units / 160 cases;
- admission/integrity/idempotent replay validation;
- projection schema v2;
- rich runtime corpus + relationship/case retention;
- partial transport safety;
- unsafe transport-path preflight protection;
- inbox claim/resume/retry/failure/archive lifecycle;
- timeout/retry + process-tree cleanup;
- duplicate delivery replay archive preservation;
- single-Current replacement logic;
- preserved non-Catalog runtime corpus;
- runtime filename/link alignment;
- activation transaction rollback/recovery;
- receiver/health serialization;
- continuous receiver and scheduled-task configuration source;
- existing BM25/Vector/Hybrid/KG/MCP reusable gates.

### Not yet claimed as real-PC PASS

The generalized transported Catalog snapshot has not yet been genuinely delivered and activated through the installed Master-PC MVS runtime. Scheduled receiver task installation has also not been performed.

Those environment-specific gates remain required before PR #3 can be treated as complete/merge-ready.

## 18. Future boundary

TGserver-linked generic knowledge processing/admission and unrelated Astera-oriented KB architecture remain separate scopes unless explicitly integrated through a verified contract.

Do not infer those systems from the ModuleCatalog reusable-asset intake path.
