# G-ACE Dev KB — Project Tree

This file is the navigation map for the repository. Update it when files are added, removed, moved, or when a major responsibility changes.

## Current repository tree

```text
gace-dev-kb/
├─ README.md
├─ docs/
│  ├─ CURRENT_DESIGN.md
│  ├─ PROJECT_TREE.md
│  └─ DESIGN_DELTA.md
├─ scripts/
│  └─ bootstrap-mvs-windows.ps1
├─ tests/
│  └─ verify-mvs-windows.ps1
└─ .gitignore                  # local untracked evidence observed; not yet verified in GitHub
```

## Responsibilities

### `README.md`
Mandatory entry point. Shows current validated status and links to design, tree, delta, and system documents.

### `docs/CURRENT_DESIGN.md`
Current design baseline and responsibility boundaries. Do not rewrite it merely to hide implementation drift.

### `docs/PROJECT_TREE.md`
Repository navigation and file/directory responsibilities.

### `docs/DESIGN_DELTA.md`
Append-only-style design change record: baseline difference, reason, evidence, and applying commit.

## Planned only after implementation requires them

The following paths are not considered implemented merely because they are planned:

```text
src/        # G-ACE-specific adapter/source only when required
tests/      # validation accompanying implementation
docs/future/ # future design material, including Astera-related design when migrated
```

Do not create placeholder subsystems solely to make the tree look complete.


## Local runtime boundary (verified outside repository source)

The validated Windows runtime is intentionally outside this Git tree:

```text
F:\G-ACE-KB\
├─ repo\
├─ data\
├─ runtime\
│  └─ mcp-vector-search\   # mcp-vector-search 4.1.14 isolated runtime
├─ assets\
└─ .venv\
```

Runtime packages, model caches, generated vector/index data, and manual site-packages compatibility patches are not represented as repository source. A repository-managed bootstrap/compatibility mechanism is still planned and must be added to this tree only when implemented.

### `scripts/bootstrap-mvs-windows.ps1`
Repository-managed Windows bootstrap for the pinned `mcp-vector-search` runtime and measured compatibility fixes.

### `tests/verify-mvs-windows.ps1`
Verifies the installed Windows compatibility state and CLI startup. A repository commit alone is not runtime PASS; execute this on the Master Windows runtime.
