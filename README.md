<p align="center">
  <h1 align="center">Plume-Skills</h1>
  <p align="center">
    <strong>Give your Claude Code a readable session history, a workflow that ships, and a diary on cron.</strong>
  </p>
  <p align="center">
    Built on <a href="https://github.com/obra/superpowers">superpowers</a> &nbsp;|&nbsp; Session history &nbsp;|&nbsp; Daily reports
  </p>
</p>

---

> plume-skills 基于 [obra/superpowers](https://github.com/obra/superpowers) 的 12 个开发工作流 skills，通过 wrapper 模式进行定制扩展

> 并新增会话历史索引和日报生成能力，整合为一个统一框架。Symlink 部署，零侵入、零依赖、幂等安装


**核心特点**：

- **Wrapper 定制** — 不修改 vendor 原文，通过 `<PLUME-OVERRIDE>` 按需覆盖输出路径、流程门控、locale 等
- **Context Keeper** — 自研。将 Claude 原生 jsonl 转化为人类可读的结构化摘要和跨会话时间线索引
- **Digest** — 自研。从 Claude 原生会话数据生成跨项目日报和研究报告，scope 隔离隐私，支持 cron 定时自动生成

## 安装

### 场景 A：个人机器（标准安装）

核心 skills 部署到用户级 `~/.claude/`，对所有项目生效；工作流 skills 按项目安装。

```bash
git clone https://github.com/Plumess/plume-skills.git ~/plume-skills && cd ~/plume-skills

# 核心 skills + hooks（安装过程会交互式配置 scope 和 cron 时间）
./install.sh --core

# 为项目安装工作流 skills（superpowers wrapper 套件）
./install.sh --project ~/project-a

# 可选：配置日报定时生成（写入 crontab）
./install.sh cron
```

部署效果：
```
~/.claude/
├── skills/
│   ├── using-plume → ~/plume-skills/skills/using-plume
│   ├── context-keeper → ~/plume-skills/skills/context-keeper
│   ├── digest → ~/plume-skills/skills/digest
│   ├── brainstorming → ~/plume-skills/skills/brainstorming-universal
│   ├── find-skills → ~/plume-skills/vendor/find-skills
│   └── skill-creator → ~/plume-skills/vendor/skill-creator
└── settings.local.json  ← hooks + 权限

~/project-a/.claude/
├── skills/
│   ├── brainstorming → ~/plume-skills/skills/brainstorming
│   ├── writing-plans → ~/plume-skills/skills/writing-plans
│   └── ...（12 个工作流 skills）
└── settings.local.json  ← 权限
```

### 场景 B：共享服务器（项目级隔离）

在共享账户（如公共服务器的 root）上，核心 skills 不能装到 `~/.claude/`（会影响同账户下所有用户）。使用 `--base` 将核心 skills 部署到项目目录下，仅对该项目生效。

```bash
cd /root/plume/plume-skills

# 核心 skills 部署到项目级 .claude/（安装器会建议使用目录名作为 scope）
./install.sh --core --base /root/plume

# 工作流 skills 部署到项目级
./install.sh --project /root/plume

# 可选：配置日报定时生成
./install.sh cron
```

部署效果：
```
/root/plume/.claude/
├── skills/
│   ├── using-plume → /root/plume/plume-skills/skills/using-plume
│   ├── context-keeper → ...
│   ├── digest → ...
│   ├── brainstorming → ...（核心 + 工作流全部在此）
│   ├── writing-plans → ...
│   └── ...
└── settings.local.json  ← hooks + 权限（合并）

~/.claude/  ← 不受任何影响
```

仅在 `/root/plume` 目录下启动的 Claude 会话才会加载这些 skills。

### 更新与维护

Skills 内容通过 symlink 指向仓库文件，`git pull` 后自动生效。`--update` 和 `--repair` 处理部署层面的变化（hooks、权限、迁移）。

```bash
# 日常更新（无论跨了多少版本，一条命令搞定）
git pull && ./install.sh --update [--base <path>]

# 或者直接再次 --core — 检测到已有安装时自动进入更新模式
git pull && ./install.sh --core [--base <path>]

# 搬迁目录后全量修复
./install.sh --repair [--base <path>]
```

**`--update`（增量同步）**：

1. **Skills**：补齐新增 symlink，修复断链（已有的不动）
2. **Hooks**：用当前模板整体替换 settings.local.json 中的 `hooks` 字段 — 旧版 hooks 自动移除
3. **权限**：三方 diff — 比对「上次安装快照」与「当前模板」的差异，只增删 plume 自己的条目，用户自定义权限完全不动
4. **迁移**：幂等检查清单，清理旧版遗留（废弃的 marker 文件、config 字段等）
5. **Config**：更新 `plume_root` 为当前路径

**`--repair`（全量重建）**：

与 `--update` 的区别在于 symlinks 是**全部删除并重建**（而非增量），hooks 也完整替换。适用于目录搬迁或部署状态不确定时。

**`--core` 自动检测**：如果目标目录已有 plume-skills 安装，`--core` 会自动跳转到 `--update` 模式，无需手动切换。

**跨版本升级**：`git pull && ./install.sh --update` 一步到位。三方 diff 和迁移逻辑都是幂等的检查清单，每项独立检测、按需执行，中间版本不需要逐个经过。

所有部署**幂等** — 重复执行无副作用。

### 命令速查

| 命令 | 作用 |
|------|------|
| `--core [--base <path>]` | 首次安装核心 skills + hooks + 权限（已有安装时自动进入 update） |
| `--project <path>` | 部署 12 个工作流 skills + 权限到项目 |
| `--update [--base <path>]` | 增量同步 skills、hooks、权限（三方 diff）+ 旧版迁移 |
| `--repair [--base <path>]` | 全量重建 symlinks + hooks 替换 + 旧版迁移 |
| `cron [HH:MM]` | 写入日报 cron 到 crontab（读取 config scope + 时区自动转换） |
| `archive <keyword\|--all>` | 归档项目数据用于迁移 |
| `--dry-run` | 预览不执行（可与其他命令组合） |

## 目录结构

```
plume-skills/
├── skills/                           # 自研 3 + wrapper 13 + 社区 2
│   ├── using-plume/                  #   框架引导（hook 自动注入）
│   ├── context-keeper/               #   会话历史摘要与索引
│   ├── digest/                       #   日报与研究报告
│   ├── brainstorming-universal/      #   通用 brainstorming（显式激活）
│   ├── brainstorming/                #   项目 brainstorming（严格自动触发）
│   ├── writing-plans/                #   实施计划（定制：输出路径 + locale）
│   ├── executing-plans/              #   执行计划（定制：读取路径）
│   ├── finishing-a-development-branch/ # 分支收尾（定制：Git 方案展示）
│   └── ...                           #   其余 8 个工作流 wrapper
│
├── vendor/                           # 社区 skills 原文（git 追踪，不直接部署）
│   ├── superpowers/                  #   obra/superpowers
│   ├── find-skills/                  #   vercel-labs/skills
│   └── skill-creator/                #   anthropics/skills
│
├── hooks/                            # SessionStart / UserPromptSubmit
├── templates/                        # wrapper / 报告 / git-plan 模板
├── config.yml                        # 全局配置（locale、scope、cron）
├── install.sh                        # 部署器（幂等，支持 --update 一键同步）
└── data/                             # 运行时数据（gitignored）
    ├── journal/                      #   日报（跨项目）
    └── reports/                      #   研究报告
```

**上下文数据**存储在 Claude 项目目录 `~/.claude/projects/<slug>/plume-context/`，不在 plume-skills 内。

**项目产出**（specs、plans）存储在各项目的 `docs/plume-skills/` 下。

## Context Keeper

> 会话历史可读化工具。Claude 原生 jsonl 是完整记录但不可直接阅读，context-keeper 生成结构化摘要和跨会话时间线索引。

### 用法

```bash
# 保存当前会话摘要（完成阶段性工作时）
/save

# 查看会话历史时间线
# 告诉 Claude "回顾历史" / "review history"
```

- **SAVE** — 从当前上下文生成结构化快照，更新时间线索引
- **REVIEW** — 展示跨会话时间线，支持按会话深入查看
- **CLEANUP** — 管理快照数据量，超过阈值时推荐清理候选

### 清理

当快照 + jsonl 数据量超过配置阈值（默认 500MB）时，`context-keeper cleanup` 按"最久未更新"和"最大体积"推荐清理候选，支持一键删除或选择性删除。永远不删 MEMORY.md。

### 存储

```
~/.claude/projects/<slug>/plume-context/
├── CONTEXT-INDEX.md                      # 全历史时间线索引
└── sessions/
    └── <id>-<YYYYMMDD-HHMM>.md           # 会话快照
```

## Digest

> 从 Claude 原生数据（jsonl + session snapshots + MEMORY.md）生成日报和研究报告。手动触发或通过 cron 定时生成。

### Scope

Scope 是日报的项目过滤机制。`~/.claude/projects/` 下每个项目有一个 slug 目录（如 `-root-plume`、`-home-user-project-a`），scope 关键词对这些目录名做**子串匹配**。

例如 `scope = "plume"`：
- 匹配 `-root-plume`、`-root-plume-project-a` ✓
- 不匹配 `-home-user-other-project` ✗

不同 scope 的日报互不干扰，天然隔离公司/个人项目。`--core` 安装时会交互式配置，默认建议使用安装路径的目录名（`--base` 时用 base 目录名，全局安装时用 `$HOME` 目录名）。

### 日报

```bash
/digest daily                         # 今日日报（default_scope）
/digest daily 2026-03-15              # 指定日期
/digest daily --scope plume           # 指定作用域
```

- **一天一份，跨项目聚合** — scope 下所有项目当天活跃会话
- **区间重叠匹配** — 通过 jsonl 首条消息时间和 mtime 判断会话是否在目标日期活跃，跨天长会话不会遗漏
- **数据源优先级** — session snapshots > CONTEXT-INDEX.md > jsonl 尾部
- **输出** — `data/journal/YYYY-MM-DD.md`

### 研究报告

```bash
/digest report 用户认证相关的工作      # 自然语言，语义匹配
/digest report                         # 展示话题聚类供选择
```

- **自然语言触发** — 从 CONTEXT-INDEX.md 和 session snapshots 语义匹配
- **已有报告更新** — 文件存在时确认：智能合并 / 覆盖 / 另存 / 取消
- **输出** — `data/reports/<topic>.md`

### 定时生成

```bash
# 写入 cron 到 crontab（读取 config 的 default_scope + cron_time + timezone）
./install.sh cron

# 指定时间（同时更新 config.yml 中的 cron_time）
./install.sh cron 21:00
```

**工作原理**：

1. 读取 config 的 `digest.cron_time`（默认 09:00）+ `locale.timezone`，用算术转换为本机时间写入 crontab，不修改系统时区
2. 生成的 cron 命令以 `claude -p "/digest daily <yesterday> --scope <scope>"` 的形式调用 Claude CLI
3. crontab 条目带 `# plume-skills-digest:<scope>` 标记，同 scope 重复执行是更新而非追加
4. 每个 plume-skills 安装实例有独立的 config 和 `data/`，不同目录/用户的日报天然隔离
5. 修改 scope 或时间后重新运行 `./install.sh cron` 即可更新 crontab

## Wrapper 模式

所有工作流 skills 通过 wrapper 间接引用 vendor 原文。定制只需编辑 `<PLUME-OVERRIDE>` 块：

```markdown
<PLUME-OVERRIDE>
- Output path: <project-root>/docs/plume-skills/specs/
- Gate: wait for user approval after spec review
</PLUME-OVERRIDE>

→ Read PLUME_ROOT/vendor/superpowers/brainstorming/SKILL.md
→ Override wins where conflicts exist; vendor as-is elsewhere
```

新建 wrapper 参考 `templates/wrapper-skill.md`。

## 配置

```yaml
# config.yml
plume_root: /path/to/plume-skills      # install.sh 自动设置

locale:
  timezone: "Asia/Shanghai"               # 时间戳、日报日期、cron 时区转换基准
  language: "zh-CN"                       # 生成文档语言

context:
  max_data_size_mb: 500                   # 快照数据量上限，超过时提醒清理

digest:
  default_scope: ""                       # 日报作用域（--core 安装时交互式配置）
  cron_time: "09:00"                      # 日报 cron 触发时间（config 时区）
```

`--core` 安装时会交互式提示配置 `default_scope` 和 `cron_time`。scope 默认建议使用安装路径的目录名（`--base /root/plume` → `"plume"`），用户可手动输入自定义值，也可后续编辑 config.yml 修改。

## 模板

| 文件 | 用途 |
|------|------|
| `templates/wrapper-skill.md` | Wrapper 骨架 + 编写指南 |
| `templates/session-snapshot.md` | Context Keeper 快照格式 |
| `templates/context-index.md` | Context Keeper 索引格式 |
| `templates/cleanup-report.md` | 快照清理报告格式 |
| `templates/daily-report.md` | 日报结构 |
| `templates/research-report.md` | 研究报告结构 |
| `templates/git-plan.md` | Git 操作方案（提交前展示） |

## 致谢

工作流 skills 构建在优秀的社区开源工作之上：

- **[superpowers](https://github.com/obra/superpowers)** by Jesse Vincent — 从头脑风暴到代码审查的完整开发工作流 skills 体系。12 个工作流 skills 均源自此项目，部分通过 wrapper 定制。
- **[skills](https://github.com/vercel-labs/skills)** by Vercel — find-skills，发现和安装社区 skills。
- **[skills](https://github.com/anthropics/skills)** by Anthropic — skill-creator，从零创建自定义 skills。

上下文管理设计参考：
- **[context-mode](https://github.com/mksglu/context-mode)** — 累积事件 + 优先级分层
- **[memsearch](https://github.com/zilliztech/memsearch)** — Markdown append-only 记忆管理

## 许可证

[Apache License 2.0](LICENSE)

| vendor 来源 | 原始许可证 |
|-------------|-----------|
| [obra/superpowers](https://github.com/obra/superpowers) | MIT |
| [vercel-labs/skills](https://github.com/vercel-labs/skills) | MIT |
| [anthropics/skills](https://github.com/anthropics/skills) | Apache 2.0 |

vendor/ 中的内容已精简，仅保留本项目所需部分。完整内容请访问源仓库。
