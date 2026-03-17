---
name: writing-plans
description: "Use when a design spec has been approved and you need to create an actionable implementation plan. Break work into small, verifiable tasks."
---

<PLUME-OVERRIDE>
The following directives take priority over the vendor skill. Anything not mentioned here follows the vendor skill as-is.

- **Locale**: Read `$PLUME_ROOT/config.yml` → `locale.language`. Write plan documents in this language. Timestamps use `locale.timezone`.
- **Output path**: `$PLUME_ROOT/data/<slug>/plans/YYYY-MM-DD-<topic>.md`
  - `<slug>` = current working directory with leading `/` removed, `/` replaced by `-`
  - `PLUME_ROOT` from `[PLUME_ROOT: ...]` in session context
  - Create `plans/` directory if it doesn't exist
  - Do NOT write to `docs/superpowers/` or `docs/plume/`
- **Task granularity**: each task should be completable within a focused work block (roughly half a day). Avoid both too-fine (5 min) and too-coarse (multi-day) tasks.
- Plan must reference the approved design spec from `$PLUME_ROOT/data/<slug>/specs/` if one exists.
</PLUME-OVERRIDE>

Now read and follow the vendor skill's complete content:

1. Use the Read tool to read: `PLUME_ROOT/vendor/superpowers/writing-plans/SKILL.md` (replace PLUME_ROOT with the path from `[PLUME_ROOT: ...]` in your session context)
2. Follow all instructions in that file
3. Where the vendor skill conflicts with `<PLUME-OVERRIDE>` above, the override wins
4. Everything else: follow the vendor skill exactly
