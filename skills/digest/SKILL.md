---
name: digest
description: "Use when user requests /digest, a daily summary, or a research report of session work."
---

# Digest

Generates daily reports and research reports. Both source directly from jsonl — daily by timestamp slicing, research by topic scanning — with sub-agent delegation for the slicing / scanning work. MEMORY.md provides background context.

Read `$PLUME_ROOT/config.yml` for `locale` (timezone, language), `digest` (default_scope).

> A report MUST cover ALL active sessions within scope. Always read source files — never summarize from memory alone.

> **Ask-Before-Persist interaction**: digest's output paths are pre-configured via `config.yml` and fixed by convention (`data/journal/YYYY-MM-DD.md`, `data/reports/<slug>.md`). Treat this as the user having pre-confirmed the write destination at install time — no per-invocation path confirmation needed. The `/digest` command is itself the explicit trigger; cron / `-p` mode cannot confirm interactively anyway. The Report Update prompt (merge / overwrite / save-as-new / cancel) serves as the per-invocation gate for overwrites.

---

## /digest daily [YYYY-MM-DD] [--scope keyword]

Generate a daily report. Default date: today.

### Scope

Resolution: `--scope` arg > `config.yml default_scope` > ask user.
Matching: Claude project slug **contains** scope keyword as substring.

### Steps

**Step 1 — Enumerate main session jsonls (top-level only)**

Find scoped project dirs in `~/.claude/projects/`. For each project, enumerate **only top-level `*.jsonl`** as main session files. Do NOT recurse — `subagents/agent-*.jsonl` are sub-agent traces and must be excluded.

> ⚠️ Do NOT use the Glob tool for this step. Glob recurses into subdirectories and has a result cap; in projects with many subagent files, truncation will silently drop the most recent main sessions. Always enumerate via Bash/Python with non-recursive listing:

```bash
# Preferred: one-shot enumeration with start timestamp + mtime, sorted by mtime desc
for f in ~/.claude/projects/<slug>/*.jsonl; do
  start=$(head -1 "$f" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('timestamp',''))")
  mtime=$(stat --format=%Y "$f")
  echo "$mtime $start $(basename $f)"
done | sort -rn
```

For each main session jsonl, determine if the session was **active on the target date** using interval overlap:

1. **session_start**: first line `timestamp` field (ISO 8601 UTC)
2. **session_end**: file mtime (`stat --format=%Y` or `os.path.getmtime()`)
3. **target window**: read `digest.cron_time` from config (default `06:00`). Window = target date `cron_time` ~ next day `cron_time` (in config timezone, converted to UTC)
4. **Match condition**: `session_start < target_end AND session_end >= target_start`

This correctly captures cross-day sessions. Do NOT rely on mtime alone — it misses sessions that started on the target date but are still active later.

**Sanity check**: After enumeration, verify the count matches a direct directory listing (`ls ~/.claude/projects/<slug>/*.jsonl | wc -l`). If a session you'd expect (e.g. the current one) is missing, re-enumerate — never trust a partial list.

Display matched projects + session counts to user for confirmation (skip if cron/`-p` mode).

**Step 2 — Delegate slicing to sub-agents (Phase B)**

**Main Claude does NOT slice jsonl directly.** Slicing is repetitive data-processing work that pollutes the main context and risks leaking temp scripts into the user's workspace. Delegate to sub-agents following Tier 0 principle 7 (Delegate with Intent).

jsonl is the authoritative source. Each line carries its own `timestamp` field. The jsonl is append-only and spans the complete session from first message to last — a cross-day session appears in multiple daily reports with disjoint slices. **Tail-based reading is wrong for cross-day sessions.** Per-line timestamp filtering is the only correct mechanism.

### Scratch directory (mandatory)

Before dispatching any sub-agent, main Claude creates a unique scratch directory for this digest invocation:

```
DIGEST_SCRATCH_ROOT = $PLUME_ROOT/data/.tmp/digest-<YYYYMMDD-HHMMSS>/
mkdir -p "$DIGEST_SCRATCH_ROOT"
```

This path is the **only** location sub-agents may create files in. The L3 inline fallback also uses it. After Step 3 finishes (report written or aborted), main Claude **must** `rm -rf "$DIGEST_SCRATCH_ROOT"`.

### Batching rule

- `N ≤ 5` sessions → one sub-agent per session, dispatched in parallel (single message, multiple Agent tool calls)
- `N > 5` → group into `ceil(N/5)` sub-agents, each handling 3–5 sessions

Use `subagent_type: "general-purpose"` with `model: "haiku"` for cost efficiency.

### Agent prompt contract

Each sub-agent receives:

- **Goal**: Slice the given jsonl file(s) to the timestamp window and extract a structured summary.
- **Context**: time window `[target_start, target_end)` in UTC ISO 8601; list of jsonl absolute paths; the mandatory scratch directory path `DIGEST_SCRATCH_ROOT`.
- **Scope**: read jsonl line-by-line, filter by per-line `timestamp`, summarize the in-window slice only. Do not read anything outside the paths given.
- **File-write restriction (HARD RULE)**: you **MUST NOT** create, write, or modify any file outside `DIGEST_SCRATCH_ROOT`. Any temp scripts, intermediate outputs, or helper files go inside that exact directory and nowhere else. Creating files in the user's main workspace (including `/root/plume/`, `/tmp/`, or the current working directory) is a protocol violation — if you cannot comply, return an error instead.
- **Return format**: a single fenced ```json block with the exact schema below. No prose outside the block.

```json
{
  "sessions": [
    {
      "session_id": "<filename without .jsonl>",
      "project_slug": "<parent dir name>",
      "window_start": "<UTC ISO>",
      "window_end": "<UTC ISO>",
      "line_count": 123,
      "summary": "<2-6 sentence natural-language summary focused on user requests, decisions, files modified, outcomes>",
      "files_modified": ["<absolute path>", "..."],
      "decisions": ["<key decision 1>", "..."],
      "is_self_referential_digest": false
    }
  ],
  "schema_fingerprint": "timestamp,type,role,message.content[].text"
}
```

`is_self_referential_digest: true` when the session's first user message is a `/digest` invocation (contains `<command-name>digest</command-name>` or starts with `/digest`). Main Claude uses this flag in Step 3 to skip the session without emitting any report entry.

`schema_fingerprint` lists the fields the agent actually found in the jsonl. Main Claude compares against `expected_fields = {timestamp, type, role, message.content[].text}` and flags drift (see Fallback Chain below).

### Cross-check after agents return

For each session with `files_modified`, verify with `stat` that the file mtimes fall within the window. Catches paraphrasing errors in agent summaries. Also read MEMORY.md for project background (context only, not source of truth).

### Fallback Chain

If the sub-agent path fails at any layer, degrade to the next:

| Layer | Trigger | Action |
|---|---|---|
| **L0 Main path** | Agent returns valid JSON, fingerprint matches expected | Aggregate and write report |
| **L1 Retry** | JSON parse fails or required fields missing | Use `SendMessage` to the same agent asking for the exact schema — the agent keeps its slice context, no re-slicing needed |
| **L2 Soft-parse** | After 2 retries still malformed | Treat agent's prose output as an unstructured summary; append `⚠ 部分会话摘要来自降级解析` at report bottom |
| **L3 Inline fallback** | Agent dispatch fails entirely (infrastructure error) | Main Claude slices inline via Python into `DIGEST_SCRATCH_ROOT` (already created at Step 2 start, same directory sub-agents would have used). Cleanup happens at Step 3 end along with the normal path |

### Schema drift handling

If `schema_fingerprint` disagrees with expected:
- **Superset** (agent found more fields than expected) → continue, log `⚠ jsonl schema drift detected: <diff>` at report bottom
- **Missing critical field** (no `timestamp` or no `content`) → go straight to L3 inline fallback; the SKILL.md expected-fields list likely needs an update, flag this in the report

**Step 3 — Aggregate, write report, cleanup**

Aggregate all sub-agent outputs, skipping any session with `is_self_referential_digest: true`. Generate using `$PLUME_ROOT/templates/daily-report.md`. Write to `$PLUME_ROOT/data/journal/YYYY-MM-DD.md`. If file exists → **Report Update**.

After the report is written (or the run aborts for any reason), **always** clean up:

```bash
rm -rf "$DIGEST_SCRATCH_ROOT"
```

> **Exclude self-referential digest work**: Sessions flagged `is_self_referential_digest: true` by sub-agents are omitted entirely — no entry, no count, no mention. Additionally, if a non-flagged session's slice turns out to describe only `/digest` command execution, treat it as noise at write time (do not emit "自动生成日报" / "Cron 触发 digest" style entries).

---

## /digest report [natural language topic]

Generate a research report on a topic across scoped sessions.

> **Note**: after v3 slim-design removed context-keeper, this command no longer has snapshot/CONTEXT-INDEX to lean on — it works directly from jsonl via sub-agent delegation. Research reports are expected to be used infrequently.

### Steps

**Step 1 — Enumerate scoped jsonls** (same Phase A logic as daily, no window filter — cover all jsonls in scope regardless of date).

**Step 2 — Delegate topic scanning to sub-agents**

Batch the jsonl list the same way as daily (`N ≤ 5` one-per-agent parallel; `N > 5` grouped). Each agent receives:
- **Goal**: identify lines/exchanges in each jsonl relevant to the topic keywords.
- **Return format**: fenced JSON `{ "matches": [{ "session_id", "snippet", "timestamp", "relevance": "high|medium|low" }] }`

If the user gave no argument, first run a lightweight agent pass asking "cluster the main topics across these jsonls", present clusters to user, then proceed with the chosen cluster.

**Step 3 — Write report**

Main Claude aggregates matches, reads MEMORY.md for background, and generates using `$PLUME_ROOT/templates/research-report.md`. Write to `$PLUME_ROOT/data/reports/<topic-slug>.md`. If file exists → **Report Update**.

Same Fallback Chain (L1 retry / L2 soft-parse / L3 inline) as daily applies.

---

## /digest status

Display: configured scope, matched projects, per-project jsonl count, today's active sessions, daily report existence.

---

## Report Update

When target file exists, present 4 options: Merge / Overwrite / Save as new (`-v2.md`) / Cancel.

Daily merge: 工作详情 append/update → 今日成果 regenerate → 明日计划 use newer.
Research merge: 核心发现 merge → 关键认知 keep all → 结论与建议 regenerate → 参考 union.

---

## Failure Modes

| Failure | Recovery |
|---------|----------|
| No active sessions for date | Report "No activity found." |
| In-window slice exceeds ~1500 lines | Instruct the sub-agent in its prompt to summarize more aggressively (tool calls / file writes / decisions only); agent context is isolated so verbosity doesn't hurt main |
| Cross-day session: which day owns it? | Both. Each day's report shows that day's timestamp slice; slices are disjoint and complementary |
| Session listing seems suspiciously short | Re-enumerate with non-recursive `ls` + `wc -l` cross-check |
| Sub-agent dispatch fails / schema drift / malformed JSON | Follow the Fallback Chain in Step 2 (L1 retry → L2 soft-parse → L3 inline `$PLUME_ROOT/data/.tmp/`) |
| Write fails | Output report to chat |
