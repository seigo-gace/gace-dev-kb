# CHAT ↔ GitHub ↔ G-ACE KB Bridge v1

## Purpose

Allow GPT CHAT to use the real Master-PC G-ACE KB without requiring a direct network connection from CHAT to the local MCP stdio process.

The v1 path is:

```text
GPT CHAT
  -> GitHub control branch request
  -> Master-PC bridge watcher
  -> existing local G-ACE KB MCP/search runtime
  -> bounded result JSON
  -> GitHub control branch result
  -> GPT CHAT reads and reuses the result
```

The bridge does not create a second KB, search engine, Knowledge Graph, or canonical knowledge store.

## Development and commonization order

This capability is developed and verified inside `gace-dev-kb` first.

```text
implement here
-> source/CI verification here
-> real Master-PC GitHub round-trip E2E here
-> confirm GPT CHAT can search and exact-fetch KB data here
-> only then register/migrate the proven capability through the GitHub Project
-> commonize it for other G-ACE projects
```

Do not move an unverified design into the shared GitHub Project as if it were a completed common capability.

## Shared cross-repository contract

The bridge is a single shared capability. Any G-ACE repository CHAT may submit a request to the same control branch. Caller repositories do not install their own watcher, MCP runtime, KB, or search index.

Optional caller-attribution fields are preserved in the result:

- `requester_repository`: GitHub `owner/repository` identity.
- `requester_project`: human/project control-plane name.
- `requester_change_unit`: bounded current work identifier.

These fields are audit metadata only. They cannot select an executable, command, path, MCP tool, Git ref, runtime, or output location.

Example:

```json
{
  "schema_version": "gace.kb.chat-request.v1",
  "request_id": "req-debugai-reuse-001",
  "action": "search",
  "query": "approval routing reusable logic",
  "mode": "hybrid",
  "limit": 10,
  "requested_by": "gpt-chat",
  "requester_repository": "seigo-gace/debug-ai",
  "requester_project": "DebugAI",
  "requester_change_unit": "shared-kb-reuse-proof"
}
```

## Control-plane contract

Dedicated branch:

```text
control/gace-kb-chat-bridge-v1
```

Request:

```text
.gace-control/requests/<request-id>.json
```

Result:

```text
.gace-control/results/<request-id>.json
```

Request schema:

```json
{
  "schema_version": "gace.kb.chat-request.v1",
  "request_id": "req-example-001",
  "action": "search",
  "query": "approval routing reusable logic",
  "mode": "hybrid",
  "limit": 10,
  "requested_by": "gpt-chat"
}
```

Supported actions are intentionally narrow:

- `search`: fixed MCP `search_code` invocation using `bm25`, `vector`, or `hybrid`.
- `exact`: exact `knowledge_id` lookup from the active reusable metadata plus related Case/Relationship sidecars.

The request cannot name an arbitrary executable, PowerShell command, Python module, MCP tool, filesystem path, Git ref, or output destination.

## Runtime implementation

- `scripts/gace_kb_chat_bridge.py`
  - validates request schema;
  - executes fixed MCP `search_code` for search requests;
  - returns bounded raw MCP result text;
  - exact-fetches one unique Knowledge Unit from Current metadata;
  - returns the matching structured metadata plus related Case/Relationship records.

- `scripts/process-gace-kb-chat-github-bridge-windows.ps1`
  - fetches only the dedicated control branch;
  - discovers request files with a strict path/name contract;
  - skips requests that already have results;
  - executes the bridge using the existing pinned local MCP runtime;
  - publishes one immutable result file back to the control branch through a temporary Git worktree;
  - never switches the main `F:\G-ACE-KB\repo` worktree to the control branch.

- `scripts/watch-gace-kb-chat-github-bridge-windows.ps1`
  - singleton polling watcher;
  - periodically invokes the one-shot processor;
  - writes bounded operational events under `F:\G-ACE-KB\data\knowledge-intake\chat-bridge`.

- `scripts/configure-gace-kb-chat-github-bridge-task-windows.ps1`
  - registers a current-user Limited AtLogOn task only after real one-shot E2E proves the round trip;
  - verifies watcher lock/log startup evidence.

## Security and authority boundaries

- GitHub is transport/control-plane evidence, not canonical KB truth.
- Current KB data under `F:\G-ACE-KB\data` remains runtime authority.
- ModuleCatalog remains producer authority for transported reusable assets.
- Search results never mutate canonical KB data.
- CHAT requests cannot execute arbitrary shell/code.
- Search is read-only.
- Exact retrieval is read-only.
- Result publication is limited to the dedicated control branch.
- Source branch, Main, ModuleCatalog, TGserver, Server runtime, and KB activation state are not mutated by a query.

## Completion gate

Do not claim CHAT reuse complete until all are observed on the intended Master PC:

1. source/CI gates PASS;
2. GPT CHAT creates a real GitHub `search` request;
3. Master-PC bridge consumes it and uses the real active KB MCP;
4. result is pushed back to GitHub;
5. GPT CHAT reads the result;
6. GPT CHAT creates a real `exact` request for a returned Knowledge Unit;
7. Master-PC bridge returns exact metadata + related Case/Relationship data;
8. GPT CHAT reads that exact result;
9. watcher Scheduled Task is installed and a new request completes without Master manually running the worker.

Only after step 9 may `CHAT_GITHUB_KB_REUSE=PASS` be claimed and the proven capability be proposed for GitHub Project commonization.
