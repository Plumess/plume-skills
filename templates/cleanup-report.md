# Cleanup Report

Data size: X MB / Y MB limit

## Recommended Cleanup

| # | Project | Last Active | Size | Snapshots | Summary |
|---|---------|-------------|------|-----------|---------|
| 1 | MelodyLM | 15 days ago | 45 MB | 8 | MCP 重写 + 编排器优化 |
| 2 | old-test | 60 days ago | 12 MB | 3 | 测试项目，已废弃 |

## Options

1. Delete all recommended (plume-context/ dirs + orphaned jsonl)
2. Select specific items (enter numbers, e.g. "1,3,5")
3. Cancel

<!--
TEMPLATE NOTES
==============
- Two candidate sources, merged with dedup (staleness priority):
  1. Stale: most recent jsonl modified >30 days ago, sorted oldest first
  2. Largest: top 10 by total size (plume-context/ + jsonl)
- Summary: from CONTEXT-INDEX.md Current State, or latest snapshot first line, or "No summary"
- On delete: remove plume-context/ entirely; ask user about jsonl deletion separately
- NEVER delete memory/MEMORY.md — that's Claude's persistent memory
-->
