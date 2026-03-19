# Session Snapshot
<!-- session: <full-uuid> -->
<!-- project: /absolute/path/to/project -->
<!-- timestamp: YYYY-MM-DDTHH:MM (in configured timezone) -->
<!-- quality: full | compact-summary -->
<!-- seq: 001 -->

## Summary
[2-3 paragraphs: what was accomplished, approach taken, outcome/current state.
Cover the ENTIRE session up to this point, not just recent work.]

## Key Changes
- `path/to/file` — what changed and why

## Decisions
- [Decision]: [what was chosen] — [reasoning/trade-offs]

## Current State
- Active task: [what is in progress]
- Next step: [the immediate next action]
- Blockers: [if any]

## Open Questions
- [Unresolved questions, if any]

<!--
TEMPLATE NOTES
==============
- **Language**: config.yml → locale.language (default: zh-CN)
- **Timezone**: config.yml → locale.timezone (default: Asia/Shanghai)
- **quality**: `full` for URGENT saves (001, complete context), `compact-summary` for RECOVERY saves (002+)
- **Summary**: cover the ENTIRE session, not just recent work
- **Key Changes**: only list files actually created/modified, with brief reason
- **Decisions**: include reasoning — "what" without "why" is useless for recovery
- **Current State**: must be concrete enough to resume work without re-asking user
-->
