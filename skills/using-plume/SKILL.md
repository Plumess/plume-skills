---
name: using-plume
description: "Framework mechanics reference — path conventions, PLUME_ROOT fallback, network policy, privacy/scope, optional wrapper extension pattern. Read on demand when handling IO, path resolution, or integrating external skills. Do not invoke for behavior — those principles are in SessionStart injection."
---

<SUBAGENT-STOP>
If you were dispatched as a subagent for a narrow task, skip this file entirely unless the task explicitly involves path resolution, network handling, or wrapper extensions.
</SUBAGENT-STOP>

# Plume Framework Mechanics

This skill documents framework mechanics only. Behavior principles are injected at session start — do not re-read or re-document them here.

## PLUME_ROOT Signal

`[PLUME_ROOT: ...]` appears in your context via SessionStart and UserPromptSubmit hooks. It is the absolute path to the plume-skills repository root. Use it to resolve all framework file references.

### Fallback (if signal missing)

1. Check the current project-level `.claude/settings.local.json` for hook command paths. Walk up cwd ancestors if needed.
2. If absent, check `~/.claude/settings.local.json`.
3. Parse `"command"` under `hooks.SessionStart[].hooks[].command` — the containing directory of `hooks/session-start` is PLUME_ROOT.
4. Report the derived value to the user before proceeding.

## Path Conventions

### Framework paths (under PLUME_ROOT)

| Path | Purpose |
|---|---|
| `$PLUME_ROOT/config.yml` | Framework config (locale, digest) |
| `$PLUME_ROOT/templates/` | Shared templates (git-plan.md, daily-report.md, research-report.md) |
| `$PLUME_ROOT/data/journal/` | Digest daily reports (output) |
| `$PLUME_ROOT/data/reports/` | Digest research reports (output) |
| `$PLUME_ROOT/.plume-install-state.json` | install.sh deploy marker (do not hand-edit) |

### Project output default paths (suggestions — always confirm via Ask-Before-Persist)

| Output type | Default path suggestion |
|---|---|
| Design specs (from Plan-First / brainstorm mode) | `<project-root>/docs/plume-skills/specs/YYYY-MM-DD-<topic>-design.md` |
| Implementation plans (from Plan-First) | `<project-root>/docs/plume-skills/plans/YYYY-MM-DD-<topic>.md` |
| Code review reports (from `code-review` skill) | `<project-root>/docs/plume-skills/reviews/YYYY-MM-DD-<topic>.md` |
| Socratic dialogue outcomes (from `socratic-dialogue`) | `<project-root>/docs/plume-skills/socratic/YYYY-MM-DD-<topic>.md` |

`<project-root>` = current working directory. Create the subdirectory if needed, but **always state the proposed path and wait for user confirmation before writing** (Ask-Before-Persist gate from Tier 0). The defaults above are suggestions, not commitments.

### Claude-native data paths (read-only for plume)

| Path | Content |
|---|---|
| `~/.claude/projects/<slug>/*.jsonl` | Session transcripts (digest source of truth) |
| `~/.claude/projects/<slug>/memory/MEMORY.md` | Auto-memory index (Claude native) |

`slug = pwd | sed 's|/|-|g'` (keeps leading dash).

## Network Policy

After 2 consecutive timeout or connection failures on foreign resources (external URLs, non-local git remotes, package registries, etc.):
- **STOP retrying**.
- Tell the user: "连接超时，可能需要检查代理配置".
- Show the exact failed command.
- Wait for the user to handle the network issue manually.

Do not attempt automatic proxy configuration or URL rewrites.

## Privacy & Scope

Project data is isolated by Claude project slug (`pwd | sed 's|/|-|g'`). Each project's data lives under `~/.claude/projects/<slug>/`.

`digest` uses `--scope <keyword>` to aggregate across projects whose slug contains the keyword as a substring. Different scopes produce separate reports, providing natural isolation between work/personal/client contexts.

## Optional Wrapper Extension Pattern

**Not used by default in v3.** Plume's own skills (`using-plume`, `code-review`, `socratic-dialogue`, `digest`) are standalone. This pattern is documented only for the case where you want to integrate an external/community skill under plume's governance with project-level customizations.

To create a wrapper:

```markdown
---
name: <external-skill-name>
description: "<your trigger phrasing>"
---

<PLUME-OVERRIDE>
# Project-level customizations, these win on conflicts:
- Locale: <from $PLUME_ROOT/config.yml>
- Output path: <where to save>
- Any other overrides
</PLUME-OVERRIDE>

Read and follow the external skill's complete content:
`<absolute path to external SKILL.md>`

Conflict resolution: PLUME-OVERRIDE wins; otherwise follow external skill as-is.
```

Place wrappers in `skills/<wrapper-name>/SKILL.md` alongside plume's own skills. The harness will auto-list them. No change to `install.sh` needed — symlink deployment handles new skill directories automatically on `--update`.
