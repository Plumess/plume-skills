# 日报自动生成方案：Cron + Claude CLI

## 背景

Hook 信号注入机制（`[DIGEST-AUTO]`）无法可靠触发 Claude 执行动作 — hook 只能往对话中注入文本，Claude 可能忽略它而优先响应用户消息。这是架构层面的限制，不是 bug。

因此日报自动生成应由**系统层面定时触发**，不依赖 Claude "看到并决定执行"。

## 方案

### 核心思路

用系统 cron 在每天固定时间调用 Claude CLI，以非交互方式执行 `/digest daily` 命令，生成前一天的日报。

### 前置条件

- Claude Code CLI 已安装且可用（`claude` 命令）
- plume-skills 已部署（`--core` 完成）
- `config.yml` 中 `digest.default_scope` 已配置

### Cron 配置

```bash
# 编辑 crontab
crontab -e

# 每天早上 9:00（本地时间）生成前一天的日报
0 9 * * * cd /path/to/project && claude -p "/digest daily $(date -d yesterday +\%Y-\%m-\%d)" --output-format text >> /path/to/plume-skills/data/cron.log 2>&1
```

#### 参数说明

| 参数 | 作用 |
|------|------|
| `cd /path/to/project` | 切到项目目录，Claude 据此确定 project slug |
| `claude -p "..."` | print mode，非交互执行，输出结果后退出 |
| `--output-format text` | 纯文本输出（不含 ANSI 色码） |
| `date -d yesterday` | 生成前一天日期（GNU date 语法） |

#### 共享服务器场景

```bash
# 如果 plume-skills 部署在项目级（--base）
0 9 * * * cd /root/plume && claude -p "/digest daily $(date -d yesterday +\%Y-\%m-\%d)" --output-format text >> /root/plume/plume-skills/data/cron.log 2>&1
```

#### macOS 差异

macOS 的 `date` 不支持 `-d`，使用：

```bash
0 9 * * * cd ~/project && claude -p "/digest daily $(date -v-1d +\%Y-\%m-\%d)" --output-format text >> ~/plume-skills/data/cron.log 2>&1
```

### 时区处理

Cron 使用系统时区。如果系统时区与 `config.yml` 中的 `locale.timezone` 不一致，用 `TZ` 环境变量对齐：

```bash
# 系统时区 PDT，但希望按上海时间 9:00 触发
0 1 * * * TZ=Asia/Shanghai cd /path/to/project && claude -p "/digest daily $(TZ=Asia/Shanghai date -d yesterday +\%Y-\%m-\%d)" --output-format text >> /path/to/plume-skills/data/cron.log 2>&1
```

> 上海 9:00 = PDT 前一天 18:00（夏令时）或 17:00（标准时），但 cron 用 `TZ=Asia/Shanghai` 直接按上海时间调度。

### 幂等性

`/digest daily` 本身已处理幂等：如果当天日报已存在，会进入 Report Update 流程（merge / overwrite / skip）。在 print mode 下默认 merge。

### 日志轮转

```bash
# 可选：定期清理日志
0 0 1 * * find /path/to/plume-skills/data/ -name "cron.log" -size +10M -exec truncate -s 0 {} \;
```

### 验证

```bash
# 手动测试（不等 cron）
cd /path/to/project && claude -p "/digest daily $(date -d yesterday +%Y-%m-%d)" --output-format text

# 检查输出
cat /path/to/plume-skills/data/journal/$(date -d yesterday +%Y-%m-%d).md
```

## 替代方案：Claude Code 内置调度

Claude Code 提供 `/schedule` 命令可创建定时 remote agent。如果你的环境支持：

```bash
# 在 Claude Code 会话中
/schedule create --cron "0 9 * * *" --prompt "/digest daily yesterday"
```

优势是不需要手动配置 crontab，且由 Claude 基础设施管理。劣势是需要网络连接且可能产生 API 费用。

## 与现有设计的关系

此方案替代了原有的 hook 信号机制（`[DIGEST-HINT]` / `[DIGEST-AUTO]`）。相关代码已在 v2 简化中移除：
- ~~UserPromptSubmit hook 中的 digest auto-sense 逻辑~~
- ~~config.yml 中的 `auto_generate`、`remind_at` 字段~~
- ~~`data/digest-hint/` marker 目录~~
