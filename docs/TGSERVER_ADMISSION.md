# TGserver evidence admission and KB activity

This is an explicit integration extension to the preserved Current Design baseline. Git remains Source authority, TGserver remains raw evidence authority, and `mcp-vector-search` remains the existing index/search/MCP engine. No second KB, raw-log import store, model download or MCP server is introduced.

## Explicit knowledge admission

`scripts/promote_tgserver_knowledge.py` accepts one selected `KNOWLEDGE_CANDIDATE` from trusted ZERO search evidence. It requires:

- canonical schema/privacy, redacted content and no internal reasoning;
- positive Telegram raw correlation and matching occurrence/acceptance timestamps;
- exact repository identity from actual local Git remote;
- full existing Git commit SHA and committed test-blob references;
- actual GitHub Actions readback from the expected repository with that exact SHA, completed/success;
- explicitly recorded knowledge type, summary, cause/fix where relevant, validation and reuse scope.

The existing `KnowledgeRecord` fields are retained. The Source field binds Git revision, TGserver event ID, raw correlation, verified CI and reuse scope. No missing cause/fix/validation is invented. Ordinary FAILED/tool/conversation events do not become KB records automatically. A supplied artifact/correlation alone does not independently prove live Telegram retrieval or the semantic truth of a cause/fix; those are retained provenance/validation limits, not silently upgraded facts.

Use trusted TGserver central Reader/API evidence as the input, select the exact event ID, provide the source repository and exact CI run ID. Generated output stays outside both KB/source Git roots. Repeated identical output is accepted; conflicting output fails closed. Existing multi-repository combining also fails closed if repository/commit/type matches but evidence differs, instead of silently dropping a promoted record.

```text
trusted TGserver search evidence + explicit candidate
 -> local Git identity/commit/test evidence + GitHub exact-revision CI readback
 -> initial KnowledgeRecord JSONL outside Git
 -> existing combine_knowledge_records / render_knowledge_corpus
 -> existing MVS generated knowledge index
 -> existing MCP client/cross-repository retrieval gates
```

Render promoted records into a deliberately selected generated corpus; the normal Windows exporter still exports Git history and does not automatically discover a separately generated admission file. A combined source must contain the admitted record before indexing. Avoid replacing the full-history corpus with a single record. Existing MVS wrappers and MCP regression remain the verification authority on the Master PC.

## PC KB Development Events

`scripts/emit_development_event.py` reads actual Git repository identity/HEAD and captures a KB activity event into the shared stdlib SQLite outbox. `scripts/devlog_producer.py` is a byte-identical vendored copy of TGserver `collector/devlog_producer.py`. It redacts before durable insert, freezes payload/ID/time, signs fresh transport timestamps, refuses redirects and retains pending events after failure. No direct TGserver path is added.

Outbox is outside Git, for example under the established `F:\G-ACE-KB\data` boundary. Contract names: `DEVLOG_GATEWAY_URL`, `DEVLOG_HMAC_SECRET`, `DEVLOG_SOURCE_INSTANCE`. Values must arrive through an approved runtime injection/secret contract; no credential is registered/copied by this Source change. Retry pending events with the producer's no-input flush mode. A durable Gateway ACK is separate from Telegram/index/knowledge completion.

The current TGserver map has no `seigo-gace/gace-dev-kb` entry. PC activity delivery is therefore blocked on a formal mapping and approved source route. P numbers/topics are not invented. The PC F: runtime is not reachable directly from the VPS; actual PC/MCP availability must be verified through the approved bridge/client.

## Retention / backup

SQLite outbox is owner-controlled recovery state with WAL/synchronous FULL, not cache. Pending/unknown events must remain. No automatic purge/rotation or source raw backup is introduced. Backup should use SQLite's consistent backup API followed by integrity check/reopen/retry verification; live PC backup scheduling/restore is NOT_VERIFIED. Existing KB generated data/index backup remains the owning runtime responsibility.

## Verification boundary

Stdlib tests verify admission rejection, Git revision/test binding, privacy, renderer compatibility, conflicting-evidence rejection and actual HTTP/SQLite producer retry/reopen. GitHub CI verifies these source contracts. Existing Master Windows MVS/MCP/cross-repository results remain historical evidence for the unchanged engine; they are not claimed as fresh evidence for TGserver-promoted knowledge.

Actual trusted TGserver candidate admission, PC indexing, MCP retrieval of that candidate and reuse in another Project remain NOT_VERIFIED until performed. Do not infer those gates from a local test record or a successful renderer.
