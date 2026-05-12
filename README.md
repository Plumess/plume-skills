<p align="center">
  <h1 align="center">Plume-Skills</h1>
  <p align="center">
    <strong>A lean Claude Code framework: behavior principles always-on, a few premium skills on demand.</strong>
  </p>
  <p align="center">
    Principles-first · Token-friendly · Scope-isolated install
  </p>
</p>

---

## 🎉 What's New in v3

**全新简化版** — 基于 最新 **harness**思想 + **Andrej Karpathy** 极简哲学，对原有框架做完全重构：

- **抛弃 wrapper 强制链路**：原 16 个 wrapper + 2 vendor 浓缩为 **1 份常驻原则 + 4 个自研 skill**
- **原则常驻取代 skill 堆叠**：karpathy 4 条核心原则 + Plume 3 条工作流原则 + Ask-Before-Persist gate 在 SessionStart 注入，Tier 0 永远在线
- **Skill 触发交给 harness**：不再手动维护 catalog，依赖 Claude Code 原生的 description 自动列出与匹配
- **Token 预算大幅下降**：常驻成本从 ~4K → **~1.2K tokens**（-70%）；调用一个 skill 的总成本从 ~7K → ~2.7K（-60%）
- **Scope 隔离 + 删除安全**：marker 文件确保多部署点互不干扰；任何删除都先列表后等用户 [y/N] 确认

详细设计演进、token 核算、风险审查见 [docs/slim-design.md](docs/slim-design.md)。

## 核心结构

```
Tier 0 （每 session 常驻，~900 tokens）
└── hooks/principles.md   — 7 条行为原则 + Ask-Before-Persist gate

Tier 1 （按需加载）
├── skills/using-plume/         — 框架机制（路径、网络、隐私、wrapper 扩展点）
├── skills/code-review/         — 基于三本经典的结构化审查（P0/P1/P2 分级）
├── skills/socratic-dialogue/   — 苏格拉底式三人设引导对话（显式触发）
└── skills/digest/              — 日报 / 研究报告（沿用，可 cron 自动）
```

没有 vendor，没有 wrapper 强制链路。所有工作流概念提炼进原则常驻；需要结构化输出或仪式感的工作才成为独立 skill。

## 原则（完整文本见 [hooks/principles.md](hooks/principles.md)）

> **Attribution** — Core principles 1–4 are adapted near-verbatim from **Andrej Karpathy's** observations on LLM coding pitfalls (via [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)). Principles 5–7 and the Ask-Before-Persist gate are Plume additions.

1. **Think Before Coding** — 先说假设 / 主动问 / 呈现权衡 / 不隐藏困惑
2. **Simplicity First** — 最小可行代码，不臆造抽象、不加未请求的灵活性
3. **Surgical Changes** — 每改一行都能追溯到用户请求；不顺手重构
4. **Goal-Driven Execution** — 把任务转成可验证的成功标准，循环至通过
5. **Plan-First for non-trivial work** — 非琐碎任务先给方案、获确认再拆步（默认 / `/brainstorm` / `/socratic` 三模式关键词区分）；**落盘前先确认保存路径**
6. **Completion Gate** — 宣告完成 / 提交前必须跑真实验证命令并展示输出
7. **Delegate with Intent** — 独立任务或研究用 subagent 派发，合并结果再汇报

**Ask-Before-Persist（通用 gate）** — 写任何文档 / 创建 commit / push 前，先报目标路径等用户确认。

## 部署模型：默认 base-level, 多 clone 天然隔离

```
git repo (唯一真相源)
  /path/to/plume-skills/

部署目标（按 scope-flag 区分, 每个 scope 自有 marker + symlinks 指向上面那一份源）：
  默认 (无旗)             → <PLUME_ROOT 父目录>/.claude/   ← base-level (推荐)
  --global                → ~/.claude/                    ← user-level (全机生效, 多 clone 会冲突)
  --base /opt/foo         → /opt/foo/.claude/             ← 自定义 scope
```

**为什么默认是 base-level (不是 user-level)?**

Claude Code 加载规则: `enterprise > personal (user-level) > project (base-level)`。
user-level 永远覆盖同名 project-level skill。如果你装在 user-level, 那么所有用 `--base`
或默认装的其他 clone 都会被 user-level 静默覆盖, 多 scope 隔离失效。

因此**默认装到本仓库父目录的 .claude/**, 多 clone 天然落在不同父目录, 互不干扰。
如果你确定全机只会有一份 plume-skills, 用 `--global` 显式装 user-level 即可。

**核心特性**：
- 默认多 clone 隔离, 各自父目录独立 marker
- 所有 scope 的 symlink 指向同一 git 仓库源 → `git pull` 一次, 各 scope 各自跑 `--update` 即可同步
- 删除某个 scope 不影响其他 scope（不会跨 scope 扫描或修改）
- `--doctor` 命令检测错配 (user-level 覆盖 base-level 等)

## 安装

```bash
git clone https://github.com/<your>/plume-skills.git /path/to/plume-skills
cd /path/to/plume-skills
```

### 默认 (base-level, 推荐多 clone 场景)

```bash
./install.sh                # → <PLUME_ROOT 父目录>/.claude/
```

仅在 cwd 处于 `<PLUME_ROOT 父目录>/` 下时, Claude Code 才加载本仓库 skills。
不同 clone 装到各自父目录, 天然隔离。

### 全机生效 (`--global`, 单 clone 场景)

```bash
./install.sh --global       # → ~/.claude/
```

⚠️ 装 user-level 后, 任何其他 clone 的 base-level 安装的同名 skill 会被本次安装静默覆盖。
仅在你确认只会有一份 plume-skills clone 时使用。命令会弹出 [y/N] 二次确认。

### 自定义 scope (`--base`)

```bash
./install.sh --base /opt/work-project          # → /opt/work-project/.claude/
```

适合项目级独立环境。

### 更新 / 修复 / 卸载 / 诊断

scope-flag 跟首装时一致：

```bash
git pull

# 默认 base-level
./install.sh --update
./install.sh --repair
./install.sh --uninstall

# user-level
./install.sh --update --global
./install.sh --uninstall --global

# 自定义 scope
./install.sh --update --base /opt/work-project

# 诊断所有 scope 状态 + 错配检测 (不改 fs)
./install.sh --doctor

# 预览 / 非交互
./install.sh --update --dry-run
./install.sh --update --yes
```

### 写入 digest 日报定时任务

```bash
./install.sh cron              # 使用 config.yml 中的 cron_time
./install.sh cron 21:00        # 指定时间（同时更新 config）
```

cron 自动从 config 时区转为本机时区，同 scope 重复执行会更新而非追加。

### 打包归档

```bash
./install.sh archive --all                 # 归档全部 data/
./install.sh archive <keyword>             # 按关键词匹配项目数据归档
```

## 安全保护

### Scope 隔离铁律

install.sh 在 `<deploy-root>/.plume-install-state.json` 维护 marker，记录本次部署的 deploy_root / base / plume_root / installed_skills / hooks / updated_at。

- `--update` / `--repair` / `--uninstall` **只操作 marker 记录的 deploy_root**，绝不跨部署点扫描或删除
- 同一 deploy_root 被另一份 plume-skills 仓库占用时, install 拒绝静默覆盖 (exit 1, 要求人工裁决)
- 多部署点需要逐个执行更新（这是有意的隔离）
- 装 base-level 时, 自动 sanity check `~/.claude/skills/` 是否有其他仓库的同名残留 (会覆盖本次安装), 给出明确警告与卸载指引

### 显式删除确认

任何删除操作都会：

1. 先列出完整路径和大小
2. 等用户 `[y/N]` 确认（默认拒绝）
3. 确认后才执行

`--dry-run` 展示列表但不删；`--yes` 跳过交互提示。

### 从 v1 / v2 安全迁移

`--update` 会扫描并逐项确认以下旧版遗留：
- 遗留 skill symlinks（brainstorming, context-keeper, writing-plans, dispatching-parallel-agents 等）
- `~/.claude/projects/*/plume-context/` 数据目录（v1/v2 context-keeper 产出）
- `data/.save-pending-*` / `data/digest-hint/`（v1 残留）
- `config.yml` 中 `auto_generate` / `remind_at` / `max_data_size_mb` / `context:` 段

每项独立扫描、独立展示、独立 [y/N] 确认，可逐项决定保留或清理。

## 目录结构

```
plume-skills/
├── skills/                                    # 4 个
│   ├── using-plume/SKILL.md                   #   机制承载
│   ├── code-review/SKILL.md                   #   结构化审查
│   ├── socratic-dialogue/SKILL.md             #   三人设引导
│   └── digest/                                #   日报 / 研究报告
│
├── hooks/
│   ├── hooks.json                             # 注册 SessionStart + UserPromptSubmit
│   ├── session-start                          # 读 principles.md → 注入
│   ├── user-prompt-submit                     # 注入 PLUME_ROOT 信号
│   └── principles.md                          # Tier 0 原则文本（~900 tokens）
│
├── templates/                                 # digest 相关模板 + git-plan
├── data/                                      # digest 产出（journal / reports）
├── config.yml                                 # locale + digest 段
├── install.sh                                 # 部署器（含 marker + scope guard + 删除确认）
├── README.md                                  # 本文件
├── LICENSE
└── docs/
    ├── slim-design.md                         # 完整瘦身设计文档（v1 → v2 → v3 演进）
    ├── auto-digest-cron.md                    # digest cron 配置说明
    └── andrej-karpathy-skills-main/           # 原 karpathy CLAUDE.md 参考
```

## Skills 详解

### using-plume — 框架机制（按需读取）

不承载行为原则（原则在 SessionStart 注入），只提供：
- PLUME_ROOT 信号缺失时的兜底推导
- 路径约定：项目产出默认路径（specs / plans / reviews / socratic），均需 Ask-Before-Persist 确认
- 网络策略（2 次超时后停止重试）
- 项目 slug 隔离 + `--scope` 聚合语义
- 可选 wrapper 扩展模式（为未来接入外部 skill 保留的模板，默认不激活）

### code-review — 结构化审查（显式触发）

基于 **Clean Code**（Robert C. Martin, 2008）/ **Clean Architecture**（Martin, 2017）/ **The Pragmatic Programmer**（Hunt & Thomas, 20th Anniv. Ed., 2019）构建。

- 26 条原则，按三本书分类（CC-*, CA-*, PP-*）
- 每条审查流程：定义 → 引用章节 → 扫描证据 → file:line 违反 → 修复建议 → P0/P1/P2 分级
- AUDIT 模式（审查自己的代码）+ FEEDBACK 模式（评估他人 review 意见）

触发："代码审查" / "审一下这段代码" / "review this" / "code review" / "检查代码质量"

### socratic-dialogue — 三人设引导对话（**严格显式触发**）

想法模糊但不想被外部方案覆盖时使用。流程：
1. 场景采集（1–2 句）
2. 推 3 个真实人物作为候选（不同视角，如实践派 + 理论派 + 挑战派）
3. 用户选一人
4. 所选人设进行苏格拉底式提问，直到用户讲清想法
5. 可选：写成方案文档（走 Ask-Before-Persist gate）

触发：`/socratic` / "苏格拉底式讨论" / "帮我理清思路" / "我想不清楚这个问题"

**严格显式触发**，不自动激活，避免干扰日常节奏。

### digest — 日报 / 研究报告（沿用现有设计）

从 Claude 原生 jsonl 生成跨项目日报和研究报告。
- `/digest daily` — 今日日报
- `/digest daily 2026-03-15 --scope plume` — 指定日期/作用域
- `/digest report 用户认证相关的工作` — 自然语言语义匹配研究报告

scope 对 `~/.claude/projects/` 下项目目录名做子串匹配，天然隔离公司/个人项目。

## Credits

- **Andrej Karpathy** — Core principles 1–4 are near-verbatim adaptations of his observations on LLM coding pitfalls
- **forrestchang** — [andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) — 将 Karpathy 观察整理成可用的 CLAUDE.md，是 v3 瘦身的直接启发
- **obra/superpowers** — v1/v2 时期的 wrapper 基础（v3 已不依赖）

## License

MIT
