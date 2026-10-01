# Reusable Asset KB Acceptance Contract v1

## Purpose

G-ACE KB must accept and search **reusable development assets**, not only Skills.
ModuleCatalog is the canonical source. G-ACE KB stores a searchable projection that can be rebuilt from a pinned ModuleCatalog commit.

Reusable asset kinds include, but are not limited to:
`code`, `logic`, `architecture`, `design`, `contract`, `capability`, `test_case`, `evidence`, `pattern`, `workflow`, `configuration`, `integration`, `remediation`.

## Non-negotiable boundaries

- ModuleCatalog canonical data is never overwritten by KB-derived data.
- Missing facts stay missing/unknown; the KB importer never fabricates canonical fields.
- AI-derived metadata must be marked `data_class=derived` and include non-empty `derivation.derived_from`.
- A ModuleCatalog Asset and a searchable Knowledge Unit are different concepts. One Asset may produce many Knowledge Units.
- One export bundle may contain one Asset or many Assets; every Knowledge Unit must resolve to exactly one declared parent Asset.
- All Knowledge Units must retain a path back to the parent Asset and pinned ModuleCatalog commit.
- The existing eight-field G-ACE record remains a compatibility/search envelope. It is not the full reusable-asset model.

## Bundle layout

A v1 bundle is a directory inside a pinned ModuleCatalog checkout containing:

```text
knowledge-units.jsonl
manifest.json
asset.json       # single-Asset bundle
        OR
assets.jsonl     # multi-Asset / catalog-level bundle
```

Exactly one Asset descriptor form is allowed: `asset.json` or `assets.jsonl`, never both.
This allows a single reusable Asset to be exported independently, while also allowing a full Catalog batch such as the current 80-Asset set to be delivered as one verified bundle.

Additional canonical files may exist and must be listed in `manifest.json` when they are part of the bundle.

### asset.json — single Asset

Required example:

```json
{
  "schema_version": 1,
  "asset_id": "approval-route-resolver",
  "name": "Approval Route Resolver"
}
```

### assets.jsonl — multiple Assets

One JSON object per parent Asset. Each object uses the same identity contract as `asset.json`.

```jsonl
{"schema_version":1,"asset_id":"approval-route-resolver","name":"Approval Route Resolver"}
{"schema_version":1,"asset_id":"architecture-fit-evaluator","name":"Architecture Fit Evaluator"}
```

### knowledge-units.jsonl

One JSON object per independently searchable/reusable unit.
Required top-level fields:

```text
schema_version
knowledge_id
parent_asset_id
asset_kind
name
summary
verification
provenance
data_class
```

Recommended structured sections:

```text
classification
discovery
applicability
contract
constraints
composition
implementation
cases
verification
provenance
lifecycle
integrity
derivation
```

### Semantics

`classification`: domains/layers/languages/runtimes/tags.

`discovery`: purpose/responsibility/capabilities/keywords/semantic terms. This is used to discover what an asset can do.

`applicability`: use_when/do_not_use_when/preconditions/required_context/failure_conditions. This is used to decide whether the asset should be used for the current problem.

`contract`: inputs/outputs/required_fields/optional_fields/error_behavior/side_effects/mutation_authority.

`composition`: depends_on/requires/recommended_before/recommended_after/complements/alternative_to/conflicts_with/supersedes.

`implementation`: language/runtime/entrypoint/symbol/source_files/dependencies.

`cases`: verified reusable usage/test cases. Test data is both verification evidence and reusable knowledge.

`verification`: status/verified_at/validation_boundary/normal_test/user_test/known_unverified. PASS claims must not exceed the actual verified boundary. Admission requires `verification.status=verified`.

`provenance`: must contain `catalog.repository`, `catalog.commit`, and `catalog.asset_id`. `origin` should be preserved separately when known.

`lifecycle`: optional status from `experimental`, `verified`, `active`, `deprecated`, `superseded`, `retired`. Lifecycle describes asset state and is separate from the admission verification status.

`integrity`: asset hash, meta hash, manifest algorithm, or other integrity data.

`data_class`: `canonical` or `derived`.

`derivation`: required for derived units. `derived_from` must identify the canonical inputs used to produce the derived metadata.

## Search projection

For every Knowledge Unit, G-ACE produces:

1. `knowledge-records.jsonl` — legacy eight-field envelope for compatibility.
2. `knowledge-metadata.jsonl` — full structured reusable-asset data plus `_gace` projection metadata.
3. `records/*.md` — rich deterministic Markdown containing structured fields so BM25, Vector search, and Knowledge Graph can index capability, applicability, contract, cases, constraints, relationships, provenance, lifecycle, etc.

The eight-field envelope is:

```text
type=reusable_asset
repository=<catalog repository>
commit=<pinned catalog commit>
summary=<knowledge unit summary>
cause=""
fix=""
validation=<actual verification boundary>
source=<exact ModuleCatalog bundle + knowledge_id pointer>
```

`cause` and `fix` stay empty unless the canonical asset actually represents a cause/fix event. They are never fabricated for generic reusable assets.

## Integrity / admission gate

A bundle is rejected if any of these fail:

- manifest algorithm is not SHA-256;
- manifested file size or hash mismatches;
- `knowledge-units.jsonl` is absent/not manifested;
- neither or both of `asset.json` and `assets.jsonl` exist;
- the chosen Asset descriptor is not manifested;
- duplicate Asset IDs exist;
- duplicate Knowledge IDs exist;
- a Knowledge Unit references an undeclared parent Asset;
- `provenance.catalog.asset_id` differs from `parent_asset_id`;
- ModuleCatalog commit in provenance differs from checked-out HEAD;
- `verification.status` is not exactly `verified`;
- a derived unit lacks derivation sources;
- lifecycle value is unsupported.

## Windows / PC search validation

The generic Windows trial must:

```text
pinned canonical checkout (core.autocrlf=false)
→ bundle integrity verify
→ single-Asset or multi-Asset descriptor verify
→ structured import
→ one Markdown search record per Knowledge Unit
→ MVS index
→ exact knowledge_id retrieval for every unit
→ natural-language retrieval for at least one unit per asset_kind
→ PASS
```

Trial data lives outside the formal KB and reports `FORMAL_KB_UNCHANGED=YES`.

After isolated trial PASS, the formal promotion flow must:

```text
rebuild the already-verified base formal KB
→ import the pinned reusable-asset bundle
→ combine legacy envelopes without losing structured metadata/corpus
→ reindex under the proven Windows safety envelope
→ re-run repository-history regression
→ re-run existing accepted-skill regression when present
→ run reusable-asset MCP exact/natural retrieval
→ PASS
```

## Current boundary

This contract makes the KB **ready to receive** a ModuleCatalog Reusable Asset Bundle, including a bulk multi-Asset export. It does not claim that the current ModuleCatalog 80-Asset migration branch already emits this exact bundle. Producer-side export remains ModuleCatalog work. Once an exact bundle path, pinned commit, and expected Knowledge Unit count are available, the KB side can run isolated Windows trial first and formal promotion second.
