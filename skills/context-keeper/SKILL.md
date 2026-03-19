---
name: context-keeper
description: "Use when conversation is about to compact (you see [CONTEXT-RECOVERY]), when completing a significant phase of work, or when the user asks to save context."
---

# Context Keeper

Saves and restores task state across compact events and work sessions.

## Locale

Read `$PLUME_ROOT/config.yml` → `locale.timezone` and `locale.language`.
- **Timezone**: All timestamps (segment filenames, LATEST.md dates) use this timezone. Default: `Asia/Shanghai`.
- **Language**: Segment content (Summary, Decisions, Open Questions) uses this language. Default: `zh-CN`.

> **IRON LAW: NO CONTEXT LOSS.**
> Every significant work phase MUST be saved. Every compact recovery MUST restore.
> There is no acceptable excuse to skip a save or ignore a recovery marker.

## Detect Mode

- `[CONTEXT-RECOVERY]` in current context → **RESTORE**
- `[CONTEXT-SAVE-URGENT]` in current context → **SAVE** (compact was blocked, save before next attempt)
- `[CONTEXT-SAVE-RECOMMENDED]` in current context → **SAVE** (message count threshold reached)
- Otherwise → **SAVE** (user explicit request)

## Storage Layout

```
$PLUME_ROOT/data/<slug>/
├── segments/                    # Append-only timeline (ground truth)
│   └── YYYY-MM-DDTHH-MM.md
├── LATEST.md                    # Lightweight index (derived, ~300 tokens)
├── tags-index.md                     # Tag → segment inverted index (derived)
├── specs/                       # brainstorming output
└── plans/                       # writing-plans output

$PLUME_ROOT/data/
├── journal/                     # digest daily reports (cross-project, scoped)
└── reports/                     # digest research reports
```

**Slug**: `pwd` with leading `/` removed, `/` replaced by `-`.
Example: `/home/plume/myproject` → `home-plume-myproject`

**PLUME_ROOT**: from `[PLUME_ROOT: ...]` at top of session context.

---

## SAVE Mode

### Red Flags — you are about to skip a save you shouldn't

| Thought | Reality |
|---------|---------|
| "This was a minor change, no need to save" | Minor changes accumulate. Save anyway. |
| "I'll save after the next step" | Compact can strike anytime. Save NOW. |
| "The user didn't ask me to save" | Saving is YOUR responsibility, not the user's. |
| "I remember everything, no need to write it down" | You won't after compact. Save. |
| "It's almost the same as the last segment" | Then it's a quick save. Do it. |

### When to Save

- **`[CONTEXT-SAVE-URGENT]` signal**: PreCompact hook blocked compact and wrote `.save-pending` marker. UserPromptSubmit injected this signal. Save NOW — next compact attempt will proceed without blocking.
- **`[CONTEXT-SAVE-RECOMMENDED]` signal**: injected by hook after ≥15 user messages since last save. Save immediately — do NOT defer.
- **User explicit request**: "保存上下文", "save context", etc.

**NOT a trigger**: vague "natural breakpoints" or every task phase. This wastes tokens. Only save when explicitly triggered by signals above or user request.

### Steps

Execute in order. Do NOT skip or reorder.

**Step 1 — Compute slug and timezone**
```bash
slug=$(pwd | sed 's|^/||; s|/|-|g')
```
Read `$PLUME_ROOT/config.yml` → `locale.timezone` (default `Asia/Shanghai`).
Use this timezone for the segment filename timestamp: `TZ=<timezone> date +%Y-%m-%dT%H-%M`.

**Step 2 — Ensure directories**
```bash
mkdir -p "$PLUME_ROOT/data/$slug/segments"
```

**Step 3 — Write segment file** (`segments/YYYY-MM-DDTHH-MM.md`)

```markdown
# Segment YYYY-MM-DDTHH-MM
<!-- project: /absolute/path/to/project -->
<!-- slug: the-computed-slug -->
<!-- tags: category:value, category:value, ... -->

## Summary
[2-3 paragraphs: what was accomplished, the approach taken, and outcome/current state]

## Key Changes
- `path/to/file` — what changed and why
- `path/to/file` — what changed and why

## Artifacts
- created: [files created]
- modified: [files modified]
- specs: [if brainstorming produced a spec, record its path under data/<slug>/specs/]
- plans: [if writing-plans produced a plan, record its path under data/<slug>/plans/]

## Decisions
- [Decision]: [what was chosen] — [reasoning/trade-offs considered]

## Open Questions
- [Unresolved questions, if any]
```

**Step 4 — Verify segment written**

Read the file back. If read fails → retry write once → if still fails, report error to user.

**Step 5 — Rebuild LATEST.md** (index, NOT full content)

From the most recent 5 segments (or fewer if less exist), build a lightweight index:

```markdown
# Context Index: <project-name>
<!-- slug: the-computed-slug -->
<!-- last-save: YYYY-MM-DDTHH-MM -->
<!-- segment-count: N -->

## Active Task
[One line: what you are currently doing]

## Next Step
[One line: the first thing to do when resuming]

## Segment Index
| Time | File | Focus |
|------|------|-------|
| HH:MM | segments/YYYY-MM-DDTHH-MM.md | one-line summary |
| HH:MM | segments/YYYY-MM-DDTHH-MM.md | one-line summary |

## Key Files
- path/to/file — [status: created/modified/in-progress]

## Decisions
- [Recent key decisions, one line each]
```

**Hard limit**: LATEST.md ≤ 800 tokens. This is an INDEX — details live in segments.

**Step 6 — Update tags-index.md**

Append new segment's tags to `$PLUME_ROOT/data/<slug>/tags-index.md`.

File format (one line per tag, space-separated timestamps):
```
# Tags Index — auto-maintained by context-keeper
# rebuildable: scan segments/* for <!-- tags: ... -->
tech:react = 2026-03-15T09-30 2026-03-15T14-15
module:auth = 2026-03-15T09-30 2026-03-15T11-00
activity:feature = 2026-03-15T09-30 2026-03-15T14-15
```

For each tag in the new segment:
- If the tag line exists in tags-index.md → append the new timestamp to that line
- If the tag line does not exist → add a new line
- If tags-index.md does not exist → create it with the new segment's tags

This is an incremental append — never rewrite the entire file for a single save.

**Step 7 — Confirm**

Tell user: "Context saved — segment `[timestamp]`, index rebuilt. [N] segments total."

**Step 8 — Reset counters and clear save-pending marker**
```bash
echo "0" > "$PLUME_ROOT/data/$slug/.msg-count"
rm -f "$PLUME_ROOT/data/.save-pending"
```
This resets the hook message counter so `[CONTEXT-SAVE-RECOMMENDED]` won't fire until another 25 messages.
Removing `.save-pending` tells the PreCompact hook that saving succeeded — the next compact will be blocked again (buying another save opportunity) instead of proceeding immediately.

### Verification Gate

After Step 6, verify:
- [ ] Segment file exists and is readable
- [ ] LATEST.md exists, contains correct slug and segment count
- [ ] LATEST.md has Active Task and Next Step filled (not placeholder text)
- [ ] tags-index.md contains entries for the new segment's tags

If any check fails, fix immediately before confirming.

---

## RESTORE Mode

### Red Flags — you are about to skip a restore you shouldn't

| Thought | Reality |
|---------|---------|
| "I can figure out what we were doing from context" | Post-compact context is lossy. Read the index. |
| "Let me start fresh instead" | The user expects continuity. Restore first. |
| "I'll look at the code and infer" | You'll miss decisions and next steps. Read LATEST.md. |

### Steps

**Step 1 — Compute slug** (same as SAVE)

**Step 2 — Read LATEST.md**
```
$PLUME_ROOT/data/<slug>/LATEST.md
```

- **Found** → proceed to Step 3
- **Not found** → fallback: `ls segments/ | sort | tail -5`, read those segments, synthesize an index. Save it as LATEST.md for next time.

**Step 3 — Present index to user**

Brief summary (2-3 lines):
- What task was in progress
- What the next step is
- How many segments of history are available

**Step 4 — Load recent segments**

Read the most recent 3 segment files from the Segment Index to build rich context. With 1M context window, the cost of loading a few segments is negligible compared to the recovery quality gained.

If more historical depth is needed for the immediate next step, read additional segments as needed.

**Step 5 — Resume work**

Execute the Next Step. Do not wait for the user to re-explain the task.

### Verification Gate

After restore, verify:
- [ ] LATEST.md was actually read (not fabricated from memory)
- [ ] Active Task and Next Step are concrete (not vague)
- [ ] If reading segment files, they exist and are readable

---

## Tags

### Extraction Rules

Tags follow a `category:value` format for consistent search:

```
tech:react, tech:postgres, module:auth, activity:feature, ref:ISSUE-123
```

**Categories**:

| Category | Meaning | Examples |
|----------|---------|---------|
| `tech` | Technology, framework, library | tech:react, tech:go, tech:redis |
| `module` | Feature area, domain | module:auth, module:payment |
| `activity` | Work type | activity:feature, activity:bugfix, activity:refactor, activity:research |
| `ref` | External reference | ref:ISSUE-123, ref:PR-456 |

**Priority matching**: If `$PLUME_ROOT/config.yml` defines a `tags` section, prefer listed values over free-form. Use the exact string from config when the concept matches. Add unlisted tags only for clearly new concepts.

**Consistency rule**: Once a tag is used in any segment for this slug, reuse the same tag for the same concept. Check recent segments before inventing new tags.

---

## Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| LATEST.md missing | Read returns error | Rebuild from most recent 3 segments |
| LATEST.md corrupted | Missing required sections | Delete and rebuild from segments |
| segments/ dir missing | mkdir fails or ls empty | Create dir; if SAVE, proceed normally; if RESTORE, report "no history" |
| Slug mismatch | LATEST.md slug ≠ computed slug | Recompute; warn user if project moved |
| Disk write fails | Verify gate catches | Retry once; if still fails, output segment content to chat as fallback |
| PLUME_ROOT unset | Config read fails | Warn user to run `install.sh --repair` |

---

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "The segment would be almost empty" | An empty save is better than a lost save. Write it. |
| "Compact probably won't happen soon" | You don't know that. It's silent and sudden. |
| "I'll combine this with the next save" | Two small saves > one missed save. |
| "The user can re-explain if needed" | That wastes the user's time. Save their context. |
| "LATEST.md is good enough without updating" | Stale index is a wrong index. Rebuild it. |
| "I don't need to read LATEST.md, I can see the summary" | Post-compact summaries lose details. Always read the file. |
