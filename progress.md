# plume-skills 剩余工作

基础框架（Phase 0-8a）已完成。以下是已完成和待验证的工作。

---

## 一、自定义 Skills 实现 ✅

### 1. context-keeper — 上下文生存系统 ✅

- [x] Iron Law + Red Flags + Rationalization Prevention
- [x] Verification Gates（SAVE/RESTORE）
- [x] Failure Modes（6 种）
- [x] LATEST.md 轻量索引（≤400 token）
- [x] 保存机制：用户请求 + `[CONTEXT-SAVE-RECOMMENDED]` hook 信号（≥15 轮），取消自主判断保存
- [x] 恢复机制：PreCompact marker → UserPromptSubmit 注入 `[CONTEXT-RECOVERY]`；fallback 无 PLUME_ROOT 时从 symlink 推导
- [x] Tags：`category:value` 格式 + config.yml 约束词表
- [x] Locale：timezone 影响时间戳，language 影响文档语言
- [x] 计数器重置：SAVE Step 8 重置 `.msg-count`

### 2. digest — 会话整理与报告系统 ✅

- [x] Iron Law + Red Flags + Rationalization Prevention
- [x] Verification Gates
- [x] Failure Modes（7 种）
- [x] 日报 scope 隔离 + 一天一份（跨项目聚合）
- [x] 研究报告：**自然语言触发**（不要求 tag 原名），无参数时展示 tag 聚类供选择
- [x] Tags Index：context-keeper 维护，digest 消费，rebuild-index 可重建
- [x] 自动感知双模式（HINT/AUTO）+ remind_at 时间窗口 + segments ≥3
- [x] Locale：timezone 用于时间窗口计算，language 用于报告语言
- [x] 模板提取：`templates/daily-report.md` + `templates/research-report.md`

---

## 二、Wrapper 输出路径统一 ✅

```
data/
├── journal/          # digest 日报（跨项目）
├── reports/          # digest 研究报告
├── <slug>/           # 项目工作数据
│   ├── segments/     # context-keeper
│   ├── LATEST.md     # context-keeper 索引
│   ├── tags-index.md      # context-keeper 倒排索引
│   ├── .msg-count    # hook 消息计数器
│   ├── specs/        # brainstorming 输出
│   └── plans/        # writing-plans 输出
```

- [x] brainstorming / brainstorming-universal → `data/<slug>/specs/` + locale
- [x] writing-plans → `data/<slug>/plans/` + locale
- [x] executing-plans → 读取 `data/<slug>/plans/` + `data/<slug>/specs/`
- [x] context-keeper → segment Artifacts 含 specs/plans
- [x] digest → 日报扫描 specs/plans，输出到 `data/journal/` + `data/reports/`
- [x] using-plume → Paths 表格完整，含 journal/reports

---

## 三、额外增强 ✅

- [x] **config.yml locale**：`timezone: Asia/Shanghai` + `language: zh-CN`，所有文档生成 skill 引用
- [x] **config.yml context.save_remind_after**：控制消息计数阈值（默认 15）
- [x] **user-prompt-submit hook 消息计数器**：每轮 +1，达阈值注入 `[CONTEXT-SAVE-RECOMMENDED]`
- [x] **Git wrapper override**：finishing-a-development-branch + using-git-worktrees → 仅用户主动请求触发 + 操作前展示 Git 方案总览
- [x] **using-plume compact fallback**：无 `[PLUME_ROOT: ...]` 时从 symlink/settings 推导路径并恢复
- [x] **using-plume 代理提醒**：非中国境内资源下载超时 2 次后停止，提示用户检查代理
- [x] **digest 自然语言 report**：`/digest report <自然语言>` 语义匹配 tags，无参数展示聚类
- [x] **模板 locale 标注**：daily-report.md + research-report.md 均含语言/时区提示

---

## 四、实际会话验证（Phase 8b）

在真实 Claude Code 会话中逐项验证。每项列出具体操作步骤和预期结果。

### 8b-1. 部署与 hook 注入

**前置**：执行 `./install.sh --universal` + `./install.sh --project <test-project>`。

**验证步骤**：
1. 启动新 Claude Code 会话（在 test-project 目录下）
2. 观察 Claude 首条响应——应体现 using-plume 引导已注入
3. 对 Claude 说「你知道哪些 plume skills？」
   - 预期：列出 brainstorming、context-keeper、digest 等
4. 对 Claude 说「读取 using-plume 的 SKILL.md 看看路径表格」
   - 预期：Paths 表格含 segments/specs/plans/journal/reports

**通过标准**：Claude 知道 plume 框架，能正确引用 PLUME_ROOT。

### 8b-2. Brainstorming wrapper override

1. 在项目 Claude 会话中说「帮我设计一个用户通知系统」
2. Claude 自动触发 brainstorming（项目版，严格触发）
3. 检查读取链路：wrapper → vendor SKILL.md
4. Spec 输出路径 = `$PLUME_ROOT/data/<slug>/specs/YYYY-MM-DD-notification-design.md`
5. Spec review 后停下等确认

**通过标准**：override 生效，输出到 `data/<slug>/specs/`，文档为中文。

### 8b-3. Writing-plans + executing-plans 衔接

1. Spec 确认后说「approved，请制定实施计划」
2. Writing-plans 从 `data/<slug>/specs/` 读取 spec
3. Plan 输出到 `data/<slug>/plans/`，文档为中文
4. 新会话：「执行 notification 实施计划」
5. Executing-plans 从 `data/<slug>/plans/` 读取 plan

**通过标准**：三级衔接路径全部正确。

### 8b-4. Context-keeper SAVE

1. 做实质工作后说「保存上下文」
2. 检查：segment 文件（时间戳 Asia/Shanghai）、LATEST.md（≤400 token）、tags-index.md
3. Tags 优先使用 config.yml 词表，内容为中文
4. `.msg-count` 被重置为 0
5. 再做工作再保存，检查累积增长

**通过标准**：三文件正确生成 + 计数器重置。

### 8b-5. SAVE 自动提醒

1. 保存后连续发 15+ 条消息（不主动保存）
2. 第 15 条后，Claude 回复中应响应 `[CONTEXT-SAVE-RECOMMENDED]` 执行保存
3. 保存完成后检查 `.msg-count` 重置

**通过标准**：hook 计数器触发保存，不过于频繁也不遗漏。

### 8b-6. Context-keeper RESTORE（模拟 compact）

1. 确保有 ≥2 segments 和 LATEST.md
2. 创建 compact marker：
   ```bash
   slug=$(pwd | sed 's|^/||; s|/|-|g')
   echo "slug=$slug" > $PLUME_ROOT/data/.compact-marker
   echo "timestamp=$(date +%Y-%m-%dT%H-%M)" >> $PLUME_ROOT/data/.compact-marker
   ```
3. 发送任意消息 → hook 注入 `[CONTEXT-RECOVERY]`
4. Claude 读取 LATEST.md 索引并汇报，不读全部 segments
5. 根据 Next Step 继续工作

**通过标准**：marker → inject → RESTORE → 自动恢复。

### 8b-7. RESTORE fallback（无 LATEST.md）

1. 删除 LATEST.md（保留 segments）
2. 重复 8b-6 marker 操作
3. Claude fallback：读最近 3 个 segments → 重建 LATEST.md

**通过标准**：fallback 正常工作。

### 8b-8. Digest daily

1. 确保 ≥3 segments（可跨项目），配置 `default_scope`
2. 说 `/digest daily`
3. Claude 展示 scope 涵盖的项目和 segment 数量
4. 确认后生成 `data/journal/YYYY-MM-DD.md`
5. 检查：中文内容、时间用 Asia/Shanghai、模板结构完整

**通过标准**：日报在 `data/journal/`，scope 隔离正确。

### 8b-9. Digest report（自然语言）

1. 确保 segments 含相关 tags
2. 说 `/digest report 用户认证相关工作`（不用 tag 原名）
3. Claude 语义匹配 → 读取相关 segments → 生成 `data/reports/auth.md`
4. 也测试 `/digest report`（无参数）→ 展示聚类供选择

**通过标准**：自然语言触发正确，无参数展示聚类。

### 8b-10. Digest auto-sense

1. 配置 `remind_at` 为当前时间附近，`auto_generate: false`
2. 确保 ≥3 今日 segments + 无日报
3. 发消息 → `[DIGEST-HINT]` → Claude 提示可生成日报
4. 改 `auto_generate: true`，删除 hint marker
5. 发消息 → `[DIGEST-AUTO]` → Claude 自动执行

**通过标准**：HINT 仅提示，AUTO 自动执行。

### 8b-11. Git wrapper

1. 在项目中做一些代码修改
2. 说「帮我提交一下」
3. Claude 应展示 Git 操作方案总览，等待确认
4. 确认后执行，不应有未经确认的 git 操作

**通过标准**：方案总览 + 用户确认后执行。

### 8b-12. Network proxy 提醒

1. 故意用一个超时的国外 URL 让 Claude 执行下载
2. 第 2 次失败后 Claude 停止重试
3. 提示用户检查代理 + 显示失败命令

**通过标准**：2 次失败后停止，给出命令让用户自行操作。

### 8b-13. Archive 完整性

1. data/ 有完整数据（slug + journal + reports）
2. `./install.sh archive <keyword>` → 检查 tar.gz 结构
3. `./install.sh archive --all` → 全量包含 journal/ + reports/

**通过标准**：archive 完整，解压后可消费。

---

## 五、待调研

- [ ] **PreCompact hook 可靠性分析**：调研 Claude Code PreCompact 事件的触发条件、已知问题、是否稳定可依赖
