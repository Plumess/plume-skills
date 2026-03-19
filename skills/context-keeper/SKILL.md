---
name: context-keeper
description: "Use when conversation is about to compact (you see [CONTEXT-RECOVERY]), when completing a significant phase of work, or when the user asks to save context."
---

# Context Keeper v2

Saves and restores task state across compact events and work sessions.
Uses Claude's native jsonl as ground truth — maintains only an index layer (snapshots + CONTEXT-INDEX.md).

## Locale

Read `$PLUME_ROOT/config.yml` → `locale.timezone` and `locale.language`.

> **Once a save signal fires, you MUST save — regardless of how little content there is.**
> Once a recovery signal fires, you MUST restore from files — do not rely on post-compact memory.

## Detect Mode

- `[CONTEXT-SAVE-URGENT]` → **SAVE** (PreCompact blocked compact; full context — highest quality)
- `[CONTEXT-RECOVERY]` → **SAVE then RESTORE** (compact executed; capture summary as snapshot, then restore)
- User request → **SAVE**
- User cleanup request → **CLEANUP**

## Storage Layout

```
~/.claude/projects/<slug>/
├── *.jsonl                      # Claude native — ground truth
├── memory/MEMORY.md             # Claude native — read-only for us
├── plume-context/
│   ├── CONTEXT-INDEX.md         # Full-history timeline index
│   └── sessions/<id>-<seq>.md   # Per-snapshot summaries

$PLUME_ROOT/data/
├── journal/                     # digest daily reports
└── reports/                     # digest research reports
```

**Slug**: `pwd | sed 's|/|-|g'` (Claude-native, keeps leading dash).
**Session ID**: first 8 chars of current session's jsonl UUID.
**MEMORY.md**: read during RESTORE for context, never written by us.

---

## SAVE Mode

### Steps

**Step 1 — Compute paths and ensure dirs**
```bash
SLUG="$(pwd | sed 's|/|-|g')"
SESSIONS_DIR="$HOME/.claude/projects/$SLUG/plume-context/sessions"
mkdir -p "$SESSIONS_DIR"
```

**Step 2 — Determine sequence**: none → `001`; `001` exists → `002`; etc.

**Step 3 — Write snapshot** following `$PLUME_ROOT/templates/session-snapshot.md` template. Summarize from current context, not from reading jsonl.

**Step 4 — Rebuild CONTEXT-INDEX.md** following `$PLUME_ROOT/templates/context-index.md` template. Read all snapshots in `sessions/`, build cumulative index.

**Step 5 — Clear markers and confirm**
```bash
rm -f "$PLUME_ROOT/data/.save-pending-"*
```
Tell user: "Context saved — snapshot `<id>-<seq>` (<quality>), [N] snapshots total."

---

## RESTORE Mode

### Steps

**Step 1 — Read CONTEXT-INDEX.md** from `~/.claude/projects/<slug>/plume-context/`
- Found → Step 2
- Not found → list `sessions/`, read snapshots, synthesize index
- Empty → report "no history available"

**Step 2 — Present** brief summary (2-3 lines): task in progress, next step, snapshot count.

**Step 3 — Load** 2-3 most recent snapshots (prefer lowest seq = highest quality). Also read `memory/MEMORY.md` if exists (supplementary).

**Step 4 — Resume** the Next Step. Do not wait for user to re-explain.

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
| sessions/ empty | SAVE: proceed normally; RESTORE: report "no history" |
| Disk write fails | Retry once; if still fails, output snapshot to chat |
| PLUME_ROOT unset | Warn user to run `install.sh --repair` |
