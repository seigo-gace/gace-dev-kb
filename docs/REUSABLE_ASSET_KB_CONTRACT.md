# Reusable Asset KB Acceptance Contract v1

## Purpose

G-ACE KB accepts and searches **reusable development assets**, not only Skills.
ModuleCatalog is the canonical repository. G-ACE KB stores a searchable runtime projection that can be rebuilt from a pinned ModuleCatalog commit.

Reusable value includes code, logic, architecture, design, contracts, capabilities, test cases, evidence, patterns, workflows, configuration, integrations, remediation knowledge, and future reusable asset kinds.

## Producer / consumer boundary

ModuleCatalog owns canonical asset creation, verification, provenance, integrity, and export.
G-ACE KB owns admission, searchable projection, BM25 / Vector / Knowledge Graph indexing, MCP retrieval, and PC-side runtime use.

The KB must never rewrite ModuleCatalog canonical data. Missing facts remain missing or unknown. Derived information remains visibly derived.

## Actual ModuleCatalog export format

The current producer contract is `gace.reusable-asset.v1`.
A full export is generated outside the ModuleCatalog working tree and has this layout:

```text
<export-root>/
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

The top-level `manifest.json` identifies the exact catalog repository and commit and declares each exported Asset with its source `assetHash`, generated `bundleHash`, Knowledge Unit count, relationship count, and case count.

Each per-Asset `manifest.json` uses SHA-256 and covers:

```text
asset.json
knowledge-units.jsonl
relationships.jsonl
cases.jsonl
```

The KB importer verifies declared size/hash values, the recomputed bundle hash, source asset hash, catalog repository, catalog commit, asset id, and asset path before admission.

## Asset and Knowledge Unit are different concepts

A ModuleCatalog Asset is the canonical package.
A Knowledge Unit is an independently searchable/reusable projection from that Asset.

One Asset may therefore produce many Knowledge Units:

```text
Asset
├─ overview/discovery
├─ documentation
├─ design
├─ logic
├─ architecture
├─ evidence
├─ code unit(s)
└─ test-case unit(s)
```

Every Knowledge Unit keeps `parent_asset_id`, so any search result can return to the parent Asset and exact pinned ModuleCatalog commit.

## asset.json

`asset.json` is the structured Reusable Asset Schema v1 projection.
The KB requires these structured sections:

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

### identity

Contains Asset identity such as:

```text
asset_id
name
version
asset_kind
symbol
```

`asset_kind` may be `unknown` when ModuleCatalog has no canonical basis for a stronger classification. The KB does not invent a better value.

### classification

Searchable classification data:

```text
domains
layers
languages
runtimes
tags
```

These values remain separate semantic fields; they are not collapsed into one generic tag list.

### discovery

Used to discover what the parent Asset is for:

```text
summary
purpose
responsibility
capabilities
keywords
semantic_terms
```

Canonical values are preserved. Deterministically derived keywords remain identifiable through derivation metadata.

### applicability

Used to decide whether an Asset should be used:

```text
use_when
do_not_use_when
preconditions
required_context
failure_conditions
```

The current producer deliberately leaves these empty when the current canonical Asset does not contain enough information. The KB must preserve that boundary rather than infer canonical facts.

### contract

Used to understand execution/reuse compatibility:

```text
status
inputs
outputs
required_fields
optional_fields
error_behavior
side_effects
mutation_authority
```

Unknown or not-recorded values remain unknown/not recorded.

### composition

Used for combination and Knowledge Graph relations:

```text
depends_on
requires
recommended_before
recommended_after
complements
alternative_to
conflicts_with
supersedes
```

### implementation

Used to locate real reusable implementation:

```text
languages
runtimes
entrypoints
source_files
dependencies
```

### verification

Admission requires:

```text
verification.status = verified
```

Normal/User evidence, verified timestamp, validation boundary and known-unverified scope are retained. The KB must never widen a PASS claim beyond the producer's evidence boundary.

### provenance

Both provenance layers are retained:

```text
origin.repository / origin.commit
catalog.repository / catalog.commit / catalog.asset_path / catalog.asset_id
```

Origin and Catalog provenance are different facts and must not be collapsed.

### lifecycle

Lifecycle remains independent from verification status.
It is searchable so retired/deprecated/superseded assets can be distinguished from current ones.

### integrity

The KB retains source Asset hash, meta hash, manifest algorithm/file data, plus generated bundle hash.

### derivation

Canonical sources and derived fields remain separate. Derived data never silently becomes canonical truth.

## knowledge-units.jsonl

The actual producer emits one object per independently searchable unit with:

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

`knowledge_kind` is the main search-unit type, for example:

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

This is intentionally distinct from the parent Asset's `asset_kind`.
The KB indexes both.

## relationships.jsonl

Relationships are first-class reusable data.
Current producer relations include Asset → Knowledge Unit `contains` edges and resolvable canonical `depends_on` edges.

The KB verifies that every relationship target resolves to a declared Asset or Knowledge Unit before admission.
These relations are retained for current Markdown search and future stronger Knowledge Graph use.

## cases.jsonl

Test data is both verification evidence and reusable knowledge.
Current Case records preserve:

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

When the producer cannot deterministically extract scenario/input/actual, the values remain null and `source_test` plus real test content remain available. The KB must not invent them.

## KB search projection

For each imported Knowledge Unit, G-ACE generates:

1. `knowledge-records.jsonl` — existing eight-field compatibility envelope.
2. `knowledge-metadata.jsonl` — full reusable-asset search metadata, including parent Asset fields and Knowledge Unit content.
3. `records/*.md` — deterministic rich search documents for BM25 / Vector / Knowledge Graph indexing.

The eight-field envelope remains only a compatibility layer:

```text
type=reusable_asset
repository=seigo-gace/modular-catalog
commit=<pinned catalog commit>
summary=<parent summary + unit title + knowledge kind>
cause=""
fix=""
validation=<actual parent Asset verification boundary>
source=modulecatalog:<repo>@<commit>#assets/<asset-id>::<knowledge-id>
```

`cause` and `fix` stay empty unless the canonical source really represents a cause/fix event. They are never fabricated for generic reusable assets.

The rich Markdown exposes searchable meaning including:

```text
Knowledge ID
Parent Asset ID / name / version / asset kind
Knowledge Kind
Data Class
Lifecycle
Verification
Summary / Purpose / Responsibility
Capabilities / Keywords / Semantic Terms
Domains / Layers / Languages / Runtimes / Tags
Applicability
Contract
Dependencies and composition relations
Source paths
Catalog commit
Asset hash
Knowledge content
Matching reusable cases
Relationships
Provenance
```

## Admission gates

The full ModuleCatalog export is rejected if any of the following fail:

```text
top-level format/schema/repository/commit
assetCount and actual assets/ directory set
unique Asset IDs
per-Asset SHA-256 manifest
per-Asset bundle hash
source Asset hash
required bundle files
Asset schema sections
verification.status=verified
Catalog provenance / commit / asset path
unique Knowledge IDs
parent_asset_id integrity
per-Asset Knowledge Unit / relationship / case counts
relationship node resolution
expected Asset count
expected total Knowledge Unit count
```

This is fail-closed. Partial admission is not silently accepted.

## Windows / PC isolated trial

Before formal KB promotion, the exact pinned ModuleCatalog commit must pass an isolated trial:

```text
pinned ModuleCatalog checkout (core.autocrlf=false)
→ run producer export API outside the catalog tree
→ verify 80-Asset/full export manifest
→ import into G-ACE reusable projection
→ verify Knowledge Unit / metadata / corpus counts
→ isolated MVS project
→ BM25 / Vector / KG index
→ exact MCP retrieval for every Knowledge Unit
→ natural-language MCP retrieval for at least one unit of every knowledge_kind
→ PASS
```

The trial uses only:

```text
F:\G-ACE-KB\data\modulecatalog-reusable-trial
```

and verifies the formal KB JSONL hash is unchanged.

## Formal promotion boundary

Only after the isolated trial passes may the same pinned export be combined into the formal KB.
Formal promotion must preserve existing repository-history and previously accepted reusable data, reindex under the proven Windows memory-safety envelope, rerun existing retrieval regressions, and then run the reusable-asset MCP gate.

## Current producer boundary

ModuleCatalog PR #4 currently provides Reusable Asset Schema v1 and the deterministic export implementation on branch `feat/reusable-asset-schema-v1-20261001` at commit `f83461b79344e18dda145978fec5cb8f62896ad1`.
Its recorded producer regression is:

```text
80 Assets
720 Knowledge Units
160 normalized test-case records
```

That branch is not treated as merged canonical `main`; the KB trial must pin the exact approved producer commit supplied for the run.

## Non-negotiable rule

G-ACE KB is not a Skill-only KB.
Any reusable Code, Logic, Architecture, Design, Contract, Capability, Test Case, Evidence, Pattern or other verified development asset may be indexed when ModuleCatalog can provide it without fabricating canonical facts.
