#!/usr/bin/env bash
# plume-skills 部署器
# 用法: ./install.sh --core [--base path] | --project [path] | archive <slug|--all>
set -euo pipefail

# ─── 颜色 ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[plume]${NC} $*"; }
ok()    { echo -e "${GREEN}[plume]${NC} $*"; }
warn()  { echo -e "${YELLOW}[plume]${NC} $*"; }
err()   { echo -e "${RED}[plume]${NC} $*" >&2; }

PLUME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
BASE_DIR=""

# ─── Skill 分类 ──────────────────────────────────────────────
# skills/ 中的原创/wrapper skills（核心安装）
CORE_PLUME_SKILLS=(using-plume context-keeper digest)

# 通用 brainstorming（显式激活版，目录名与部署名不同）
CORE_BRAINSTORMING_SRC="skills/brainstorming-universal"
CORE_BRAINSTORMING_NAME="brainstorming"

# vendor/ 中的社区 skills（核心安装）
CORE_VENDOR_SKILLS=(
  "vendor/find-skills:find-skills"
  "vendor/skill-creator:skill-creator"
)

# skills/ 中的 wrapper skills（项目安装）
# brainstorming 项目版（强制前置）会遮盖通用版
PROJECT_SKILLS=(
  brainstorming writing-plans executing-plans
  subagent-driven-development dispatching-parallel-agents
  test-driven-development systematic-debugging
  requesting-code-review receiving-code-review
  verification-before-completion finishing-a-development-branch
  using-git-worktrees
)

# ─── 辅助函数 ─────────────────────────────────────────────────

# 计算 Claude 配置目录：--base 指定时用 <base>/.claude，否则用 ~/.claude
claude_dir() {
  echo "${BASE_DIR:-$HOME}/.claude"
}

symlink_skill() {
  local src="$1" dest="$2" name="$3"
  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    warn "  $name — 源不存在 ($src)，跳过"
    return 0
  fi
  if [ -L "$dest" ]; then
    local existing target
    existing="$(readlink -f "$dest" 2>/dev/null || true)"
    target="$(readlink -f "$src" 2>/dev/null || true)"
    if [ "$existing" = "$target" ]; then
      info "  $name — 已链接，跳过"
      return 0
    else
      warn "  $name — 已存在（指向 $existing），不覆盖"
      return 0
    fi
  elif [ -e "$dest" ]; then
    warn "  $name — 已存在（非 symlink），不覆盖"
    return 0
  fi
  if $DRY_RUN; then
    info "  $name — 将链接 → $dest"
  else
    ln -sf "$src" "$dest"
    ok "  $name — 已链接"
  fi
}

# 权限管理快照路径
permissions_manifest() {
  echo "$PLUME_ROOT/data/.installed-permissions.json"
}

# 三方 diff 权限同步：只动 plume 自己的条目，不碰用户的
# 输入：target（settings.local.json），template（当前模板），manifest（上次安装快照）
# 逻辑：
#   stale  = manifest - template  （plume 旧版加的，新版已移除 → 删除）
#   added  = template - target    （新版需要的，target 中还没有 → 添加）
#   result = (target - stale) + added
sync_permissions() {
  local target="$1" template="$2"
  local manifest
  manifest="$(permissions_manifest)"

  if ! command -v jq &>/dev/null; then
    warn "未找到 jq — 无法同步权限。请安装 jq 后重新执行。"
    warn "需要手动合并的模板: $template"
    return 0
  fi

  # 首次安装：target 不存在
  if [ ! -f "$target" ]; then
    if $DRY_RUN; then
      info "  将从模板创建 $target"
    else
      cp "$template" "$target"
      mkdir -p "$(dirname "$manifest")"
      cp "$template" "$manifest"
      ok "  已创建 $target"
    fi
    return 0
  fi

  # 如果快照不存在（从旧版本升级），将当前模板视为旧快照
  # 效果：首次 update 时不会误删任何条目，只补入新增
  local manifest_file="$manifest"
  if [ ! -f "$manifest_file" ]; then
    manifest_file="$template"
  fi

  # 三方 diff
  local diff_info
  diff_info="$(jq -s '
    (.[0].permissions.allow // []) as $current |
    (.[1].permissions.allow // []) as $new_template |
    (.[2].permissions.allow // []) as $old_template |
    ($old_template - $new_template) as $stale |
    ($new_template - $current) as $to_add |
    ($current - $stale) as $cleaned |
    {
      stale: ($stale | length),
      add: ($to_add | length),
      result: (($cleaned + $to_add) | unique)
    }
  ' "$target" "$template" "$manifest_file" 2>/dev/null || echo '{"stale":0,"add":0,"result":[]}')"

  local stale_count add_count
  stale_count="$(echo "$diff_info" | jq '.stale')"
  add_count="$(echo "$diff_info" | jq '.add')"

  if [ "$stale_count" = "0" ] && [ "$add_count" = "0" ]; then
    info "  权限已是最新"
    # 确保快照存在
    if [ ! -f "$manifest" ] && ! $DRY_RUN; then
      mkdir -p "$(dirname "$manifest")"
      cp "$template" "$manifest"
    fi
    return 0
  fi

  if $DRY_RUN; then
    [ "$stale_count" != "0" ] && info "  将移除 $stale_count 条旧版 plume 权限"
    [ "$add_count" != "0" ] && info "  将新增 $add_count 条权限"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  echo "$diff_info" | jq '{ permissions: { allow: .result } }' > "$tmp"
  # 合并回 target（保留 hooks 等其他字段）
  jq -s '.[0] * .[1]' "$target" "$tmp" > "${tmp}.merged" && mv "${tmp}.merged" "$target"
  rm -f "$tmp"

  # 更新快照
  mkdir -p "$(dirname "$manifest")"
  cp "$template" "$manifest"

  local msg=""
  [ "$stale_count" != "0" ] && msg="移除 $stale_count 条旧版"
  [ "$add_count" != "0" ] && msg="${msg:+$msg，}新增 $add_count 条"
  ok "  权限已同步（$msg）"
}


# 迁移：清理旧版本遗留（PreCompact hook、stale marker、废弃 config 字段）
# 仅清理 plume-skills 自身产生的数据，不碰用户内容
migrate_from_old_version() {
  local claude_dir="$1"
  local settings_file="$claude_dir/settings.local.json"
  local migrated=0

  # 清理 stale marker 文件（旧版 PreCompact 遗留）
  local markers
  markers="$(ls "$PLUME_ROOT/data"/.save-pending-* 2>/dev/null || true)"
  if [ -n "$markers" ]; then
    if $DRY_RUN; then
      info "  将清理旧版 save-pending marker 文件"
    else
      rm -f "$PLUME_ROOT/data"/.save-pending-*
      ok "  已清理旧版 save-pending marker 文件"
    fi
    migrated=$((migrated + 1))
  fi

  # 清理 digest-hint 目录（旧版 auto-sense 遗留）
  if [ -d "$PLUME_ROOT/data/digest-hint" ]; then
    if $DRY_RUN; then
      info "  将清理旧版 digest-hint 目录"
    else
      rm -rf "$PLUME_ROOT/data/digest-hint"
      ok "  已清理旧版 digest-hint 目录"
    fi
    migrated=$((migrated + 1))
  fi

  # 清理 config.yml 中的废弃字段（auto_generate、remind_at）
  if grep -qE '^\s*(auto_generate|remind_at)' "$PLUME_ROOT/config.yml" 2>/dev/null; then
    if $DRY_RUN; then
      info "  将清理 config.yml 中的废弃字段（auto_generate、remind_at）"
    else
      sed -i '/^\s*auto_generate:/d; /^\s*remind_at:/d; /^\s*- "[0-9]\{2\}:[0-9]\{2\}"/d' "$PLUME_ROOT/config.yml"
      # 清理可能残留的空注释行
      sed -i '/^\s*# 自动生成/d; /^\s*# false 时仅提示/d; /^\s*# 最早提醒时间/d; /^\s*# 条件：/d; /^\s*# 每天每个时间点/d' "$PLUME_ROOT/config.yml"
      ok "  已清理 config.yml 中的废弃字段"
    fi
    migrated=$((migrated + 1))
  fi

  if [ "$migrated" -eq 0 ]; then
    info "  无旧版本遗留需要清理"
  fi
}

write_plume_root() {
  if $DRY_RUN; then
    info "  将写入 plume_root=$PLUME_ROOT 到 config.yml"
    return 0
  fi
  sed -i "s|^plume_root:.*|plume_root: \"$PLUME_ROOT\"|" "$PLUME_ROOT/config.yml"
  ok "  plume_root 已设为 $PLUME_ROOT"
}

# ─── 命令 ─────────────────────────────────────────────────────
cmd_core() {
  local claude_dir
  claude_dir="$(claude_dir)"

  # 检测已有安装 → 自动进入 update 模式
  if [ -d "$claude_dir/skills/using-plume" ] || [ -L "$claude_dir/skills/using-plume" ]; then
    info "检测到已有安装（$claude_dir/skills/），自动进入更新模式..."
    echo ""
    cmd_update
    return 0
  fi

  info "安装核心 skills 到 $claude_dir/skills/"
  echo ""

  info "将安装以下 skills:"
  info "  - using-plume — 会话引导（hook 注入）"
  info "  - context-keeper — 会话历史摘要与索引"
  info "  - digest — 日报与研究报告"
  info "  - brainstorming — 结构化设计探索（显式激活）"
  info "  - find-skills — skill 发现"
  info "  - skill-creator — skill 创建"
  echo ""

  if ! $DRY_RUN; then
    read -rp "继续？[Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      info "已取消。"
      exit 0
    fi
  fi

  mkdir -p "$claude_dir/skills"

  # 链接原创/wrapper skills（来自 skills/）
  info "正在链接 plume skills..."
  for skill in "${CORE_PLUME_SKILLS[@]}"; do
    symlink_skill "$PLUME_ROOT/skills/$skill" "$claude_dir/skills/$skill" "$skill"
  done
  # brainstorming 通用版（目录名 ≠ 部署名）
  symlink_skill "$PLUME_ROOT/$CORE_BRAINSTORMING_SRC" "$claude_dir/skills/$CORE_BRAINSTORMING_NAME" "$CORE_BRAINSTORMING_NAME"

  # 链接 vendor skills（来自 vendor/ 子目录）
  info "正在链接 vendor skills..."
  for entry in "${CORE_VENDOR_SKILLS[@]}"; do
    local rel_path="${entry%%:*}"
    local name="${entry##*:}"
    local src="$PLUME_ROOT/$rel_path"
    if [ -d "$src" ] && [ -f "$src/SKILL.md" ]; then
      symlink_skill "$src" "$claude_dir/skills/$name" "$name"
    else
      warn "  $name — 未找到 $rel_path/SKILL.md"
    fi
  done
  echo ""

  # 合并 hooks 到 settings.local.json（替换 __PLUME_ROOT__ 为实际路径）
  info "合并 hooks 配置..."
  local settings_file="$claude_dir/settings.local.json"
  local hooks_resolved
  hooks_resolved="$(sed "s|__PLUME_ROOT__|$PLUME_ROOT|g" "$PLUME_ROOT/hooks/hooks.json")"
  if [ ! -f "$settings_file" ]; then
    if $DRY_RUN; then
      info "  将创建 $settings_file（含 hooks）"
    else
      echo "$hooks_resolved" > "$settings_file"
      ok "  已创建 $settings_file（含 hooks）"
    fi
  else
    if grep -q "hooks/session-start" "$settings_file" 2>/dev/null; then
      info "  $settings_file 中已有 hooks，跳过"
    else
      if $DRY_RUN; then
        info "  将合并 hooks 到 $settings_file"
      else
        if command -v jq &>/dev/null; then
          local tmp
          tmp="$(mktemp)"
          jq -s '.[0] * .[1]' "$settings_file" <(echo "$hooks_resolved") > "$tmp" && mv "$tmp" "$settings_file"
          ok "  已合并 hooks 到 $settings_file"
        else
          warn "  未找到 jq — 请手动将 hooks/hooks.json 合并到 $settings_file"
        fi
      fi
    fi
  fi

  # 合并权限模板
  info "合并权限配置..."
  sync_permissions "$settings_file" "$PLUME_ROOT/templates/settings.local.append.json"
  echo ""

  # 写入 plume_root
  info "写入配置..."
  write_plume_root
  echo ""

  ok "核心安装完成。"

  # 交互式配置（dry-run 时跳过）
  if ! $DRY_RUN; then
    echo ""
    info "配置 digest"
    echo ""

    # default_scope — 说明原理并建议
    local current_scope suggested_scope
    current_scope="$(grep -oP '^\s*default_scope:\s*"\K[^"]*' "$PLUME_ROOT/config.yml" 2>/dev/null || true)"
    if [ -n "$BASE_DIR" ]; then
      suggested_scope="$(basename "$BASE_DIR")"
    else
      suggested_scope="$(basename "$HOME")"
    fi
    local default_scope="${current_scope:-$suggested_scope}"

    info "  日报作用域 (default_scope)"
    info "  scope 用于过滤 ~/.claude/projects/ 中的项目目录名（子串匹配）。"
    info "  例如 scope=\"plume\" 会匹配 -root-plume、-root-plume-project-a 等。"
    info "  不同 scope 的日报互不干扰，可用于隔离公司/个人项目。"
    info "  如需自定义请直接输入，否则回车使用默认值。"
    echo ""
    read -rp "  default_scope [$default_scope]: " input_scope
    local final_scope="${input_scope:-$default_scope}"
    if [ -n "$final_scope" ] && [ "$final_scope" != "$current_scope" ]; then
      sed -i "s|^\(\s*default_scope:\).*|\1 \"$final_scope\"|" "$PLUME_ROOT/config.yml"
      ok "  default_scope = \"$final_scope\""
    fi

    # cron_time
    local current_cron current_tz
    current_cron="$(grep -oP '^\s*cron_time:\s*"\K[^"]*' "$PLUME_ROOT/config.yml" 2>/dev/null || echo "09:00")"
    current_tz="$(grep -oP '^\s*timezone:\s*"\K[^"]*' "$PLUME_ROOT/config.yml" 2>/dev/null || echo "Asia/Shanghai")"
    echo ""
    read -rp "  日报生成时间 (cron_time, 时区: $current_tz) [$current_cron]: " input_cron
    local final_cron="${input_cron:-$current_cron}"
    if [ "$final_cron" != "$current_cron" ]; then
      sed -i "s|^\(\s*cron_time:\).*|\1 \"$final_cron\"|" "$PLUME_ROOT/config.yml"
      ok "  cron_time = \"$final_cron\""
    fi

    echo ""
    info "运行 ./install.sh cron 可自动配置定时日报生成。"
  fi
}

cmd_project() {
  local target="${1:-$(dirname "$PLUME_ROOT")}"
  if [ -n "$target" ]; then
    target="$(cd "$target" 2>/dev/null && pwd || echo "$target")"
    if [ ! -d "$target" ]; then
      err "目标目录不存在: $target"
      exit 1
    fi
  fi

  # 检测核心 skills 是否对目标项目可见（通过 ~/.claude/）
  # Claude Code 只解析 <cwd>/.claude/ 和 ~/.claude/，中间层不可见
  local need_core=false
  if [ ! -L "$HOME/.claude/skills/context-keeper" ] && [ ! -d "$HOME/.claude/skills/context-keeper" ]; then
    need_core=true
  fi

  info "安装项目 skills 到 $target/.claude/skills/"
  echo ""

  info "将安装 ${#PROJECT_SKILLS[@]} 个工作流 skills:"
  for skill in "${PROJECT_SKILLS[@]}"; do
    info "  - $skill"
  done
  if $need_core; then
    echo ""
    info "检测到核心 skills 不在用户级 (~/.claude/)，将一并安装:"
    info "  - using-plume"
    info "  - context-keeper"
    info "  - digest"
    info "  - find-skills"
    info "  - skill-creator"
    info "  + hooks (SessionStart, UserPromptSubmit)"
  fi
  echo ""

  if ! $DRY_RUN; then
    read -rp "继续？[Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      info "已取消。"
      exit 0
    fi
  fi

  mkdir -p "$target/.claude/skills"

  # 链接项目 skills（全部来自 skills/，各自 wrapper 引用 vendor 原文）
  info "正在链接项目 skills..."
  for skill in "${PROJECT_SKILLS[@]}"; do
    symlink_skill "$PLUME_ROOT/skills/$skill" "$target/.claude/skills/$skill" "$skill"
  done

  # 核心 skills + hooks 补装（场景 B：核心装在中间层，子项目不可见）
  if $need_core; then
    echo ""
    info "正在链接核心 skills..."
    for skill in "${CORE_PLUME_SKILLS[@]}"; do
      symlink_skill "$PLUME_ROOT/skills/$skill" "$target/.claude/skills/$skill" "$skill"
    done
    # vendor skills
    for entry in "${CORE_VENDOR_SKILLS[@]}"; do
      local rel_path="${entry%%:*}"
      local name="${entry##*:}"
      local src="$PLUME_ROOT/$rel_path"
      if [ -d "$src" ] && [ -f "$src/SKILL.md" ]; then
        symlink_skill "$src" "$target/.claude/skills/$name" "$name"
      fi
    done
  fi
  echo ""

  # 权限同步
  info "合并权限配置..."
  sync_permissions "$target/.claude/settings.local.json" "$PLUME_ROOT/templates/settings.local.append.json"

  # hooks 补装（核心不在用户级时，项目需要自带 hooks 才能激活框架）
  if $need_core; then
    local settings_file="$target/.claude/settings.local.json"
    info "合并 hooks 配置..."
    local hooks_resolved
    hooks_resolved="$(sed "s|__PLUME_ROOT__|$PLUME_ROOT|g" "$PLUME_ROOT/hooks/hooks.json")"
    if grep -q "hooks/session-start" "$settings_file" 2>/dev/null; then
      info "  hooks 已存在，跳过"
    else
      if $DRY_RUN; then
        info "  将合并 hooks 到 $settings_file"
      else
        if command -v jq &>/dev/null; then
          local tmp
          tmp="$(mktemp)"
          jq -s '.[0] * .[1]' "$settings_file" <(echo "$hooks_resolved") > "$tmp" && mv "$tmp" "$settings_file"
          ok "  hooks 已合并"
        else
          warn "  未找到 jq — 请手动将 hooks 合并到 $settings_file"
        fi
      fi
    fi
  fi
  echo ""

  ok "项目安装完成: $target"
}

cmd_archive() {
  local pattern="$1"
  local archive_dir="$PLUME_ROOT/data/archives"
  local date_stamp
  date_stamp="$(date +%Y-%m-%d)"

  mkdir -p "$archive_dir"

  if [ "$pattern" = "--all" ]; then
    local archive_name="plume-full-$date_stamp.tar.gz"
    info "正在归档全部项目数据..."
    if $DRY_RUN; then
      info "  将创建 $archive_dir/$archive_name"
    else
      tar czf "$archive_dir/$archive_name" \
        -C "$PLUME_ROOT/data" \
        --exclude='archives' \
        . 2>/dev/null || { err "没有数据可归档"; exit 1; }
      ok "已归档到 $archive_dir/$archive_name"
    fi
  else
    local matches=()
    for dir in "$PLUME_ROOT/data/"*"$pattern"*/; do
      [ -d "$dir" ] && [[ "$(basename "$dir")" != "archives" ]] && matches+=("$dir")
    done

    if [ ${#matches[@]} -eq 0 ]; then
      err "未找到匹配 '$pattern' 的项目数据: $PLUME_ROOT/data/"
      exit 1
    fi

    info "找到 ${#matches[@]} 个匹配项目:"
    for dir in "${matches[@]}"; do
      info "  - $(basename "$dir")"
    done

    local archive_name="$pattern-$date_stamp.tar.gz"
    if $DRY_RUN; then
      info "  将创建 $archive_dir/$archive_name"
    else
      local rel_dirs=()
      for dir in "${matches[@]}"; do
        rel_dirs+=("$(basename "$dir")")
      done
      tar czf "$archive_dir/$archive_name" \
        -C "$PLUME_ROOT/data" \
        "${rel_dirs[@]}"
      ok "已归档到 $archive_dir/$archive_name"
    fi
  fi
}

cmd_update() {
  local claude_dir
  claude_dir="$(claude_dir)"
  info "更新 plume-skills（同步 skills、hooks、权限）..."
  info "  目标: $claude_dir"
  echo ""

  if ! command -v jq &>/dev/null; then
    err "需要 jq 来执行更新。请安装: sudo dnf install jq"
    exit 1
  fi

  local settings_file="$claude_dir/settings.local.json"
  local changes=0

  # 1. 补齐 skills symlinks（新增的 skill 自动链接，已有的不动）
  info "同步 skills symlinks..."
  mkdir -p "$claude_dir/skills"
  for skill in "${CORE_PLUME_SKILLS[@]}"; do
    local dest="$claude_dir/skills/$skill"
    local src="$PLUME_ROOT/skills/$skill"
    if [ ! -L "$dest" ] && [ ! -e "$dest" ]; then
      if $DRY_RUN; then
        info "  $skill — 将新增链接"
      else
        ln -sf "$src" "$dest"
        ok "  $skill — 新增链接"
      fi
      changes=$((changes + 1))
    elif [ -L "$dest" ]; then
      local existing
      existing="$(readlink -f "$dest" 2>/dev/null || true)"
      local target_real
      target_real="$(readlink -f "$src" 2>/dev/null || true)"
      if [ "$existing" != "$target_real" ]; then
        if $DRY_RUN; then
          info "  $skill — 将更新链接（旧→ $existing）"
        else
          rm "$dest"
          ln -sf "$src" "$dest"
          ok "  $skill — 已更新链接"
        fi
        changes=$((changes + 1))
      fi
    fi
  done
  # brainstorming 通用版（与 CORE_PLUME_SKILLS 相同的断链检测逻辑）
  local bs_dest="$claude_dir/skills/$CORE_BRAINSTORMING_NAME"
  local bs_src="$PLUME_ROOT/$CORE_BRAINSTORMING_SRC"
  if [ ! -L "$bs_dest" ] && [ ! -e "$bs_dest" ]; then
    if $DRY_RUN; then
      info "  $CORE_BRAINSTORMING_NAME — 将新增链接"
    else
      ln -sf "$bs_src" "$bs_dest"
      ok "  $CORE_BRAINSTORMING_NAME — 新增链接"
    fi
    changes=$((changes + 1))
  elif [ -L "$bs_dest" ]; then
    local existing target_real
    existing="$(readlink -f "$bs_dest" 2>/dev/null || true)"
    target_real="$(readlink -f "$bs_src" 2>/dev/null || true)"
    if [ "$existing" != "$target_real" ]; then
      if $DRY_RUN; then
        info "  $CORE_BRAINSTORMING_NAME — 将更新链接（旧→ $existing）"
      else
        rm "$bs_dest"; ln -sf "$bs_src" "$bs_dest"
        ok "  $CORE_BRAINSTORMING_NAME — 已更新链接"
      fi
      changes=$((changes + 1))
    fi
  fi
  # vendor skills（与 CORE_PLUME_SKILLS 相同的断链检测逻辑）
  for entry in "${CORE_VENDOR_SKILLS[@]}"; do
    local rel_path="${entry%%:*}"
    local name="${entry##*:}"
    local src="$PLUME_ROOT/$rel_path"
    local dest="$claude_dir/skills/$name"
    if [ -d "$src" ] && [ -f "$src/SKILL.md" ]; then
      if [ ! -L "$dest" ] && [ ! -e "$dest" ]; then
        if $DRY_RUN; then
          info "  $name — 将新增链接"
        else
          ln -sf "$src" "$dest"
          ok "  $name — 新增链接"
        fi
        changes=$((changes + 1))
      elif [ -L "$dest" ]; then
        local existing target_real
        existing="$(readlink -f "$dest" 2>/dev/null || true)"
        target_real="$(readlink -f "$src" 2>/dev/null || true)"
        if [ "$existing" != "$target_real" ]; then
          if $DRY_RUN; then
            info "  $name — 将更新链接（旧→ $existing）"
          else
            rm "$dest"; ln -sf "$src" "$dest"
            ok "  $name — 已更新链接"
          fi
          changes=$((changes + 1))
        fi
      fi
    fi
  done
  if [ "$changes" -eq 0 ]; then
    info "  所有 skills 已是最新"
  fi

  # 2. 同步 hooks（以 hooks.json 模板为准，完整替换 hooks 部分）
  info "同步 hooks..."
  if [ -f "$settings_file" ]; then
    local hooks_resolved
    hooks_resolved="$(sed "s|__PLUME_ROOT__|$PLUME_ROOT|g" "$PLUME_ROOT/hooks/hooks.json")"
    local hooks_diff
    hooks_diff="$(jq -s '
      (.[0].hooks // {}) as $current |
      (.[1].hooks // {}) as $template |
      if $current == $template then "match" else "differ" end
    ' "$settings_file" <(echo "$hooks_resolved") 2>/dev/null || echo "differ")"
    if [ "$hooks_diff" = '"match"' ]; then
      info "  hooks 已与模板一致"
    else
      if $DRY_RUN; then
        info "  将更新 hooks 配置"
      else
        local tmp
        tmp="$(mktemp)"
        jq -s '.[0] * { hooks: .[1].hooks }' "$settings_file" <(echo "$hooks_resolved") > "$tmp" && mv "$tmp" "$settings_file"
        ok "  hooks 已同步"
      fi
    fi
  else
    warn "  $settings_file 不存在，请先执行 --core 安装"
  fi

  # 3. 同步权限（三方 diff：只动 plume 条目，保留用户自定义）
  info "同步权限..."
  sync_permissions "$settings_file" "$PLUME_ROOT/templates/settings.local.append.json"

  # 4. 迁移：清理旧版本遗留
  info "迁移检查..."
  migrate_from_old_version "$claude_dir"

  # 5. 更新 plume_root
  info "更新配置..."
  write_plume_root
  echo ""

  ok "更新完成。Skills 内容通过 symlink 自动生效，无需额外操作。"
}

cmd_repair() {
  local claude_dir
  claude_dir="$(claude_dir)"
  info "修复 plume-skills 路径引用..."
  info "  目标: $claude_dir"
  echo ""

  # 1. 更新 config.yml 中的 plume_root
  info "更新 config.yml..."
  write_plume_root

  # 2. 重建所有 skills symlinks（删除旧的并重建，包括新增的 skill）
  mkdir -p "$claude_dir/skills"
  info "重建核心 skills symlinks..."
  for skill in "${CORE_PLUME_SKILLS[@]}"; do
    local dest="$claude_dir/skills/$skill"
    rm -f "$dest"
    ln -sf "$PLUME_ROOT/skills/$skill" "$dest"
    ok "  $skill — 已重建"
  done
  # brainstorming 通用版
  local bs_dest="$claude_dir/skills/$CORE_BRAINSTORMING_NAME"
  rm -f "$bs_dest"
  ln -sf "$PLUME_ROOT/$CORE_BRAINSTORMING_SRC" "$bs_dest"
  ok "  $CORE_BRAINSTORMING_NAME — 已重建"
  # vendor skills
  for entry in "${CORE_VENDOR_SKILLS[@]}"; do
    local rel_path="${entry%%:*}"
    local name="${entry##*:}"
    local dest="$claude_dir/skills/$name"
    if [ -d "$PLUME_ROOT/$rel_path" ]; then
      rm -f "$dest"
      ln -sf "$PLUME_ROOT/$rel_path" "$dest"
      ok "  $name — 已重建"
    fi
  done

  # 3. 同步 hooks（完整替换，确保旧版 PreCompact 等被移除）
  local settings_file="$claude_dir/settings.local.json"
  if [ -f "$settings_file" ]; then
    info "同步 hooks..."
    if command -v jq &>/dev/null; then
      local hooks_resolved
      hooks_resolved="$(sed "s|__PLUME_ROOT__|$PLUME_ROOT|g" "$PLUME_ROOT/hooks/hooks.json")"
      local tmp
      tmp="$(mktemp)"
      jq -s '.[0] * { hooks: .[1].hooks }' "$settings_file" <(echo "$hooks_resolved") > "$tmp" && mv "$tmp" "$settings_file"
      ok "  hooks 已同步（旧版 hooks 如 PreCompact 已移除）"
    else
      warn "  未找到 jq — 请手动更新 $settings_file 中的 hooks"
    fi
  fi

  # 4. 同步权限
  info "同步权限..."
  sync_permissions "$settings_file" "$PLUME_ROOT/templates/settings.local.append.json"

  # 5. 迁移旧版本遗留
  info "迁移检查..."
  migrate_from_old_version "$claude_dir"

  # 6. 扫描项目级 symlinks（提示用户）
  local broken_found=false
  for dir in "$HOME"/*/.claude/skills /tmp/*/.claude/skills; do
    [ -d "$dir" ] || continue
    for link in "$dir"/*/; do
      if [ -L "${link%/}" ] && [ ! -e "${link%/}" ]; then
        if ! $broken_found; then
          warn "发现断开的项目级 symlinks（需要对相关项目重新执行 --project）："
          broken_found=true
        fi
        warn "  ${link%/}"
      fi
    done
  done

  echo ""
  ok "修复完成。如有项目级 symlinks 需要修复，请对相关项目重新执行 --project。"
}

cmd_cron() {
  local config="$PLUME_ROOT/config.yml"

  # 检查依赖
  if ! command -v python3 &>/dev/null; then
    err "需要 python3 来计算时区转换"
    exit 1
  fi
  if ! command -v crontab &>/dev/null; then
    err "未找到 crontab 命令。请先安装 cron 服务："
    err "  Debian/Ubuntu: sudo apt-get install cron"
    err "  RHEL/CentOS:   sudo dnf install cronie"
    err "  macOS:         系统自带"
    exit 1
  fi

  # scope 从 config 读取
  local scope
  scope="$(grep -oP '^\s*default_scope:\s*"\K[^"]*' "$config" 2>/dev/null || true)"
  if [ -z "$scope" ]; then
    err "config.yml 中 digest.default_scope 为空。"
    err "请先设置: 编辑 $PLUME_ROOT/config.yml → digest.default_scope"
    err "或重新运行 ./install.sh --core 进行交互式配置"
    exit 1
  fi
  local cron_marker="# plume-skills-digest:$scope"

  # 读取 config 中的 cron_time（或使用命令行参数覆盖）
  local config_cron cli_time
  config_cron="$(grep -oP '^\s*cron_time:\s*"\K[^"]*' "$config" 2>/dev/null || echo "09:00")"
  cli_time="${CRON_TIME:-}"
  local use_time="${cli_time:-$config_cron}"
  local target_hour="$((10#${use_time%%:*}))"
  local target_min="$((10#${use_time##*:}))"

  # 如果命令行指定了时间且与 config 不同，更新 config
  if [ -n "$cli_time" ] && [ "$cli_time" != "$config_cron" ]; then
    sed -i "s|^\(\s*cron_time:\).*|\1 \"$cli_time\"|" "$config"
    ok "config.yml cron_time 已更新为 \"$cli_time\""
  fi

  # 时区转换
  local cron_result
  cron_result="$(python3 -c "
import datetime, sys
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo

target_tz_name = 'Asia/Shanghai'
try:
    import yaml
    c = yaml.safe_load(open('$config'))
    target_tz_name = c.get('locale', {}).get('timezone', 'Asia/Shanghai')
except Exception:
    pass

target_tz = ZoneInfo(target_tz_name)
local_tz = datetime.datetime.now().astimezone().tzinfo

dt = datetime.datetime.combine(datetime.date.today(), datetime.time($target_hour, $target_min), tzinfo=target_tz)
local_dt = dt.astimezone(local_tz)

day_diff = (local_dt.date() - dt.date()).days
if day_diff != 0:
    note = f'跨天：{target_tz_name} {$target_hour:02d}:{$target_min:02d} = 本机前一天 {local_dt.strftime(\"%H:%M\")}'
else:
    note = f'{target_tz_name} {$target_hour:02d}:{$target_min:02d} = 本机 {local_dt.strftime(\"%H:%M\")}'

print(f'{local_dt.minute} {local_dt.hour}|{target_tz_name}|{note}')
" 2>&1)"
  if [ -z "$cron_result" ] || echo "$cron_result" | grep -q "Traceback\|Error"; then
    err "时区转换失败: $cron_result"
    exit 1
  fi

  local cron_time tz_name tz_note
  IFS='|' read -r cron_time tz_name tz_note <<< "$cron_result"

  local project_dir
  if [ -n "$BASE_DIR" ]; then
    project_dir="$BASE_DIR"
  else
    project_dir="$(dirname "$PLUME_ROOT")"
  fi

  # 构造 cron 行（日期用 config 时区计算，不用本机时区）
  local date_cmd
  if [[ "$(uname)" == "Darwin" ]]; then
    date_cmd="\$(TZ=$tz_name date -v-1d +\\%Y-\\%m-\\%d)"
  else
    date_cmd="\$(TZ=$tz_name date -d yesterday +\\%Y-\\%m-\\%d)"
  fi
  # 查找 claude CLI 绝对路径（cron 环境不加载 .bashrc，PATH 不完整）
  local claude_bin
  claude_bin="$(command -v claude 2>/dev/null || true)"
  if [ -z "$claude_bin" ]; then
    err "未找到 claude CLI。请先安装: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
  fi

  local cron_line="$cron_time * * * cd $project_dir && $claude_bin -p \"/digest daily $date_cmd --scope $scope\" --allowedTools \"Write Read Glob Grep Bash(head:*) Bash(stat:*) Bash(ls:*) Bash(mkdir:*) Bash(find:*)\" --output-format text >> $PLUME_ROOT/data/cron.log 2>&1 $cron_marker"

  echo ""
  info "日报 cron — scope: $scope（$tz_note）"

  if $DRY_RUN; then
    info "将写入 crontab:"
    echo "  $cron_line"
    return 0
  fi

  # 读取现有 crontab，移除当前 scope 的旧条目，追加新条目
  local existing
  existing="$(crontab -l 2>/dev/null || true)"
  local filtered
  filtered="$(echo "$existing" | grep -v "$cron_marker" || true)"

  echo "${filtered:+$filtered
}$cron_line" | crontab -

  ok "crontab 已更新:"
  echo "  $cron_line"

  # 确保 cron 服务运行
  if command -v systemctl &>/dev/null; then
    if ! systemctl is-active --quiet cron 2>/dev/null && ! systemctl is-active --quiet crond 2>/dev/null; then
      warn "cron 服务未运行。启动: sudo systemctl start cron"
    fi
  fi
}

# ─── 主入口 ───────────────────────────────────────────────────
usage() {
  cat <<'EOF'
plume-skills 部署器

用法:
  ./install.sh --core [--base path] [--dry-run]  部署核心 skills + hooks
  ./install.sh --project [path] [--dry-run]      部署项目工作流 skills
  ./install.sh --update [--base path] [--dry-run] 同步 skills/hooks/权限
  ./install.sh --repair [--base path]             修复搬迁后的路径引用
  ./install.sh cron [HH:MM]                       写入日报 cron 到 crontab（自动时区转换）
  ./install.sh archive <keyword|--all>            归档项目数据用于迁移
  ./install.sh --help                             显示帮助

选项:
  --base <path>  将核心 skills 部署到 <path>/.claude/ 而非 ~/.claude/
                 适用于共享服务器等无法使用用户级配置的场景

示例:
  # 个人机器
  ./install.sh --core                        # → ~/.claude/
  ./install.sh --project ~/project-a        # → ~/project-a/.claude/

  # 共享服务器（项目级隔离）
  ./install.sh --core --base /root/plume     # → /root/plume/.claude/
  ./install.sh --project /root/plume         # → /root/plume/.claude/

  # 写入日报 cron（scope 从 config 读取，同 scope 更新而非追加）
  ./install.sh cron                          # 使用 config 的 cron_time
  ./install.sh cron 21:00                    # 指定时间（同时更新 config）

vendor/ 中的内容已随项目一起分发，无需额外拉取。
EOF
}

CMD=""
PROJECT_PATH=""
ARCHIVE_PATTERN=""
CRON_TIME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core)       CMD="core"; shift ;;
    --universal)  CMD="core"; shift ;;  # 向后兼容
    --project)    CMD="project"; shift
                  if [ "${1:-}" ] && [[ ! "$1" =~ ^-- ]]; then
                    PROJECT_PATH="$1"; shift
                  fi ;;
    --update)     CMD="update"; shift ;;
    --repair)     CMD="repair"; shift ;;
    cron)         CMD="cron"; shift
                  if [ "${1:-}" ] && [[ "$1" =~ ^[0-9] ]]; then
                    CRON_TIME="$1"; shift
                  fi ;;
    archive)      CMD="archive"; shift; ARCHIVE_PATTERN="${1:---all}"; shift 2>/dev/null || true ;;
    --base)       shift; BASE_DIR="${1:?--base 需要指定路径}"; shift ;;
    --clean-permissions) shift ;;  # 已废弃，三方 diff 自动处理
    --dry-run)    DRY_RUN=true; shift ;;
    --help|-h)    usage; exit 0 ;;
    *)            err "未知选项: $1"; usage; exit 1 ;;
  esac
done

if [ -z "$CMD" ]; then
  usage
  exit 1
fi

case "$CMD" in
  core)    cmd_core ;;
  project) cmd_project "$PROJECT_PATH" ;;
  update)  cmd_update ;;
  repair)  cmd_repair ;;
  cron)    cmd_cron ;;
  archive) cmd_archive "$ARCHIVE_PATTERN" ;;
esac
