---
name: digest
description: "Use when user requests /digest, a daily summary, or a research report of session work."
---

# Digest

Generates daily reports and research reports from Claude's native data sources (jsonl + session snapshots + MEMORY.md).

Read `$PLUME_ROOT/config.yml` for `locale` (timezone, language), `digest` (default_scope).

> A report MUST cover ALL active sessions within scope. Always read source files — never summarize from memory alone.

---

## /digest daily [YYYY-MM-DD] [--scope keyword]

Generate a daily report. Default date: today.

### Scope

Resolution: `--scope` arg > `config.yml default_scope` > ask user.
Matching: Claude project slug **contains** scope keyword as substring.

### Steps

**Step 1** — Find scoped project dirs in `~/.claude/projects/`. For each jsonl file, determine if the session was **active on the target date** using interval overlap:

1. **session_start**: read the first line of the jsonl, extract `timestamp` field (ISO 8601 UTC)
2. **session_end**: file mtime (use `stat` or `os.path.getmtime()`)
3. **target window**: target date 00:00:00 ~ 23:59:59 in config timezone, converted to UTC
4. **Match condition**: `session_start <= target_end AND session_end >= target_start`

This correctly captures cross-day sessions: a session started yesterday and still active today will appear in both days' reports. Do NOT rely on mtime alone — it only reflects the last write time and misses sessions that started on the target date but are still active later.

```bash
# Example: get session_start from first line
head -1 <session>.jsonl | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('timestamp',''))"
```

Display matched projects + session counts to user for confirmation (skip if cron/`-p` mode).

**Step 2** — Gather content per active session (first available source):
1. Session snapshots (`plume-context/sessions/<id>-<timestamp>.md`)
2. CONTEXT-INDEX.md timeline entry
3. jsonl tail (~200 lines)

Read MEMORY.md for project context (supplementary).

**Step 3** — Generate using `$PLUME_ROOT/templates/daily-report.md`. Write to `$PLUME_ROOT/data/journal/YYYY-MM-DD.md`. If file exists → **Report Update**.

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
| CONTEXT-INDEX.md or snapshots missing | Fall back to jsonl tails |
| Write fails | Output report to chat |
