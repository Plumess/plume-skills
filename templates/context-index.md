# Context Index: <project-name>
<!-- last-updated: YYYY-MM-DDTHH:MM -->
<!-- total-snapshots: N -->

## Current State
[Active task and next step from the most recent snapshot]

## Session Timeline
| Date | Session | Timestamp | Snapshot | Focus | Key Outcomes |
|------|---------|-----------|----------|-------|--------------|
| 03-19 | ef0c98 | 20260319-1435 | primary ✓ | MCP IntentRouter rewrite | design complete |
| 03-18 | 844f19 | 20260318-1420 | primary ✓ | prompt optimization | experiments done |

## Accumulated Decisions
- [Key decisions from all snapshots, deduplicated]

## Architecture Notes
- [Key patterns and conventions discovered across sessions]

<!--
TEMPLATE NOTES
==============
- **Language**: config.yml → locale.language (default: zh-CN)
- Sort by date descending (newest first)
- **Snapshot column**: "primary ✓" = `<id>-<marker-id>.md` exists and is the one to load.
  "fallback" = only `<id>-<marker-id>-fallback.md` exists (primary never written — compact fired before save completed).
  Same marker-id = same content window; primary always wins.
- One row per timestamp (content window). No duplicate content across rows.
- ≤1500 tokens hard limit — this is an INDEX, details live in snapshots
- Accumulated Decisions: deduplicate, keep most recent version if conflicting
- Architecture Notes: stable patterns confirmed across multiple sessions
-->
