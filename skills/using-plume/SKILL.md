---
name: using-plume
description: "System guide injected at session start. Do not invoke manually."
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this guide entirely.
</SUBAGENT-STOP>

# Plume Skills Framework

Skills give you structured capabilities. Invoke by name via the Skill tool. Load on demand — only read a skill when needed.

## Priority

`User instruction > CLAUDE.md > <PLUME-OVERRIDE> in wrapper > vendor skill > system default`

## Skill Invocation

**If a skill MIGHT apply, invoke it BEFORE any response or action.** Even 1% chance means invoke it. Process skills first (brainstorming, debugging), then implementation skills (TDD, code review). Never skip because "it's simple" or "I remember what it says" — skills evolve.

## Wrapper Pattern

Skills with `<PLUME-OVERRIDE>` blocks: read override → read vendor skill via PLUME_ROOT → override wins on conflicts → vendor as-is elsewhere.

## Context Signals

| Signal | Action |
|--------|--------|
| `[CONTEXT-SAVE-URGENT]` | Call context-keeper SAVE immediately (full context, highest quality) |
| `[CONTEXT-RECOVERY]` | Call context-keeper — it will SAVE then RESTORE |
| `[PLUME_ROOT: ...]` missing | Fallback: derive PLUME_ROOT from `~/.claude/settings.local.json` hook paths, then call context-keeper RESTORE |
| `[DIGEST-HINT]` | Remind user: "今日有工作记录，可运行 /digest daily 生成日报" |
| `[DIGEST-AUTO]` | Launch background subagent to generate daily report silently. Tell user one line: "日报生成中（后台）..." |

Never save "just because" — only on signals or user request.

## Paths

`[PLUME_ROOT: ...]` in context = absolute path to plume-skills. Use for:
- Vendor skills: `PLUME_ROOT/vendor/superpowers/<name>/SKILL.md`
- Config / Templates: `PLUME_ROOT/config.yml`, `PLUME_ROOT/templates/`
- Reports: `PLUME_ROOT/data/journal/`, `PLUME_ROOT/data/reports/`
- Project output: `<project-root>/docs/plume-skills/{specs,plans}/`
- Context data: `~/.claude/projects/<slug>/plume-context/` (`slug = pwd | sed 's|/|-|g'`)

## Network

After 2 timeout/connection failures on foreign resources: STOP retrying. Tell user "连接超时，可能需要检查代理配置", show the failed command, wait for user to handle manually.

## Privacy

Project data isolated by Claude project slug. Use `--scope` keyword to aggregate across projects with matching path prefixes.
