---
name: using-plume
description: "System guide injected at session start. Do not invoke manually."
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this guide entirely.
</SUBAGENT-STOP>

# Plume Skills Framework

You have skills that give you structured capabilities. Use the Skill tool to invoke them by name. Skills are loaded on demand — only read a skill when you need it.

## Priority Chain

```
User direct instruction > CLAUDE.md > <PLUME-OVERRIDE> in wrapper > vendor skill content > system default
```

## Skill Invocation Rule

**If a skill MIGHT apply, you MUST invoke it BEFORE any response or action.** This is not optional.

Even a 1% chance a skill applies means invoke it. If the skill turns out irrelevant, move on. But never skip the check.

**Skill priority**: process skills first (brainstorming, debugging), then implementation skills (TDD, code review).

**Stop rationalizing** — these thoughts mean you're about to skip a skill you shouldn't:

| Thought | Reality |
|---------|---------|
| "This is just a simple question" | Check for skills first. |
| "I need more context first" | Skill check comes BEFORE gathering context. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "The skill is overkill for this" | Simple things become complex. Use it. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |
| "I remember what that skill says" | Skills evolve. Read the current version. |

## Wrapper Pattern

Some skills contain a `<PLUME-OVERRIDE>` block. When you see one:
1. Read and memorize the override directives
2. Read the referenced vendor skill file using the PLUME_ROOT path from context
3. Follow the vendor skill, but override sections take priority
4. Anything not mentioned in the override follows vendor as-is

## Core Workflow

Think before you act. Follow this progression:

| Phase | Action | Gate |
|-------|--------|------|
| Understand | Clarify requirements, ask questions | User confirms understanding |
| Design | Use brainstorming skill for creative work | Spec reviewed and approved |
| Plan | Break into tasks (use writing-plans in projects) | Plan approved |
| Execute | Implement with TDD, use subagents for parallel work | Tests pass |
| Verify | Evidence-based verification, never skip investigation | Proof shown |
| Review | Code review before completion | No critical issues |

**Red lines:**
- NEVER skip straight to code without understanding the problem
- NEVER claim "it works" without running verification
- When blocked, propose a pragmatic fallback — don't spin

## Context Survival

**Save triggers** — Call `context-keeper` SAVE only when:
1. **`[CONTEXT-SAVE-URGENT]`**: PreCompact blocked compact. Save NOW — next compact attempt will not block.
2. **`[CONTEXT-SAVE-RECOMMENDED]`**: hook counter reached ≥15 messages since last save. Save immediately.
3. **User explicit request**: "保存上下文", "save context", etc.
4. Never save "just because" — no per-turn or per-phase auto-saves.

**Compact recovery** — Two detection paths:

1. **`[CONTEXT-RECOVERY]` in context** (PreCompact hook wrote marker → UserPromptSubmit injected it):
   - IMMEDIATELY call `context-keeper` skill in RESTORE mode
   - It reads a lightweight index (~300 tokens), not a full dump
   - Load segment details only as needed for the immediate next step
   - Resume work without asking the user to re-explain

2. **`[PLUME_ROOT: ...]` line is MISSING from this context** (compact stripped it, hook didn't fire):
   - Read `~/.claude/skills/using-plume/SKILL.md` to find PLUME_ROOT path from the symlink target
   - Or read `$HOME/.claude/settings.local.json` → look for plume hook path → derive PLUME_ROOT
   - Once PLUME_ROOT is found, compute slug from `pwd`, read `$PLUME_ROOT/data/<slug>/LATEST.md`
   - Follow RESTORE steps from context-keeper skill
   - This is a fallback — if `[PLUME_ROOT: ...]` is present, skip this entirely

## Paths

The `[PLUME_ROOT: ...]` line at the top of this context provides the absolute path to plume-skills.
Use it for ALL file operations:
- Vendor skills: `PLUME_ROOT/vendor/superpowers/<name>/SKILL.md`
- Config: `PLUME_ROOT/config.yml`
- Project data: `PLUME_ROOT/data/<slug>/` — per-project working data:

| Subdirectory | Producer | Content |
|-------------|----------|---------|
| `segments/` | context-keeper | Append-only work timeline |
| `LATEST.md` | context-keeper | Lightweight context index |
| `tags-index.md` | context-keeper | Tag → segment inverted index |
| `specs/` | brainstorming | Design spec documents |
| `plans/` | writing-plans | Implementation plan documents |

- Cross-project output: `PLUME_ROOT/data/journal/` and `PLUME_ROOT/data/reports/` — digest writes here (scoped by config keyword, not by slug)

`<slug>` = current working directory path with `/` replaced by `-`, leading `/` removed.
Example: `/home/plume/myproject` → `home-plume-myproject`

## Network / Proxy

When executing commands that download or install resources from outside China (npm install, pip install, cargo install, git clone from github.com, curl/wget to foreign hosts, etc.):

1. First attempt: run normally
2. Second attempt: if timeout or connection refused, retry once
3. **After 2 failures**: STOP. Do NOT keep retrying. Instead:
   - Inform the user: "连接超时，可能需要检查代理配置"
   - Show the exact command that failed
   - Suggest the user run it manually (they may need to configure proxy, VPN, or mirror)
   - Wait for the user to report completion before continuing

## Privacy

Each project's data is isolated by its directory slug. Company and personal projects have different path prefixes and never mix. Use `--scope` to aggregate across projects by path prefix keyword.
