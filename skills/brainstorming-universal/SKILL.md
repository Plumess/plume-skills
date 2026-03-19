---
name: brainstorming
description: "Use when the user explicitly requests brainstorming, design exploration, or structured ideation — e.g. /brainstorm, 'let's brainstorm', 'help me design'. NOT auto-triggered in general conversation."
---

<PLUME-OVERRIDE>
The following directives take priority over the vendor skill. Anything not mentioned here follows the vendor skill as-is.

- **Activation**: This is the universal (non-project) version. Only activate when the user explicitly asks.
- **Locale**: Read `$PLUME_ROOT/config.yml` → `locale.language`. Write spec documents in this language. Timestamps use `locale.timezone`.
- **Output path**: `<project-root>/docs/plume-skills/specs/YYYY-MM-DD-<topic>-design.md`
  - `<project-root>` = current working directory (the project being worked on)
  - Create `docs/plume-skills/specs/` directory if it doesn't exist
  - Do NOT write to `docs/superpowers/` or `docs/plume/`
- **Gate**: After spec review is complete: STOP and wait for explicit user approval.
</PLUME-OVERRIDE>

Now read and follow the vendor skill's complete content:

1. Use the Read tool to read: `PLUME_ROOT/vendor/superpowers/brainstorming/SKILL.md` (replace PLUME_ROOT with the path from `[PLUME_ROOT: ...]` in your session context)
2. Follow all instructions in that file
3. Where the vendor skill conflicts with `<PLUME-OVERRIDE>` above, the override wins
4. Everything else: follow the vendor skill exactly
