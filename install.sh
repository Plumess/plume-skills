#!/usr/bin/env bash
# plume-skills 部署器
# 用法: ./install.sh --universal | --project [path] | archive <slug|--all>
set -euo pipefail

# ─── 颜色 ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[plume]${NC} $*"; }
ok()    { echo -e "${GREEN}[plume]${NC} $*"; }
warn()  { echo -e "${YELLOW}[plume]${NC} $*"; }
err()   { echo -e "${RED}[plume]${NC} $*" >&2; }

PLUME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

# ─── Skill 分类 ──────────────────────────────────────────────
# skills/ 中的原创/wrapper skills（通用安装）
UNIVERSAL_PLUME_SKILLS=(using-plume context-keeper digest)

# 通用 brainstorming（显式激活版，目录名与部署名不同）
UNIVERSAL_BRAINSTORMING_SRC="skills/brainstorming-universal"
UNIVERSAL_BRAINSTORMING_NAME="brainstorming"

# vendor/ 中的社区 skills（通用安装）
UNIVERSAL_VENDOR_SKILLS=(
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

merge_json_permissions() {
  local target="$1" template="$2"
  if ! command -v jq &>/dev/null; then
    warn "未找到 jq — 无法合并配置。请安装 jq 后重新执行。"
    warn "需要手动合并的模板: $template"
    return 0
  fi
  if [ ! -f "$target" ]; then
    if $DRY_RUN; then
      info "  将从模板创建 $target"
    else
      cp "$template" "$target"
      ok "  已创建 $target"
    fi
    return 0
  fi
  # Check if all template permissions already exist in target
  local new_count
  new_count="$(jq -s '
    (.[0].permissions.allow // []) as $existing |
    (.[1].permissions.allow // []) as $new |
    ($new - $existing) | length
  ' "$target" "$template" 2>/dev/null || echo "-1")"
  if [ "$new_count" = "0" ]; then
    info "  权限已包含全部模板条目，跳过"
    return 0
  fi
  if $DRY_RUN; then
    info "  将合并权限到 $target（新增 $new_count 条）"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  jq -s '
    (.[0].permissions.allow // []) as $existing |
    (.[1].permissions.allow // []) as $new |
    .[0] * { permissions: { allow: ($existing + $new | unique) } }
  ' "$target" "$template" > "$tmp" && mv "$tmp" "$target"
  ok "  已合并权限到 $target（新增 $new_count 条）"
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
cmd_universal() {
  info "安装通用 skills 到 ~/.claude/skills/"
  echo ""

  info "将安装以下 skills:"
  info "  - using-plume — 会话引导（hook 注入）"
  info "  - context-keeper — compact 保存/恢复"
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

  mkdir -p "$HOME/.claude/skills"

  # 链接原创/wrapper skills（来自 skills/）
  info "正在链接 plume skills..."
  for skill in "${UNIVERSAL_PLUME_SKILLS[@]}"; do
    symlink_skill "$PLUME_ROOT/skills/$skill" "$HOME/.claude/skills/$skill" "$skill"
  done
  # brainstorming 通用版（目录名 ≠ 部署名）
  symlink_skill "$PLUME_ROOT/$UNIVERSAL_BRAINSTORMING_SRC" "$HOME/.claude/skills/$UNIVERSAL_BRAINSTORMING_NAME" "$UNIVERSAL_BRAINSTORMING_NAME"

  # 链接 vendor skills（来自 vendor/ 子目录）
  info "正在链接 vendor skills..."
  for entry in "${UNIVERSAL_VENDOR_SKILLS[@]}"; do
    local rel_path="${entry%%:*}"
    local name="${entry##*:}"
    local src="$PLUME_ROOT/$rel_path"
    if [ -d "$src" ] && [ -f "$src/SKILL.md" ]; then
      symlink_skill "$src" "$HOME/.claude/skills/$name" "$name"
    else
      warn "  $name — 未找到 $rel_path/SKILL.md"
    fi
  done
  echo ""

  # 合并 hooks 到 settings.local.json（替换 __PLUME_ROOT__ 为实际路径）
  info "合并 hooks 配置..."
  local settings_file="$HOME/.claude/settings.local.json"
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
  merge_json_permissions "$settings_file" "$PLUME_ROOT/templates/settings.local.append.json"
  echo ""

  # 写入 plume_root
  info "写入配置..."
  write_plume_root
  echo ""

  ok "通用安装完成。"
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

  info "安装项目 skills 到 $target/.claude/skills/"
  echo ""

  info "将安装 ${#PROJECT_SKILLS[@]} 个工作流 skills:"
  for skill in "${PROJECT_SKILLS[@]}"; do
    info "  - $skill"
  done
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
  echo ""

  info "合并权限配置..."
  merge_json_permissions "$target/.claude/settings.local.json" "$PLUME_ROOT/templates/settings.local.append.json"
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

cmd_repair() {
  info "修复 plume-skills 路径引用..."
  echo ""

  # 1. 更新 config.yml 中的 plume_root
  info "更新 config.yml..."
  write_plume_root

  # 2. 重建 ~/.claude/skills/ symlinks
  if [ -d "$HOME/.claude/skills" ]; then
    info "修复通用 skills symlinks..."
    for skill in "${UNIVERSAL_PLUME_SKILLS[@]}"; do
      local dest="$HOME/.claude/skills/$skill"
      if [ -L "$dest" ]; then
        rm "$dest"
        ln -sf "$PLUME_ROOT/skills/$skill" "$dest"
        ok "  $skill — 已更新"
      fi
    done
    # brainstorming 通用版
    local bs_dest="$HOME/.claude/skills/$UNIVERSAL_BRAINSTORMING_NAME"
    if [ -L "$bs_dest" ]; then
      rm "$bs_dest"
      ln -sf "$PLUME_ROOT/$UNIVERSAL_BRAINSTORMING_SRC" "$bs_dest"
      ok "  $UNIVERSAL_BRAINSTORMING_NAME — 已更新"
    fi
    for entry in "${UNIVERSAL_VENDOR_SKILLS[@]}"; do
      local rel_path="${entry%%:*}"
      local name="${entry##*:}"
      local dest="$HOME/.claude/skills/$name"
      if [ -L "$dest" ]; then
        rm "$dest"
        ln -sf "$PLUME_ROOT/$rel_path" "$dest"
        ok "  $name — 已更新"
      fi
    done
  fi

  # 3. 修复 settings.local.json 中的 hook 路径
  local settings_file="$HOME/.claude/settings.local.json"
  if [ -f "$settings_file" ] && grep -q "hooks/session-start" "$settings_file"; then
    info "修复 hook 路径..."
    if command -v jq &>/dev/null; then
      local tmp
      tmp="$(mktemp)"
      jq --arg path "$PLUME_ROOT/hooks/session-start" \
        '.hooks.SessionStart[0].hooks[0].command = ("\"\($path)\"")' \
        "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
      ok "  hook 路径已更新为 $PLUME_ROOT/hooks/session-start"
    else
      warn "  未找到 jq — 请手动更新 $settings_file 中的 hook 路径"
    fi
  fi

  # 4. 扫描项目级 symlinks（提示用户）
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

# ─── 主入口 ───────────────────────────────────────────────────
usage() {
  cat <<'EOF'
plume-skills 部署器

用法:
  ./install.sh --universal [--dry-run]       部署通用 skills 到 ~/.claude/
  ./install.sh --project [path] [--dry-run]  部署项目 skills 到 <path>/.claude/
  ./install.sh --repair                      修复搬迁后的路径引用
  ./install.sh archive <keyword|--all>       归档项目数据用于迁移
  ./install.sh --help                        显示帮助

vendor/ 中的内容已随项目一起分发，无需额外拉取。
EOF
}

CMD=""
PROJECT_PATH=""
ARCHIVE_PATTERN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal)  CMD="universal"; shift ;;
    --project)    CMD="project"; shift
                  if [ "${1:-}" ] && [[ ! "$1" =~ ^-- ]]; then
                    PROJECT_PATH="$1"; shift
                  fi ;;
    --repair)     CMD="repair"; shift ;;
    archive)      CMD="archive"; shift; ARCHIVE_PATTERN="${1:---all}"; shift 2>/dev/null || true ;;
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
  universal) cmd_universal ;;
  project)   cmd_project "$PROJECT_PATH" ;;
  repair)    cmd_repair ;;
  archive)   cmd_archive "$ARCHIVE_PATTERN" ;;
esac
