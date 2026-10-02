# ModuleCatalog KBData receive-to-runtime boundary

## Responsibility boundary

ModuleCatalog owns reusable-asset creation, verification, search-ready KBData generation and transport.
G-ACE KB starts at **receipt of a transported `gace.reusable-asset.v1` delivery**.
The operational KB path must not clone/fetch ModuleCatalog or regenerate producer data.

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

The transport side must publish a complete delivery under `ready`. A directory without `manifest.json` is incomplete/pending and is not consumed.

The active KB is a **single-current-snapshot** runtime. Until the producer manifest carries explicit monotonic ordering / predecessor authority, more than one complete ready delivery is rejected with `MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY`. Directory names or filesystem time are never used to guess which Catalog snapshot is newer.

Before processing, the KB claims one complete delivery by moving it from `ready` to `processing`. Success moves it to `processed`; failure moves it to `failed` with a timestamp suffix. Successful archives contain `kb-active-receipt.json`. Failed archives contain machine-readable `kb-failure.json`.

If a prior process/PC interruption left exactly one delivery under `processing`, the next inbox run resumes that claimed delivery before considering new ready data. More than one stranded processing delivery fails closed and requires explicit recovery.

The transport side may use another delivery directory only when it explicitly invokes the receiver with `-DeliveryRoot`.

## Receive serialization

Two levels of serialization protect current KB state:

```text
F:\G-ACE-KB\data\knowledge-inbox\modulecatalog\processor.lock
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receive.lock
```

`processor.lock` serializes inbox claim/archive lifecycle. `receive.lock` serializes admission/index/cutover. Concurrent mutation attempts fail closed instead of racing two index/cutover operations.

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

The eight-field Knowledge Record remains only the legacy compatibility envelope. Full reusable-asset data is retained in `knowledge-metadata.jsonl` and deterministic Markdown search documents.

At acceptance time, the KB adds **runtime-only derived frontmatter** to its local Markdown projection. The transported/canonical ModuleCatalog bundle is not modified. Frontmatter contains stable reusable-asset / parent-asset / knowledge-kind / lifecycle / verification tags plus resolvable related-document links from transported relationships.

This allows the already-installed `mcp-vector-search 4.1.14` runtime to use the same accepted documents through:

```text
BM25
Vector semantic search
Hybrid search
Knowledge Graph DocSection/Tag relationships
MCP
```

The runtime gate therefore does not prove BM25 alone. Every Knowledge Unit remains exactly retrievable by stable ID through BM25, and one representative of every Knowledge Kind must pass natural-language retrieval through BM25, Vector and Hybrid modes. The MCP Knowledge Graph must report populated entities/doc sections and `kg_query` must find the accepted reusable corpus through the deterministic `gace-reusable-asset` tag.

## Operational pipeline

```text
transported delivery
→ ready
→ atomic claim into processing
→ acceptance / integrity verification
→ ACCEPTED receipt
→ local structured + KG-ready search projection
→ active-snapshot replacement candidate
→ staging search corpus
→ existing BM25 / Vector / Knowledge Graph index
→ repository-history MCP regression
→ existing accepted-asset MCP regression
→ all Knowledge Units exact BM25 retrieval
→ per-Knowledge-Kind BM25 / Vector / Hybrid natural retrieval
→ KG stats + reusable tag query
→ durable activation transaction journal
→ backup-backed current cutover
→ post-cutover MCP verification from the actual current path
→ atomic ACTIVE marker / receipt / runtime-state
→ clear transaction journal
→ archive delivery under processed
```

## Cutover crash recovery

In-process exceptions already roll back formal records, search runtime, reusable snapshot, activation marker and receipt. Hard process/PC termination is handled separately with:

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
records/*.md
delivery-manifest.json
acceptance-state.json
runtime-state.json
```

Search results therefore remain traceable to parent Asset, exact Catalog commit, source paths, verification, lifecycle, integrity and derivation boundary.

## Runtime health verification

`check-modulecatalog-kb-runtime-windows.ps1` is non-mutating. It cross-checks activation marker, ACTIVE receipt and current `runtime-state.json`; verifies formal/reusable/delivery hashes and record counts; and confirms MVS indexed-file cardinality without degraded vector-only warnings.

`-Deep` reruns repository-history MCP plus the full reusable MCP gate, including BM25 / Vector / Hybrid and Knowledge Graph checks.

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
existing BM25 / Vector / Hybrid retrieval gates PASS
existing Knowledge Graph gate PASS
post-cutover MCP PASS on the actual current path
delivery archived under processed
no unresolved activation transaction journal
```
