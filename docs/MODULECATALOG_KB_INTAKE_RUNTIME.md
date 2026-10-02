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

The transport side must publish a complete delivery under `ready`. A directory without `manifest.json` is treated as incomplete/pending and is not consumed.

The active KB is a **single-current-snapshot** runtime. The current producer manifest does not contain a monotonic sequence / predecessor authority, so the inbox processor refuses more than one complete ready delivery at once. This prevents an older valid Catalog snapshot from becoming current merely because of directory sort order. Transport should therefore expose exactly one current activation candidate in `ready` until an explicit ordering authority is added to the delivery contract.

Before processing, the KB atomically claims the ready directory by moving it to `processing`. A successful ACTIVE delivery is moved to `processed`. A failed delivery is moved to `failed` with a timestamp suffix. No successful delivery is left in `ready` and repeatedly reactivated.

The transport side may use another delivery directory when it explicitly invokes the receiver with `-DeliveryRoot`.

## Receive serialization

Only one receive/activation operation may change the KB runtime at a time.
`receive-modulecatalog-kbdata-windows.ps1` holds an exclusive file lock under:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receive.lock
```

A concurrent receiver fails closed with `MODULECATALOG_RECEIVER_BUSY` instead of running two index/cutover operations against the same current KB.

## Receipts

KB receipts are written under:

```text
F:\G-ACE-KB\data\knowledge-intake\modulecatalog\receipts\<catalog-commit>.json
```

Receipt states:

```text
ACCEPTED = transport payload passed admission and local projection was built.
ACTIVE   = payload passed the existing KB runtime gates and is the current searchable snapshot.
```

Re-delivery of the exact already-ACTIVE Catalog commit is idempotent and must not downgrade it back to ACCEPTED.

## Operational pipeline

```text
transported delivery
→ ready
→ claim into processing
→ acceptance/integrity verification
→ ACCEPTED receipt
→ local structured projection
→ active-snapshot replacement candidate
→ staging search corpus
→ existing BM25 / Vector / Knowledge Graph index
→ repository-history MCP regression
→ existing accepted-asset MCP regression
→ new reusable-asset exact + natural MCP retrieval
→ backup-backed current cutover
→ post-cutover MCP verification from the actual current path
→ ACTIVE receipt
→ archive delivery under processed
```

A failure before cutover leaves the current KB unchanged. A failure after cutover begins triggers rollback to the prior formal records/search runtime/current reusable snapshot. The failed transported bundle is preserved under `failed` for diagnosis.

## Data retention

The active runtime keeps one current ModuleCatalog reusable snapshot rather than accumulating old Catalog commits in the active search index.
Repository-history knowledge and non-reusable accepted source types are preserved.
The current reusable structured snapshot retains:

```text
knowledge-records.jsonl
knowledge-metadata.jsonl
records/*.md
delivery-manifest.json
acceptance-state.json
```

Search results therefore remain traceable to the parent Asset, exact Catalog commit, source paths, verification, lifecycle, integrity and derivation boundary.

## Commands

Process one delivered bundle through the full KB runtime:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\receive-modulecatalog-kbdata-windows.ps1 `
  -DeliveryRoot '<transported-delivery-directory>'
```

Process the one complete current delivery in the default inbox:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\process-modulecatalog-inbox-windows.ps1
```

## Completion definition

A transported Catalog payload is not operational merely because it was copied or accepted.
Completion requires an `ACTIVE` receipt after the existing KB runtime has indexed it and post-cutover MCP retrieval succeeds. For inbox operation, the transported directory must also have moved from `processing` to `processed`.
