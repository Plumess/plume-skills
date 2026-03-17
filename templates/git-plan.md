# Git 操作方案

<!--
TEMPLATE NOTES
==============
- **Language**: Use config.yml → locale.language (default: zh-CN)
- 以下为 Git 操作方案的标准结构，Claude 在执行任何 git 写操作前必须先生成此方案并等待用户确认
- 根据实际情况裁剪章节：单仓库可省略仓库状态总结表；无 merge 可省略第二步；无 push 可省略第三步
- 每个 commit message 必须完整展示，不允许省略号或"等"
-->

## 仓库状态总结

<!-- 多仓库时用表格，单仓库用简要文字描述 -->

| 仓库 | main HEAD | dev 领先 main (committed) | 未提交变更 |
|------|-----------|--------------------------|-----------|
| repo-name | `abc1234` | N files (+X/-Y, 简要描述) | M files (简要描述) |

## 第一步：提交 (Commits)

<!-- 按仓库分组，每个 commit 列出：编号、完整 commit message、涉及文件和变更摘要 -->

### 1A. repo-name (N commits)

**Commit 1:**

```
<type>: <简明描述>

<详细说明：涉及模块、修改原因、关键变更点>

涉及模块:
- module-a: 具体变更
- module-b: 具体变更
```

涉及文件:
- `path/to/file1` — 变更说明
- `path/to/file2` — 变更说明

---

## 第二步：合并 (Merge)

<!-- 仅在需要 merge 时出现。说明合并策略（squash/rebase/merge commit）和合并范围 -->

### 2A. repo-name

合并策略: squash merge dev → main
合并范围: 描述 dev 上自 main 以来的累积变更

```
<type>: <合并 commit message>

<详细变更列表>
```

---

## 第三步：推送 (Push)

<!-- 仅在需要 push 时出现。列出所有 push 命令 -->

```bash
cd repo-name
git push origin dev
git push origin main
```

---

## 确认

以上为完整 Git 操作方案。需要我开始执行吗？

<!--
RULES
=====
1. 方案展示后必须等待用户明确确认（"好的"、"执行"、"开始"等）才能开始操作
2. 用户未确认前，不得执行任何 git write 操作（commit, merge, rebase, push, tag, branch -d 等）
3. git read 操作（status, diff, log, branch, remote -v 等）在方案制定阶段可自由执行
4. 如果用户要求修改方案，重新生成完整方案并再次等待确认
5. 执行过程中遇到冲突或错误，立即停止并报告，不自行解决
6. commit message 规范：
   - type: feat / fix / refactor / docs / test / chore / perf / ci / sync
   - 主题行 ≤ 72 字符
   - body 使用中文（或 locale.language 配置的语言）
   - 多模块变更时按模块分组列出
7. 单仓库简单提交可精简格式，但核心结构不变：状态 → 方案 → 确认 → 执行
-->
