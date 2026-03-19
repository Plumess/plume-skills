---
name: digest
description: "Use when user requests /digest, a daily summary, or a research report of session work. Also use when you see [DIGEST-HINT] or [DIGEST-AUTO] in context."
---

# Digest

Aggregates context-keeper segments into structured reports.

## Locale

Read `$PLUME_ROOT/config.yml` → `locale.timezone` and `locale.language`.
- **Timezone**: All time window computations and date labels use this timezone. Default: `Asia/Shanghai`.
- **Language**: Generated reports (daily and research) use this language throughout. Default: `zh-CN`.

> **IRON LAW: NO PARTIAL REPORTS.**
> A daily report MUST include ALL segments within the time window for the given scope.
> A research report MUST include ALL segments matching the queried tags.
> Skipping segments produces incomplete records. There is no acceptable shortcut.

## Data Layout

```
$PLUME_ROOT/data/
├── journal/                   # Daily reports (one per day, scoped)
│   └── YYYY-MM-DD.md
├── reports/                   # Research reports
│   └── <topic>.md
├── home-plume-aaa-b/          # Project-specific working data
│   ├── segments/
│   ├── tags-index.md
│   ├── specs/
│   └── plans/
└── home-plume-aaa-c/
    └── ...
```

Digest **reads** from scoped `data/*/segments/` and **writes** to `data/journal/` and `data/reports/`.

**PLUME_ROOT**: from `[PLUME_ROOT: ...]` at top of session context.

## Config

Read `$PLUME_ROOT/config.yml`:
- `locale.timezone`: timezone for time window (default `"Asia/Shanghai"`)
- `locale.language`: report language (default `"zh-CN"`)
- `digest.default_scope`: slug keyword for daily report scope (e.g. `"edgeexploration"`)
- `digest.auto_generate`: `true` = auto-generate at remind_at times; `false` = hint only
- `digest.remind_at`: time points for hint/auto triggers

---

## Subcommands

### /digest daily [YYYY-MM-DD] [--scope keyword]

Generate a daily report. Default date: today.

#### Scope — Privacy Isolation

Daily reports only collect segments from projects matching a **scope keyword**.
This prevents personal projects from leaking into work reports.

**Resolution order**:
1. `--scope keyword` explicit argument → use it
2. `config.yml` → `digest.default_scope` → use it
3. Neither set → **ask the user** which directory scope to use before proceeding

**Before generating**, always display to the user:
```
Daily report scope: "edgeexploration"
Projects included:
  - aaa-b (5 segments)
  - aaa-c (3 segments)
Proceed? (or specify --scope to change)
```

If `auto_generate` is true and triggered via `[DIGEST-AUTO]`, skip confirmation and use default_scope directly.

**Matching rule**: a project slug matches if it **contains** the scope keyword as a substring.
```
scope "aaa" → matches:
  home-plume-aaa-b         (aaa/b)
  home-plume-aaa-c         (aaa/c)
  home-plume-aaa-c-deep    (aaa/c/deep)
Does NOT match:
  home-plume-personal-xyz  (personal/xyz)
```

#### Time Window

Covers a **calendar day** — date **D** from 00:00:00 to 23:59:59 in configured timezone.

- Example: date 2026-03-17, timezone Asia/Shanghai → 2026-03-17T00:00 ~ 2026-03-17T23:59

#### Steps

1. **Resolve scope** — `--scope` argument > `config.yml` default_scope > ask user
2. **Compute time window** — date D 00:00 ~ 23:59 in `locale.timezone`
3. **Collect scoped segment directories** — `ls $PLUME_ROOT/data/` → filter dirs whose name contains scope keyword AND has `segments/`
   - Skip `journal/`, `reports/`, `archives/`
4. **Display scope summary** — show matched projects + segment counts (skip if auto-generate)
5. **Filter segments by time** — parse `YYYY-MM-DDTHH-MM` from filenames, include only those within window
6. **Verify completeness** — count collected segments vs total files matching the time range. They MUST match.
7. **Read all matching segments** — extract Summary, Artifacts, Decisions, Open Questions
8. **Scan specs/ and plans/** — in each matched project's directory, list files with date prefix within the time window
9. **Aggregate into report** — follow template structure
10. **Check existing file** — read `$PLUME_ROOT/data/journal/YYYY-MM-DD.md`:
    - **Not exists** → write new file
    - **Exists** → smart merge (see "Report Update" section below)
11. **Report to user** — summary line: date, scope, segment count, project count, output path

#### Verification Gate

After step 7, if file count mismatch is detected:
- List the missing/extra files
- Ask user whether to proceed with partial data or investigate

After step 11, read back the written file to verify it exists and is non-empty.

#### Daily Report Template

Read the template from `$PLUME_ROOT/templates/daily-report.md` and follow its structure and notes.

Key rules:
- Project short name: last segment of slug (e.g., `home-plume-aaa-b` → `b`)
- If only one project has segments, simplify — omit project grouping headers
- All sections are required even if empty

---

### /digest report \<topic description\> [--since YYYY-MM-DD] [--scope keyword]

Generate a research/topic report. The topic is **natural language** — no need to know exact tag names.

Examples:
- `/digest report 用户认证相关的工作`
- `/digest report auth`
- `/digest report 最近的性能优化`
- `"总结一下最近 auth 方面的工作"` — also triggers this command

**Default scope**: current project slug only (research is typically project-focused).
**With --scope**: match all slug dirs containing the keyword.

#### Steps

1. **Determine search scope** — current slug (default) or all slug dirs matching --scope keyword
2. **Semantic search via tags-index.md + segments**:
   a. Read `tags-index.md` from each matched slug's data directory
   b. Match topic against tag values **semantically** (e.g. "用户认证" matches `module:auth`; "性能" matches `activity:performance`)
   c. Collect candidate segment timestamps from matching tags
   d. If tags-index.md is missing, empty, or produces <3 results: fall back to reading segment files directly and grep for topic keywords in Summary/Decisions
   e. Combine all matched segment timestamps, deduplicate
3. **Filter by --since** if provided (default: no time limit)
4. **Read matching segments** — sort by timestamp
5. **Verify completeness** — cross-check idx results with grep fallback if segment count seems low
6. **Aggregate into report** (template below)
7. **Check existing file** — `$PLUME_ROOT/data/reports/<topic-slug>.md`:
   - `<topic-slug>`: brief English slug derived from the topic (e.g. "用户认证" → `auth`, "性能优化" → `performance`)
   - **Not exists** → write new file
   - **Exists** → smart merge (see "Report Update" section below)

#### No-argument mode: `/digest report`

If no topic is provided:
1. Read `tags-index.md` from scoped project(s)
2. Aggregate tag counts across all segments
3. Display top tag clusters with counts:
   ```
   可用主题：
     module:auth (12 segments)  — 用户认证、权限相关
     tech:react (8 segments)   — React 组件开发
     activity:refactor (5 segments) — 重构工作
   选择一个主题，或输入自然语言描述：
   ```
4. Wait for user selection

#### Research Report Template

Read the template from `$PLUME_ROOT/templates/research-report.md` and follow its structure and notes.

---

### Report Update (applies to both daily and research reports)

When the target file already exists, **always confirm with the user** before proceeding:

```
File exists: data/journal/2026-03-17.md
Choose action:
  1. Smart merge (integrate new content into existing file)
  2. Overwrite (replace with new content)
  3. Save as new file (keep original)
  4. Cancel
```

**Smart merge rules** (when user chooses 1):

Daily report merge:
- **Highlights section**: append new items at end of list
- **Details section**: new topics become new subsections; existing topics get new entries appended
- **Tomorrow section**: mark completed items as ~~done~~, append new items
- On conflict, latest content wins — edit in place, never keep contradictory versions
- Result must be a coherent, complete report

Research report merge:
- **Findings**: append as new numbered subsections
- **Key insights**: append new insights
- **Conclusions**: update based on new findings (may modify existing conclusions)
- **References**: append new segment citations
- Result must be a coherent, complete research record

---

### /digest status

Overview of ALL available data. No file output — display only.

#### Display Format

```
Digest Status
  Segments: 42 total (2026-03-01 ~ 2026-03-15)
  Daily reports: 8 (latest: 2026-03-14)
  Research reports: 2 (auth, performance)

  Per-project breakdown:
    aaa-b — 25 segments, 3 specs, 1 plan
    aaa-c — 17 segments, 0 specs, 2 plans

  Top tags (across all projects):
    module:auth (12)  activity:feature (9)  tech:react (8)
    tech:postgres (6)  activity:bugfix (5)
```

If no segments: inform user and suggest working first (context-keeper saves segments at natural breakpoints).

---

### /digest rebuild-index

Scan ALL `data/*/segments/` files, reconstruct every project's `tags-index.md` from scratch.

Use when tags-index.md is suspected stale or missing.

---

## Auto-Sense: [DIGEST-HINT] / [DIGEST-AUTO]

The `user-prompt-submit` hook detects when a daily report may be warranted.
All conditions must be met:

1. **Time window**: current time is within ±60 minutes of a `remind_at` time (default: 09:00, 18:00)
2. **Scope configured**: `default_scope` is set in config.yml
3. **Segment count**: ≥ 1 segment for today across scoped projects
4. **No existing report**: no `data/journal/YYYY-MM-DD.md` for today

Fires **once per day** (marker file prevents repeat).

**Two modes** depending on `auto_generate` config:

| Config | Hook injects | Claude behavior |
|--------|-------------|-----------------|
| `auto_generate: false` | `[DIGEST-HINT]` | Suggest `/digest daily` to user after current response |
| `auto_generate: true` | `[DIGEST-AUTO]` | Immediately execute `/digest daily` with default_scope, no confirmation |

When you see `[DIGEST-HINT]`:
1. Do NOT interrupt the user's current task
2. After completing the current response, mention the available segments and suggest `/digest daily`
3. If the user declines, do not mention it again this session

When you see `[DIGEST-AUTO]`:
1. Execute `/digest daily` using the default_scope from config
2. Skip the scope confirmation display (auto mode)
3. Output the report and inform the user it was auto-generated

---

## Tags Index

Digest relies on `tags-index.md` maintained by context-keeper for efficient tag lookups.

**Format** (`$PLUME_ROOT/data/<slug>/tags-index.md`):
```
# Tags Index — auto-maintained by context-keeper
# rebuildable: scan segments/* for <!-- tags: ... -->
tech:react = 2026-03-15T09-30 2026-03-15T14-15
module:auth = 2026-03-15T09-30 2026-03-15T11-00
activity:feature = 2026-03-15T09-30 2026-03-15T14-15
```

**Lookup**: to find segments for a topic, grep the idx file for matching tag entries, then read only those segment files.

**Fallback**: if tags-index.md is missing, corrupt, or stale, fall back to grep across all segment files. Then rebuild the idx from what was found.

---

## Red Flags

| Thought | Reality |
|---------|---------|
| "These segments look similar, I'll skip some" | Every segment is a unique work record. Include ALL. |
| "The report is long enough already" | Completeness > brevity. Summarize, don't omit. |
| "Tags index seems stale, I'll just use it anyway" | Stale index = wrong results. Rebuild or fallback to grep. |
| "The user probably doesn't need tomorrow's section" | Every section exists for a reason. Fill them all. |
| "Only one project had work today, no need for project headers" | If one project, simplify. But always scan ALL projects first. |

## Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|----------|
| No segments in time window | Empty file list after filtering | Report to user: "No segments found for [date]. Was context-keeper saving?" |
| tags-index.md missing | File read error | Fall back to grep; rebuild idx after |
| tags-index.md stale | Segment exists but not in idx | Merge missing entries; warn user to run rebuild-index |
| Config missing timezone | Key not in config.yml | Default to "Asia/Shanghai" |
| No project dirs in data/ | ls returns only journal/reports | Report "No project data found. Work in a project first." |
| Journal dir not writable | Write fails | Retry with mkdir -p; if still fails, output report to chat |

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Most of today's work was minor, skip the daily" | Minor work adds up. The daily captures the full picture. |
| "I'll generate the report later" | You might forget, or context may be lost. Do it now. |
| "The segments are too few for a meaningful report" | Even 1 segment is worth recording. Generate it. |
| "I can summarize from memory without reading segments" | Memory is unreliable. Always read the source files. |
