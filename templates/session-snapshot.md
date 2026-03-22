# Session Snapshot
<!-- session: <full-uuid> -->
<!-- project: /absolute/path/to/project -->
<!-- timestamp: YYYY-MM-DDTHH:MM (in configured timezone) -->
<!-- ts: <YYYYMMDD-HHMM> (filename timestamp, same as marker) -->

## Summary
[2-3 paragraphs: what was accomplished, approach taken, outcome/current state.
Cover the ENTIRE session up to this point, not just recent work.]

## Key Changes
<!-- List files actually created/modified. These serve as index pointers for later recovery. -->
- `path/to/file` — what changed and why

## Code & Doc Index
<!-- Searchable pointers into the codebase. Use function/class names, section titles, config keys. -->
- `path/to/file:line` — [function/class/section name]: brief description
- `path/to/config` — [key]: value or purpose

## Decisions
- [Decision]: [what was chosen] — [reasoning/trade-offs]

## Current State
- Active task: [what is in progress]
- Next step: [the immediate next action]
- Blockers: [if any]

## Open Questions
- [Unresolved questions, if any]

## Recovery Hints
<!-- Keywords to grep in jsonl if uncertain about prior work. Format: keyword → what it reveals -->
- `keyword` → [what searching this term in jsonl would clarify]

<!--
TEMPLATE NOTES
==============
- **Language**: config.yml → locale.language (default: zh-CN)
- **Timezone**: config.yml → locale.timezone (default: Asia/Shanghai)
- **filename**: `<session-id>-<marker-id>.md` for primary saves (PreCompact or manual);
  `<session-id>-<marker-id>-fallback.md` for post-compact recovery.
  marker-id (YYYYMMDD-HHMM) is encoded in the `.save-pending-<sid>-<marker-id>` filename
  and carried in the signal text `[CONTEXT-SAVE-URGENT marker-id=<mid>]` — never from the current clock at recovery time.
  Manual saves without a marker generate marker-id from current time.
- **Primary vs fallback**: same marker-id = same content window. Index and RESTORE always prefer primary;
  fallback is only read if primary is missing.
- **Summary**: cover the ENTIRE session, not just recent work
- **Key Changes**: only list files actually created/modified, with brief reason
- **Code & Doc Index**: function names, class names, config keys — enables targeted jsonl grep during recovery
- **Decisions**: include reasoning — "what" without "why" is useless for recovery
- **Current State**: must be concrete enough to resume work without re-asking user
- **Recovery Hints**: 3-5 keywords max; pick terms unique enough to find relevant jsonl lines quickly
-->
