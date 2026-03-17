---
name: executing-plans
description: "Use when you have a written implementation plan to execute in a separate session with review checkpoints"
---

<PLUME-OVERRIDE>
The following directives take priority over the vendor skill. Anything not mentioned here follows the vendor skill as-is.

- Plan file location: `$PLUME_ROOT/data/<slug>/plans/` (NOT `docs/superpowers/plans/`)
  - `<slug>` = current working directory with leading `/` removed, `/` replaced by `-`
  - `PLUME_ROOT` from `[PLUME_ROOT: ...]` in session context
  - When the vendor skill references plan files, look in this directory instead
- Design spec location: `$PLUME_ROOT/data/<slug>/specs/` (for cross-referencing approved designs)
</PLUME-OVERRIDE>

Now read and follow the vendor skill's complete content:

1. Use the Read tool to read: `PLUME_ROOT/vendor/superpowers/executing-plans/SKILL.md` (replace PLUME_ROOT with the path from `[PLUME_ROOT: ...]` in your session context)
2. Follow all instructions in that file
3. Where the vendor skill conflicts with `<PLUME-OVERRIDE>` above, the override wins
4. Everything else: follow the vendor skill exactly
