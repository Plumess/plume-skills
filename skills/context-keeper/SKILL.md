---
name: context-keeper
description: "Invoke when user says 保存上下文/save context/保存/save, or when completing a significant phase of work and wants to record progress."
---

# Context Keeper

Generates human-readable session summaries and maintains a cross-session timeline index.
Uses Claude's native jsonl as ground truth — maintains only an index layer (snapshots + CONTEXT-INDEX.md).

## Locale

Read `$PLUME_ROOT/config.yml` → `locale.timezone` and `locale.language`.

## Detect Mode

- User says save/保存 → **SAVE**
- User asks to review history → **REVIEW**
- User cleanup request → **CLEANUP**

## Storage Layout

```
~/.claude/projects/<slug>/
├── *.jsonl                      # Claude native — ground truth
├── memory/MEMORY.md             # Claude native — read-only for us
├── plume-context/
│   ├── CONTEXT-INDEX.md         # Full-history timeline index
│   └── sessions/<sid>-<timestamp>.md  # Session snapshot

$PLUME_ROOT/data/
├── journal/                     # digest daily reports
└── reports/                     # digest research reports
```

**Slug**: `pwd | sed 's|/|-|g'` (Claude-native, keeps leading dash).
**Session ID**: first 8 chars of current session's jsonl UUID.
**Timestamp**: YYYYMMDD-HHMM (configured timezone).
**MEMORY.md**: read during REVIEW for context, never written by us.

---

## SAVE Mode

Generate a structured summary of the current session from context (not from jsonl — you have the full context in memory).

### Steps

**Step 1 — Compute paths and ensure dirs**
```bash
SLUG="$(pwd | sed 's|/|-|g')"
SESSIONS_DIR="$HOME/.claude/projects/$SLUG/plume-context/sessions"
mkdir -p "$SESSIONS_DIR"
```

**Step 2 — Determine filename**
```bash
TZ_NAME="<from config.yml>"
TIMESTAMP="$(TZ=$TZ_NAME date +%Y%m%d-%H%M)"
FILENAME="<session-id>-$TIMESTAMP.md"
```

If a snapshot with the same session-id already exists (different timestamp), this is an update — the new one supplements, not replaces.

**Step 3 — Write snapshot** following `$PLUME_ROOT/templates/session-snapshot.md` template. Summarize from current context.

**Step 4 — Rebuild CONTEXT-INDEX.md** following `$PLUME_ROOT/templates/context-index.md` template. Read all snapshots in `sessions/`, build cumulative index.

**Step 5 — Confirm**
Tell user: "Context saved — snapshot `<filename>`, [N] snapshots total."

---

## REVIEW Mode

Present the session history timeline for the current project.

### Steps

**Step 1 — Read CONTEXT-INDEX.md** from `~/.claude/projects/<slug>/plume-context/`
- Found → Step 2
- Not found → list `sessions/`, read snapshots, synthesize index
- Empty → report "no history available"

**Step 2 — Present** timeline summary: each session's date, duration/scope, key outcomes.

**Step 3 — Drill down** if user asks about a specific session, read that snapshot. If snapshot lacks detail, grep the jsonl for specifics:
```bash
ls ~/.claude/projects/$SLUG/*.jsonl
grep -i "<keyword>" ~/.claude/projects/$SLUG/<session>.jsonl | tail -20
```

---

## CLEANUP Mode

Manages snapshot and session data size. Triggered by user request.

**Step 1 — Scan** all `~/.claude/projects/*/plume-context/` dirs + associated jsonl. Compute per-project size and last-modified time.

**Step 2 — Check threshold** from `config.yml` → `context.max_data_size_mb` (default 500). Below threshold → report size and stop.

**Step 3 — Build candidates and present** following `$PLUME_ROOT/templates/cleanup-report.md` template. Two sources merged (staleness priority): >30 days inactive + top 10 by size.

**Step 4 — Execute** user's choice. Delete `plume-context/` for selected items. Ask separately about jsonl deletion. Never delete `memory/MEMORY.md`.

---

## Failure Modes

| Failure | Recovery |
|---------|----------|
| CONTEXT-INDEX.md missing or corrupted | Rebuild from available snapshots |
| sessions/ empty | SAVE: proceed normally; REVIEW: report "no history" |
| Disk write fails | Retry once; if still fails, output snapshot to chat |
| PLUME_ROOT unset | Warn user to run `install.sh --repair` |
