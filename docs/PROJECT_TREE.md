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
└─ .gitignore                  # to be added with implementation bootstrap
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
