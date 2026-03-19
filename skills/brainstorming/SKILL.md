---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, designing systems, or modifying behavior. Engage in structured exploration before committing to an approach."
---

<PLUME-OVERRIDE>
The following directives take priority over the vendor skill. Anything not mentioned here follows the vendor skill as-is.

- **Locale**: Read `$PLUME_ROOT/config.yml` → `locale.language`. Write spec documents in this language. Timestamps use `locale.timezone`.
- **Output path**: `<project-root>/docs/plume-skills/specs/YYYY-MM-DD-<topic>-design.md`
  - `<project-root>` = current working directory (the project being worked on)
  - Create `docs/plume-skills/specs/` directory if it doesn't exist
  - Do NOT write to `docs/superpowers/` or `docs/plume/`
- **Gate**: After spec review is complete: STOP and wait for explicit user approval before proceeding to writing-plans or any implementation. Do NOT auto-transition.
- If the user says "looks good" or "approved", only then proceed to the next phase.
</PLUME-OVERRIDE>

Now read and follow the vendor skill's complete content:

1. Use the Read tool to read: `PLUME_ROOT/vendor/superpowers/brainstorming/SKILL.md` (replace PLUME_ROOT with the path from `[PLUME_ROOT: ...]` in your session context)
2. Follow all instructions in that file
3. Where the vendor skill conflicts with `<PLUME-OVERRIDE>` above, the override wins
4. Everything else: follow the vendor skill exactly
