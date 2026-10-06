# ModuleCatalog KB operational retention

## Purpose

The ModuleCatalog receive pipeline creates operational evidence and rollback material on every successful or failed activation. These files are not part of the permanent canonical producer record; unbounded retention would eventually consume the Master PC storage.

Retention therefore runs as a KB-side operational responsibility after receipt. It never changes ModuleCatalog canonical data and never deletes the Current active snapshot.

## Default policy

The continuous receiver invokes `scripts/prune-modulecatalog-kb-retention-windows.ps1` every 3600 seconds by default.

Default retained counts:

```text
activation rollback backups     3 per backup class
processed delivery archives    20
failed delivery archives       20
accepted delivery snapshots     5
failed search-runtime backups   2
```

Per-commit receipt JSON files are intentionally retained because they are small audit records.

## Protected authority

Retention acquires the same `receive.lock` used by admission/index/cutover. It skips cleanup while an activation transaction journal exists.

The following are protected regardless of age/rank:

```text
Current ACTIVE accepted snapshot
ACTIVE marker backupFormal
ACTIVE marker backupSearch
ACTIVE marker backupReusable when recorded
immediate reusable rollback sibling derived from backupSearch timestamp for older marker schema
```

This preserves the current runtime and its immediate rollback authority even when those paths are older than other retained evidence.

## Pruned operational material

Retention may remove only known paths below `F:\G-ACE-KB\data`:

```text
knowledge-search.previous-*
knowledge-search.failed-*
knowledge-records\formal-kb.previous-*.jsonl
knowledge-sources\accepted\modulecatalog-reusable.previous-*
knowledge-intake\modulecatalog\accepted\<old-commit>
knowledge-inbox\modulecatalog\processed\<old-delivery>
knowledge-inbox\modulecatalog\failed\<old-delivery>
```

With `receive.lock` held and no activation journal, stale transaction scratch may also be removed:

```text
knowledge-search.reusable-staging
knowledge-sources\accepted\modulecatalog-reusable-staging
knowledge-records\formal-kb.reusable-next.jsonl
knowledge-records\formal-kb.reusable-base-next.jsonl
```

The cleanup script checks that every deletion candidate remains under its allowed root before deleting it.

## Receiver integration

`watch-modulecatalog-kb-inbox-windows.ps1` runs retention on its configured cadence and records `RETENTION_PASS` / `RETENTION_FAILED` in the receiver service JSONL.

`configure-modulecatalog-kb-receiver-task-windows.ps1` persists the retention cadence and retained counts into the Windows Scheduled Task command line, so reboot/logon does not silently revert to different retention behavior.

Use `-RetentionSeconds 0` only for isolated test environments that intentionally disable retention.

## Manual dry run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File F:\G-ACE-KB\repo\scripts\prune-modulecatalog-kb-retention-windows.ps1 `
  -DryRun
```

A dry run prints deletion candidates without removing them.

## Verification

`tests/test_modulecatalog_retention.ps1` verifies bounded counts, stale scratch cleanup, idempotency, Current accepted-snapshot protection, explicit rollback protection, and compatibility with older ACTIVE markers that do not contain `backupReusable`.

This retention policy is operational housekeeping only. It does not replace Git history, ModuleCatalog canonical history, or the Current KB authority files.
