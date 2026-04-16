---
name: digest
description: "Use when user requests /digest, a daily summary, or a research report of session work."
---

# Digest

Generates daily reports and research reports. Daily reports source from jsonl (timestamp-sliced); research reports source from CONTEXT-INDEX/snapshots with jsonl as deep dive. MEMORY.md provides background context for both.

Read `$PLUME_ROOT/config.yml` for `locale` (timezone, language), `digest` (default_scope).

> A report MUST cover ALL active sessions within scope. Always read source files — never summarize from memory alone.

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

**Step 2 — Slice each session by timestamp window**

**jsonl is the authoritative source. Always read it. Never consult snapshots/CONTEXT-INDEX in daily mode unless the in-window slice is too dense to summarize.**

Each line in a jsonl carries its own `timestamp` field. The jsonl is append-only and contains the complete session history from first message to last — including for sessions that span multiple days. **Tail-based reading is wrong for cross-day sessions** because it can miss the target day's work entirely.

For each active session, do **per-line timestamp filtering**, not tail:

1. **Filter the jsonl** to lines whose `timestamp` falls within the target window `[target_start, target_end)`. This is the slice that belongs to the target date's report.
2. A cross-day session naturally appears in **multiple daily reports** — each day shows that day's slice. The slices are disjoint and complementary.
3. Summarize from the slice. Focus on user requests, decisions, files modified, outcomes.
4. **Cross-check files actually modified**: if the slice mentions writing files in a directory, verify with `stat` that mtimes fall within the window. Catches anything the slice paraphrasing missed.

```bash
# Filter jsonl by per-line timestamp window (UTC ISO 8601)
python3 - <<'PY' "$jsonl" "$start_utc" "$end_utc"
import sys, json
path, start, end = sys.argv[1:]
with open(path) as f:
    for line in f:
        try:
            ts = json.loads(line).get("timestamp", "")
            if start <= ts < end:
                print(line, end="")
        except Exception:
            pass
PY
```

**Fallback to context-keeper artifacts only when**: the in-window slice exceeds ~1500 lines AND you cannot summarize directly. Then consult `plume-context/CONTEXT-INDEX.md` timeline + matching `plume-context/sessions/<id>-*.md` snapshots as compression aids — treat them as *supplementary*, never authoritative. If the snapshots don't exist (the common case), proceed with the raw slice and read more selectively (grep for tool calls, file writes, decisions).

Read MEMORY.md for project context (background only).

> Why jsonl-first with timestamp filtering: jsonl is the system-written ground truth. Snapshots/CONTEXT-INDEX are human-triggered artifacts that may not exist. Tail is a hack that breaks for long sessions. Per-line timestamp slicing is the only mechanism that correctly handles both short single-day sessions and ultra-long multi-day sessions, and it makes context-keeper a true *fallback* (only for ultra-dense days), not a default detour.

**Step 3** — Generate using `$PLUME_ROOT/templates/daily-report.md`. Write to `$PLUME_ROOT/data/journal/YYYY-MM-DD.md`. If file exists → **Report Update**.

> **Exclude self-referential digest work**: If a session's slice content is almost entirely a `/digest` command invocation and its execution trace, treat it as noise and omit it from the report — no entry, no count, no mention. The daily report describes user work, not the act of generating itself (e.g. do not emit "自动生成日报" / "Cron 触发 digest" style entries).

---

## /digest report [natural language topic]

Generate a research report.

- **With argument**: semantic match against CONTEXT-INDEX.md and snapshots across scoped projects
- **Without argument**: display topic clusters from CONTEXT-INDEX.md, let user choose

### Steps

**Step 1** — Scan scoped `plume-context/CONTEXT-INDEX.md` + grep `sessions/*.md` for topic keywords.

**Step 2** — Read matched snapshots. If more detail needed, grep jsonl. Read MEMORY.md for context.

**Step 3** — Generate using `$PLUME_ROOT/templates/research-report.md`. Write to `$PLUME_ROOT/data/reports/<topic-slug>.md`. If file exists → **Report Update**.

---

## /digest status

Display: configured scope, matched projects, per-project snapshot count, today's active sessions, daily report existence.

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
| CONTEXT-INDEX.md or snapshots missing | Proceed with jsonl timestamp slice alone (jsonl is primary anyway) |
| In-window slice exceeds ~1500 lines | Consult CONTEXT-INDEX/snapshots as compression aids if present; otherwise grep slice for tool calls / file writes / decisions |
| Cross-day session: which day owns it? | Both. Each day's report shows that day's timestamp slice; slices are disjoint and complementary |
| Session listing seems suspiciously short | Re-enumerate with non-recursive `ls` + `wc -l` cross-check |
| Write fails | Output report to chat |
