#!/usr/bin/env bash
# plume-skills v3 部署器
# 用法：./install.sh [--base <path>] | --update | --repair | cron [HH:MM] | archive <keyword|--all>
# 模型：每个 scope（~/.claude/ 或 <base>/.claude/）独立部署，全部 symlink 指向同一 git 仓库源。

set -euo pipefail

# ─── 颜色 & 日志 ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[plume]${NC} $*"; }
ok()    { echo -e "${GREEN}[plume]${NC} $*"; }
warn()  { echo -e "${YELLOW}[plume]${NC} $*"; }
err()   { echo -e "${RED}[plume]${NC} $*" >&2; }

# ─── 全局状态 ─────────────────────────────────────────────────
PLUME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
ASSUME_YES=false
BASE_DIR=""
USE_USER_LEVEL=false   # --global 显式装到 ~/.claude/ 时为 true

# ─── v3 Skill 清单（平铺，无 core/project 分流）────────────
V3_SKILLS=(using-plume code-review socratic-dialogue digest)

# ─── 已知 v1/v2 遗留 skill 名（文档用途；清理由 scan_orphan_links 统一按"指向 plume-skills 的 symlink"规则处理）
# brainstorming, context-keeper, writing-plans, executing-plans,
# finishing-a-development-branch, requesting/receiving-code-review,
# dispatching-parallel-agents, subagent-driven-development,
# systematic-debugging, test-driven-development, verification-before-completion,
# using-git-worktrees, find-skills, skill-creator

# ─── 核心路径计算 ─────────────────────────────────────────────
# 优先级: --base 显式路径 > --global (~/.claude/) > 默认 base-level (PLUME_ROOT 父目录)
#
# 默认从 user-level 改为 base-level 的原因:
# Claude Code 规则下 user-level (personal) 永远覆盖 project-level (project) 同名 skill,
# 因此装在 user-level 会让所有 base-level 隔离失效。默认装到本仓库父目录的 .claude/
# 实现多 clone 天然隔离, 想全机生效请显式 --global。
claude_dir() {
  if [ -n "$BASE_DIR" ]; then
    echo "$BASE_DIR/.claude"
  elif $USE_USER_LEVEL; then
    echo "$HOME/.claude"
  else
    echo "$(dirname "$PLUME_ROOT")/.claude"
  fi
}

marker_file() {
  echo "$(claude_dir)/.plume-install-state.json"
}

permissions_manifest() {
  echo "$PLUME_ROOT/data/.installed-permissions.json"
}

# ─── marker 读写 ──────────────────────────────────────────────
read_marker() {
  local mf; mf="$(marker_file)"
  if [ -f "$mf" ]; then cat "$mf"; else echo "{}"; fi
}

write_marker() {
  local mf; mf="$(marker_file)"
  local cd; cd="$(claude_dir)"
  $DRY_RUN && { info "  将写入 marker $mf"; return 0; }
  mkdir -p "$cd"
  local skills_json; skills_json="$(printf '%s\n' "${V3_SKILLS[@]}" | jq -R . | jq -s .)"
  jq -n \
    --arg deploy_root "$cd" \
    --arg base "$BASE_DIR" \
    --arg plume_root "$PLUME_ROOT" \
    --arg version "v3-slim" \
    --argjson skills "$skills_json" \
    --argjson hooks '["SessionStart","UserPromptSubmit"]' \
    '{
      deploy_root: $deploy_root,
      base: $base,
      plume_root: $plume_root,
      installed_version: $version,
      installed_skills: $skills,
      installed_hooks: $hooks,
      updated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    }' > "$mf"
  ok "  marker 已写入: $mf"
}

# 判断 deploy_root 是否已被 plume 装过
is_installed() {
  local cd; cd="$(claude_dir)"
  [ -f "$(marker_file)" ] && return 0
  # 无 marker 但有 using-plume symlink → v1/v2 遗留
  [ -L "$cd/skills/using-plume" ] && return 0
  return 1
}

# ─── Scope guard ─────────────────────────────────────────────
# 检查当前 deploy_root 的 marker:
#   - 不存在 marker → 干净, 通过
#   - 存在且 plume_root == 本仓库 → 通过 (升级/重装本仓库的同一 scope)
#   - 存在且 plume_root != 本仓库 → exit 1 (该 scope 被另一份占用, 拒绝静默覆盖)
scope_guard() {
  local prev_deploy_root; prev_deploy_root="$(read_marker | jq -r '.deploy_root // empty' 2>/dev/null || true)"
  local prev_plume_root;  prev_plume_root="$(read_marker | jq -r '.plume_root // empty' 2>/dev/null || true)"
  local current; current="$(claude_dir)"

  # marker 不存在 → 干净
  [ -z "$prev_deploy_root" ] && return 0

  # marker 存在但 deploy_root 字段与当前计算不符 → 异常 (手动改过 marker 或 fs)
  if [ "$prev_deploy_root" != "$current" ]; then
    err "Scope 状态异常: marker 记录 deploy_root=$prev_deploy_root, 当前计算=$current"
    err "可能是手动改了 marker 或 fs。请检查 $current/.plume-install-state.json"
    exit 1
  fi

  # 同一 deploy_root 被另一份 plume-skills 占用 → 拒绝
  if [ -n "$prev_plume_root" ] && [ "$prev_plume_root" != "$PLUME_ROOT" ]; then
    err "该 scope 已被另一份 plume-skills 占用:"
    err "   现有 marker plume_root: $prev_plume_root"
    err "   本次仓库:              $PLUME_ROOT"
    err ""
    err "需要人工裁决, 可选:"
    err "   (a) 先在那份仓库下卸载: cd $prev_plume_root && ./install.sh --uninstall $(scope_flag_hint)"
    err "   (b) 换到其他 scope: ./install.sh --base /opt/another"
    exit 1
  fi
}

# scope_guard 报错时给用户的卸载命令提示
scope_flag_hint() {
  if [ -n "$BASE_DIR" ]; then
    echo "--base $BASE_DIR"
  elif $USE_USER_LEVEL; then
    echo "--global"
  else
    echo ""
  fi
}

# ─── Sanity check: 检测 user-level 是否被其他仓库占用 ─────────
# 仅在装 base-level 时调用。检测到冲突时强警告 (Claude Code 加载规则:
# user-level 永远覆盖 project-level, 残留会让本次 base 安装失效)
sanity_check_user_level_residue() {
  $USE_USER_LEVEL && return 0   # 装 user-level 本身不查这个

  local user_skills="$HOME/.claude/skills"
  [ -d "$user_skills" ] || return 0

  local conflicting=()
  local self_residue=()
  for skill in "${V3_SKILLS[@]}"; do
    local link="$user_skills/$skill"
    [ -L "$link" ] || continue
    local target; target="$(readlink -f "$link" 2>/dev/null || true)"
    [ -z "$target" ] && continue
    # 提取仓库根: target 形如 <repo>/skills/<name>
    if [[ "$target" == */skills/"$skill" ]]; then
      local repo_root; repo_root="${target%/skills/$skill}"
      if [ "$repo_root" = "$PLUME_ROOT" ]; then
        self_residue+=("$skill")
      else
        conflicting+=("$skill → $repo_root")
      fi
    fi
  done

  if [ ${#conflicting[@]} -gt 0 ]; then
    echo ""
    warn "⚠️  Sanity check — user-level 残留警告:"
    warn "   ~/.claude/skills/ 下检测到另一份 plume-skills 的同名 skill:"
    for c in "${conflicting[@]}"; do
      warn "     $c"
    done
    warn ""
    warn "   Claude Code 规则: user-level (personal) 永远覆盖 project-level (project)"
    warn "   后果: 本次 base-level 安装的同名 skill 不会被 Claude Code 加载"
    warn "   修复: 在占用方仓库下跑 ./install.sh --uninstall --global"
    warn "         然后回本仓库跑 ./install.sh --update"
    echo ""
  fi

  if [ ${#self_residue[@]} -gt 0 ]; then
    info "  备注: ~/.claude/skills/ 下有指向本仓库的残留 (${self_residue[*]}),"
    info "        可能是历史 --global 安装。如不需要全机生效, 跑 ./install.sh --uninstall --global"
  fi
}

# ─── Sanity check: --global 安装前的强警告 + 用户确认 ─────────
sanity_check_global_install() {
  $USE_USER_LEVEL || return 0

  echo ""
  warn "⚠️  WARNING — --global 安装注意事项:"
  warn "   Claude Code 规则: user-level (personal) 永远覆盖 project-level (project)"
  warn "   后果: 任何用 ./install.sh (默认 base-level) 装的其他 plume-skills 仓库,"
  warn "         其同名 skill 都会被本次 user-level 安装静默覆盖"
  warn "   推荐: 仅在你确认只会有一份 plume-skills clone 时使用 --global"
  warn "         多仓库共存请用默认 ./install.sh (base-level)"
  echo ""

  if $DRY_RUN; then
    info "  [dry-run] 跳过确认"
    return 0
  fi
  if $ASSUME_YES; then
    info "  [--yes] 自动确认"
    return 0
  fi

  read -rp "继续 --global 安装？[y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy] ]]; then
    info "已取消。建议改用默认: ./install.sh (无 --global, 自动装到本仓库父目录)"
    exit 0
  fi
}

# ─── symlink helpers ─────────────────────────────────────────
sym_create() {
  local src="$1" dest="$2" name="$3"
  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    warn "  $name — 源不存在 ($src)，跳过"
    return 0
  fi
  if [ -L "$dest" ]; then
    local existing; existing="$(readlink -f "$dest" 2>/dev/null || true)"
    local target; target="$(readlink -f "$src" 2>/dev/null || true)"
    if [ "$existing" = "$target" ]; then
      info "  $name — 已链接"
    else
      if $DRY_RUN; then
        info "  $name — 将更新链接（旧→ $existing）"
      else
        rm "$dest"; ln -sf "$src" "$dest"
        ok "  $name — 已更新链接"
      fi
    fi
  elif [ -e "$dest" ]; then
    warn "  $name — 已存在且非 symlink，跳过（保护用户自定义）"
  else
    if $DRY_RUN; then
      info "  $name — 将新增链接"
    else
      ln -sf "$src" "$dest"
      ok "  $name — 已链接"
    fi
  fi
}

# ─── 删除前列表 + 确认（所有删除操作必须走这个） ──────────
# 用法：confirm_deletion "<描述>" <path1> <path2> ...
# 返回 0 表示用户确认删除；非 0 表示跳过
confirm_deletion() {
  local description="$1"; shift
  local items=("$@")
  [ ${#items[@]} -eq 0 ] && return 1

  echo ""
  warn "即将删除 ${#items[@]} 项 — $description:"
  for item in "${items[@]}"; do
    if [ -L "$item" ]; then
      local target; target="$(readlink "$item" 2>/dev/null || echo "?")"
      echo "  - $item  →  $target"
    elif [ -e "$item" ]; then
      local size; size="$(du -sh "$item" 2>/dev/null | cut -f1 || echo "?")"
      echo "  - $item  ($size)"
    else
      echo "  - $item  (已不存在)"
    fi
  done
  echo ""

  if $DRY_RUN; then
    info "  [dry-run] 上列项目不会被删除"
    return 1
  fi

  if $ASSUME_YES; then
    info "  [--yes] 自动确认"
    return 0
  fi

  read -rp "确认删除以上项目？[y/N] " confirm
  if [[ "$confirm" =~ ^[Yy] ]]; then
    return 0
  else
    warn "  已保留，跳过本批删除"
    return 1
  fi
}

# ─── 权限三方 diff（沿用 v2 逻辑）────────────────────────────
sync_permissions() {
  local target="$1" template="$2"
  local manifest; manifest="$(permissions_manifest)"

  if ! command -v jq &>/dev/null; then
    warn "未找到 jq — 无法同步权限。请安装 jq 后重试。"
    return 0
  fi

  # 模板中的 __PLUME_ROOT__ 占位符在此处解析为真实路径（与 sync_hooks 同机制）
  local template_resolved; template_resolved="$(mktemp)"
  sed "s|__PLUME_ROOT__|$PLUME_ROOT|g" "$template" > "$template_resolved"

  # 首次安装：target 不存在
  if [ ! -f "$target" ]; then
    if $DRY_RUN; then
      info "  将从模板创建 $target"
    else
      cp "$template_resolved" "$target"
      mkdir -p "$(dirname "$manifest")"
      cp "$template_resolved" "$manifest"
      ok "  已创建 $target"
    fi
    rm -f "$template_resolved"
    return 0
  fi

  # 快照不存在（旧版升级）→ 视模板为旧快照，首次 update 不删任何条目
  local manifest_file="$manifest"
  [ -f "$manifest_file" ] || manifest_file="$template_resolved"

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
  ' "$target" "$template_resolved" "$manifest_file" 2>/dev/null || echo '{"stale":0,"add":0,"result":[]}')"

  local stale_count add_count
  stale_count="$(echo "$diff_info" | jq '.stale')"
  add_count="$(echo "$diff_info" | jq '.add')"

  if [ "$stale_count" = "0" ] && [ "$add_count" = "0" ]; then
    info "  权限已是最新"
    [ ! -f "$manifest" ] && ! $DRY_RUN && { mkdir -p "$(dirname "$manifest")"; cp "$template_resolved" "$manifest"; }
    rm -f "$template_resolved"
    return 0
  fi

  if $DRY_RUN; then
    [ "$stale_count" != "0" ] && info "  将移除 $stale_count 条旧版 plume 权限"
    [ "$add_count" != "0" ] && info "  将新增 $add_count 条权限"
    rm -f "$template_resolved"
    return 0
  fi

  local tmp; tmp="$(mktemp)"
  echo "$diff_info" | jq '{ permissions: { allow: .result } }' > "$tmp"
  jq -s '.[0] * .[1]' "$target" "$tmp" > "${tmp}.merged" && mv "${tmp}.merged" "$target"
  rm -f "$tmp"

  mkdir -p "$(dirname "$manifest")"
  cp "$template_resolved" "$manifest"
  rm -f "$template_resolved"

  local msg=""
  [ "$stale_count" != "0" ] && msg="移除 $stale_count 条旧版"
  [ "$add_count" != "0" ] && msg="${msg:+$msg，}新增 $add_count 条"
  ok "  权限已同步（$msg）"
}

# ─── hooks 同步（完整替换 hooks 字段，保留其他）────────────
sync_hooks() {
  local settings_file="$1"
  local hooks_resolved
  hooks_resolved="$(sed "s|__PLUME_ROOT__|$PLUME_ROOT|g" "$PLUME_ROOT/hooks/hooks.json")"

  if [ ! -f "$settings_file" ]; then
    if $DRY_RUN; then
      info "  将创建 $settings_file（含 hooks）"
    else
      echo "$hooks_resolved" > "$settings_file"
      ok "  已创建 $settings_file（含 hooks）"
    fi
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    warn "  未找到 jq — 请手动合并 $PLUME_ROOT/hooks/hooks.json 到 $settings_file"
    return 0
  fi

  local hooks_diff
  hooks_diff="$(jq -s '
    (.[0].hooks // {}) as $current |
    (.[1].hooks // {}) as $template |
    if $current == $template then "match" else "differ" end
  ' "$settings_file" <(echo "$hooks_resolved") 2>/dev/null || echo '"differ"')"

  if [ "$hooks_diff" = '"match"' ]; then
    info "  hooks 已与模板一致"
    return 0
  fi

  if $DRY_RUN; then
    info "  将更新 hooks 配置"
  else
    local tmp; tmp="$(mktemp)"
    jq -s '.[0] * { hooks: .[1].hooks }' "$settings_file" <(echo "$hooks_resolved") > "$tmp" && mv "$tmp" "$settings_file"
    ok "  hooks 已同步（v3 仅 SessionStart + UserPromptSubmit）"
  fi
}

# ─── v1/v2 迁移清理（显式列表 + 逐项确认）──────────────────
# 顺序：config.yml 字段 → data/ 残留 → context-keeper 数据
# 每项扫描器独立处理展示和确认；用户可逐项选择保留或清理
migrate_legacy() {
  info "检查 config.yml 废弃字段..."
  scan_config_stale_fields

  info "检查 data/ 残留文件..."
  scan_stale_data_files

  info "检查 ~/.claude/projects/*/plume-context/ 数据..."
  scan_plume_context_data
}

# ─── 写 plume_root 到 config ──────────────────────────────────
write_plume_root() {
  if $DRY_RUN; then
    info "  将写入 plume_root=$PLUME_ROOT 到 config.yml"
    return 0
  fi
  sed -i "s|^plume_root:.*|plume_root: \"$PLUME_ROOT\"|" "$PLUME_ROOT/config.yml"
  ok "  plume_root 已设为 $PLUME_ROOT"
}

# ─── 交互式 digest 配置（仅 fresh install 走） ────────────────
interactive_digest_config() {
  $DRY_RUN && return 0
  echo ""
  info "配置 digest"
  echo ""

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
  echo ""
  read -rp "  default_scope [$default_scope]: " input_scope
  local final_scope="${input_scope:-$default_scope}"
  if [ -n "$final_scope" ] && [ "$final_scope" != "$current_scope" ]; then
    sed -i "s|^\(\s*default_scope:\).*|\1 \"$final_scope\"|" "$PLUME_ROOT/config.yml"
    ok "  default_scope = \"$final_scope\""
  fi

  local current_cron current_tz
  current_cron="$(grep -oP '^\s*cron_time:\s*"\K[^"]*' "$PLUME_ROOT/config.yml" 2>/dev/null || echo "06:00")"
  current_tz="$(grep -oP '^\s*timezone:\s*"\K[^"]*' "$PLUME_ROOT/config.yml" 2>/dev/null || echo "Asia/Shanghai")"
  echo ""
  read -rp "  日报生成时间 (cron_time, 时区: $current_tz) [$current_cron]: " input_cron
  local final_cron="${input_cron:-$current_cron}"
  if [ "$final_cron" != "$current_cron" ]; then
    sed -i "s|^\(\s*cron_time:\).*|\1 \"$final_cron\"|" "$PLUME_ROOT/config.yml"
    ok "  cron_time = \"$final_cron\""
  fi

  echo ""
  info "运行 ./install.sh cron 配置定时日报生成。"
}

# ─── 扫描未知 skill 链接（指向 plume-skills 但不在 V3_SKILLS）
scan_orphan_links() {
  local cd; cd="$(claude_dir)"
  [ -d "$cd/skills" ] || return 0
  local orphans=()
  for link in "$cd/skills"/*; do
    [ -L "$link" ] || continue
    local name; name="$(basename "$link")"
    local in_v3=false
    for v3 in "${V3_SKILLS[@]}"; do
      [ "$name" = "$v3" ] && { in_v3=true; break; }
    done
    $in_v3 && continue
    local target; target="$(readlink "$link" 2>/dev/null || true)"
    # 仅收集指向本仓的 / 断链的；外部 symlink 保留
    if [[ "$target" == *plume-skills* ]] || [ ! -e "$link" ]; then
      orphans+=("$link")
    else
      warn "  $name — 指向外部（$target），跳过"
    fi
  done
  if [ ${#orphans[@]} -eq 0 ]; then
    info "  无遗留 skill 链接"
    return 0
  fi
  if confirm_deletion "遗留 v1/v2 skill 链接" "${orphans[@]}"; then
    for link in "${orphans[@]}"; do
      rm -f "$link" && ok "  $(basename "$link") — 已删除"
    done
  fi
}

# ─── 扫描旧版 context-keeper 数据目录 ─────────────────────────
# v1/v2 context-keeper 在 ~/.claude/projects/<slug>/plume-context/ 产生数据
# v3 已移除该 skill，数据需清理
scan_plume_context_data() {
  local projects_dir="$HOME/.claude/projects"
  [ -d "$projects_dir" ] || return 0
  local contexts=()
  while IFS= read -r dir; do
    contexts+=("$dir")
  done < <(find "$projects_dir" -maxdepth 2 -name plume-context -type d 2>/dev/null || true)

  if [ ${#contexts[@]} -eq 0 ]; then
    info "  无旧版 context-keeper 数据"
    return 0
  fi

  if confirm_deletion "旧版 context-keeper 生成的数据目录" "${contexts[@]}"; then
    for dir in "${contexts[@]}"; do
      rm -rf "$dir" && ok "  $dir — 已删除"
    done
  fi
}

# ─── 扫描旧版 data/ 内废弃文件 ────────────────────────────────
scan_stale_data_files() {
  local stale=()
  # v1 save-pending marker
  while IFS= read -r f; do
    [ -n "$f" ] && stale+=("$f")
  done < <(ls "$PLUME_ROOT/data"/.save-pending-* 2>/dev/null || true)
  # v1 digest-hint 目录
  [ -d "$PLUME_ROOT/data/digest-hint" ] && stale+=("$PLUME_ROOT/data/digest-hint")

  if [ ${#stale[@]} -eq 0 ]; then
    info "  无旧版 data/ 残留文件"
    return 0
  fi

  if confirm_deletion "旧版 data/ 残留（save-pending markers / digest-hint 等）" "${stale[@]}"; then
    for item in "${stale[@]}"; do
      rm -rf "$item" && ok "  $(basename "$item") — 已删除"
    done
  fi
}

# ─── 扫描 config.yml 中的废弃字段（不直接删；先展示预览） ────
scan_config_stale_fields() {
  local config="$PLUME_ROOT/config.yml"
  [ -f "$config" ] || return 0
  local matched_lines
  matched_lines="$(grep -nE '^\s*(auto_generate|remind_at|max_data_size_mb|^context:)' "$config" 2>/dev/null || true)"
  # 同时检测 context: 段存在
  local has_context_section=false
  grep -qE '^context:' "$config" && has_context_section=true

  if [ -z "$matched_lines" ] && ! $has_context_section; then
    info "  config.yml 无废弃字段"
    return 0
  fi

  echo ""
  warn "config.yml 包含废弃字段（v3 已不使用）:"
  [ -n "$matched_lines" ] && echo "$matched_lines" | sed 's/^/  /'
  $has_context_section && echo "  (整段 context: 将被移除)"
  echo ""

  if $DRY_RUN; then
    info "  [dry-run] 不执行清理"
    return 0
  fi
  if ! $ASSUME_YES; then
    read -rp "从 config.yml 移除以上字段？[y/N] " confirm
    [[ "$confirm" =~ ^[Yy] ]] || { warn "  已保留 config.yml"; return 0; }
  fi

  sed -i '/^\s*auto_generate:/d; /^\s*remind_at:/d; /^\s*max_data_size_mb:/d; /^\s*- "[0-9]\{2\}:[0-9]\{2\}"/d' "$config"
  # 移除整段 context: (至下一顶层字段前的所有缩进行)
  sed -i '/^context:/,/^[^ #]/{/^context:/d; /^\s/d}' "$config"
  # 清理可能残留的孤立注释
  sed -i '/^\s*# 自动生成/d; /^\s*# false 时仅提示/d; /^\s*# 最早提醒时间/d; /^\s*# 条件：/d; /^\s*# 每天每个时间点/d; /^\s*# 数据量上限/d; /^\s*# 上下文快照管理/d' "$config"
  ok "  config.yml 已清理"
}

# ─── 命令：install（新装或自动转 update） ─────────────────────
cmd_install() {
  scope_guard

  local cd; cd="$(claude_dir)"

  if is_installed; then
    info "检测到已有安装（$cd），自动进入更新模式..."
    echo ""
    cmd_update
    return 0
  fi

  # 装 user-level (--global) 前的强警告 + 二次确认
  sanity_check_global_install

  local scope_label
  if [ -n "$BASE_DIR" ]; then
    scope_label="custom scope --base $BASE_DIR"
  elif $USE_USER_LEVEL; then
    scope_label="user-level (~/.claude/, 全机生效)"
  else
    scope_label="base-level (仅 cwd 在 $(dirname "$PLUME_ROOT")/ 下时生效)"
  fi

  info "全新安装 plume-skills v3 → $cd/skills/"
  info "  scope:  $scope_label"
  info "  skills: ${V3_SKILLS[*]}"
  info "  hooks:  SessionStart + UserPromptSubmit"
  echo ""

  if ! $DRY_RUN; then
    read -rp "继续？[Y/n] " confirm
    [[ "$confirm" =~ ^[Nn] ]] && { info "已取消。"; exit 0; }
  fi

  mkdir -p "$cd/skills"

  info "链接 skills..."
  for skill in "${V3_SKILLS[@]}"; do
    sym_create "$PLUME_ROOT/skills/$skill" "$cd/skills/$skill" "$skill"
  done
  echo ""

  info "合并 hooks..."
  local settings_file="$cd/settings.local.json"
  sync_hooks "$settings_file"
  echo ""

  info "合并权限..."
  sync_permissions "$settings_file" "$PLUME_ROOT/templates/settings.local.append.json"
  echo ""

  info "写入配置..."
  write_plume_root
  write_marker
  echo ""

  # 装完后扫 user-level 残留 (装 base-level 时才有意义)
  sanity_check_user_level_residue

  ok "安装完成。"
  interactive_digest_config
}

# ─── 命令：update（scope-aware 增量同步） ──────────────────────
cmd_update() {
  scope_guard

  local cd; cd="$(claude_dir)"
  info "更新 plume-skills → $cd"
  echo ""

  if ! command -v jq &>/dev/null; then
    err "需要 jq。安装: sudo apt install jq / sudo dnf install jq"
    exit 1
  fi

  mkdir -p "$cd/skills"

  info "同步 v3 skills..."
  for skill in "${V3_SKILLS[@]}"; do
    sym_create "$PLUME_ROOT/skills/$skill" "$cd/skills/$skill" "$skill"
  done
  echo ""

  info "清理 v1/v2 遗留 skill 链接..."
  scan_orphan_links
  echo ""

  local settings_file="$cd/settings.local.json"
  info "同步 hooks..."
  sync_hooks "$settings_file"
  echo ""

  info "同步权限..."
  sync_permissions "$settings_file" "$PLUME_ROOT/templates/settings.local.append.json"
  echo ""

  info "迁移检查..."
  migrate_legacy
  echo ""

  info "写入配置..."
  write_plume_root
  write_marker
  echo ""

  sanity_check_user_level_residue

  ok "更新完成。"
}

# ─── 命令：repair（全量重建） ──────────────────────────────────
cmd_repair() {
  scope_guard

  local cd; cd="$(claude_dir)"
  info "修复 plume-skills → $cd（全量重建）"
  echo ""

  mkdir -p "$cd/skills"

  info "重建 v3 skills..."
  for skill in "${V3_SKILLS[@]}"; do
    local dest="$cd/skills/$skill"
    if [ -L "$dest" ] || [ ! -e "$dest" ]; then
      if $DRY_RUN; then
        info "  $skill — 将重建"
      else
        rm -f "$dest"
        ln -sf "$PLUME_ROOT/skills/$skill" "$dest"
        ok "  $skill — 已重建"
      fi
    else
      warn "  $skill — 非 symlink，跳过"
    fi
  done
  echo ""

  info "清理遗留..."
  scan_orphan_links
  echo ""

  info "同步 hooks（完整替换）..."
  sync_hooks "$cd/settings.local.json"
  echo ""

  info "同步权限..."
  sync_permissions "$cd/settings.local.json" "$PLUME_ROOT/templates/settings.local.append.json"
  echo ""

  info "迁移检查..."
  migrate_legacy
  echo ""

  info "写入配置..."
  write_plume_root
  write_marker
  echo ""

  # 扫描项目级断链（只读提示，不主动清理其他部署点）
  local broken_found=false
  for dir in "$HOME"/*/.claude/skills; do
    [ -d "$dir" ] || continue
    for link in "$dir"/*; do
      [ -L "$link" ] || continue
      if [ ! -e "$link" ]; then
        if ! $broken_found; then
          warn "发现其他部署点的断链（需在对应部署点执行 --update --base <path> 修复）:"
          broken_found=true
        fi
        warn "  $link"
      fi
    done
  done

  ok "修复完成。"
}

# ─── 命令：uninstall（卸载指定 scope） ─────────────────────────
cmd_uninstall() {
  local cd; cd="$(claude_dir)"
  local mf; mf="$(marker_file)"

  # 必须有 marker 或 skills 目录之一
  if [ ! -f "$mf" ] && [ ! -d "$cd/skills" ]; then
    err "未在 $cd 检测到 plume-skills 安装 (无 marker, 无 skills/)"
    exit 1
  fi

  # 若有 marker, 验证指向本仓库
  if [ -f "$mf" ]; then
    local marker_plume; marker_plume="$(read_marker | jq -r '.plume_root // empty' 2>/dev/null || true)"
    if [ -n "$marker_plume" ] && [ "$marker_plume" != "$PLUME_ROOT" ]; then
      err "$cd 部署点 marker 指向其他仓库:"
      err "   marker plume_root: $marker_plume"
      err "   本次仓库:          $PLUME_ROOT"
      err "请在 $marker_plume 下跑 ./install.sh --uninstall [对应旗]"
      exit 1
    fi
  fi

  echo ""
  info "即将卸载 plume-skills 部署:"
  info "  scope:  $cd"
  info "  仓库:   $PLUME_ROOT"
  echo ""
  info "将删除:"
  for skill in "${V3_SKILLS[@]}"; do
    [ -L "$cd/skills/$skill" ] && info "  - $cd/skills/$skill"
  done
  [ -f "$cd/settings.local.json" ] && info "  - $cd/settings.local.json 中的 hooks 段 + plume 权限"
  [ -f "$mf" ] && info "  - $mf"
  echo ""
  info "保留: $cd/settings.local.json 中的其他配置, data/, config.yml, 仓库源文件"
  echo ""

  if $DRY_RUN; then
    info "  [dry-run] 不执行删除"
    return 0
  fi
  if ! $ASSUME_YES; then
    read -rp "确认卸载？[y/N] " confirm
    [[ "$confirm" =~ ^[Yy] ]] || { info "已取消"; exit 0; }
  fi

  # 删 skills symlinks
  for skill in "${V3_SKILLS[@]}"; do
    local link="$cd/skills/$skill"
    if [ -L "$link" ]; then
      rm -f "$link" && ok "  $skill — 已删除"
    fi
  done

  # 清空 settings.local.json 中 plume 部分 (hooks + 来自 manifest 的权限)
  local settings_file="$cd/settings.local.json"
  local manifest; manifest="$(permissions_manifest)"
  if [ -f "$settings_file" ] && command -v jq &>/dev/null; then
    local tmp; tmp="$(mktemp)"
    if [ -f "$manifest" ]; then
      # 同时清 hooks 段 + 权限段中来自 manifest 的条目
      jq -s '
        (.[0] | del(.hooks)) as $base |
        (.[1].permissions.allow // []) as $plume_perms |
        ($base.permissions.allow // []) as $current_perms |
        ($current_perms - $plume_perms) as $remaining |
        $base * { permissions: { allow: $remaining } }
      ' "$settings_file" "$manifest" > "$tmp" && mv "$tmp" "$settings_file"
      ok "  settings.local.json — hooks 段 + plume 权限已清"
    else
      # 无 manifest, 只清 hooks 段
      jq 'del(.hooks)' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
      ok "  settings.local.json — hooks 段已清 (无 manifest, 权限段保留)"
    fi
  fi

  # 删 manifest
  [ -f "$manifest" ] && rm -f "$manifest" && ok "  权限 manifest 已删除"

  # 删 marker
  [ -f "$mf" ] && rm -f "$mf" && ok "  marker 已删除"

  echo ""
  ok "卸载完成 — scope $cd"
  info "本仓库 ($PLUME_ROOT) 源文件未动。可重新跑 ./install.sh 或换 scope。"
}

# ─── 命令：doctor（诊断当前所有 scope 状态） ─────────────────
cmd_doctor() {
  info "plume-skills 部署诊断"
  echo ""
  info "本仓库 PLUME_ROOT: $PLUME_ROOT"
  echo ""

  # 待扫的 scope: user-level + 本仓库父目录 (base-level 默认位置)
  local base_default; base_default="$(dirname "$PLUME_ROOT")"
  local scopes=("$HOME/.claude" "$base_default/.claude")
  local labels=("user-level (~/.claude/)" "base-level ($base_default/.claude/)")

  local user_repo="" base_repo=""

  local i
  for i in 0 1; do
    local scope="${scopes[$i]}"
    local label="${labels[$i]}"

    local mf="$scope/.plume-install-state.json"
    local has_symlinks=false
    if [ -d "$scope/skills" ]; then
      local skill
      for skill in "${V3_SKILLS[@]}"; do
        [ -L "$scope/skills/$skill" ] && { has_symlinks=true; break; }
      done
    fi

    # 完全没装: 既无 marker 又无 v3 skill symlink
    if [ ! -f "$mf" ] && ! $has_symlinks; then
      info "  [ ] $label — 未安装"
      continue
    fi

    local marker_plume="(无 marker)"
    if [ -f "$mf" ]; then
      marker_plume="$(jq -r '.plume_root // "?"' "$mf" 2>/dev/null || echo "?")"
    fi
    [ "$i" = "0" ] && user_repo="$marker_plume"
    [ "$i" = "1" ] && base_repo="$marker_plume"

    if [ "$marker_plume" = "$PLUME_ROOT" ]; then
      ok "  [✓] $label — 本仓库已装"
    elif [ "$marker_plume" = "(无 marker)" ]; then
      warn "  [?] $label — 有 skills symlink 但无 marker (异常状态)"
    else
      info "  [○] $label — 装的是另一份: $marker_plume"
    fi

    local skill
    for skill in "${V3_SKILLS[@]}"; do
      local link="$scope/skills/$skill"
      if [ -L "$link" ]; then
        local t; t="$(readlink "$link" 2>/dev/null || echo '?')"
        if [ ! -e "$link" ]; then
          warn "       $skill → $t  (断链!)"
        else
          info "       $skill → $t"
        fi
      fi
    done
  done

  echo ""
  info "Claude Code 加载规则: enterprise > personal (user-level) > project (base-level)"
  echo ""

  # 错配检测
  if [ -n "$user_repo" ] && [ "$user_repo" != "(无 marker)" ] && [ -n "$base_repo" ] && [ "$base_repo" != "(无 marker)" ]; then
    if [ "$user_repo" != "$base_repo" ]; then
      warn "⚠️  user-level 与 base-level 装着不同仓库:"
      warn "   user-level → $user_repo"
      warn "   base-level → $base_repo"
      warn "   实际加载: user-level 那份 (base-level 同名 skill 被覆盖)"
      warn ""
      warn "   若你想用 base-level 那份生效, 卸 user-level:"
      warn "     cd $user_repo && ./install.sh --uninstall --global"
    fi
  fi

  # 推荐 cwd
  if [ "$base_repo" = "$PLUME_ROOT" ] && [ -z "$user_repo" -o "$user_repo" = "(无 marker)" ]; then
    info "推荐工作 cwd: $base_default/ 或其子目录 (此时 Claude Code 才会加载本仓库 skills)"
  fi

  echo ""
  info "诊断完成。"
}

# ─── 命令：archive（打包 data/） ───────────────────────────────
cmd_archive() {
  local pattern="$1"
  local archive_dir="$PLUME_ROOT/data/archives"
  local date_stamp; date_stamp="$(date +%Y-%m-%d)"
  mkdir -p "$archive_dir"

  if [ "$pattern" = "--all" ]; then
    local archive_name="plume-full-$date_stamp.tar.gz"
    info "归档全部项目数据..."
    if $DRY_RUN; then
      info "  将创建 $archive_dir/$archive_name"
    else
      tar czf "$archive_dir/$archive_name" -C "$PLUME_ROOT/data" --exclude='archives' . 2>/dev/null || { err "无数据可归档"; exit 1; }
      ok "已归档: $archive_dir/$archive_name"
    fi
  else
    local matches=()
    for dir in "$PLUME_ROOT/data/"*"$pattern"*/; do
      [ -d "$dir" ] && [[ "$(basename "$dir")" != "archives" ]] && matches+=("$dir")
    done
    [ ${#matches[@]} -eq 0 ] && { err "未匹配 '$pattern' 的数据"; exit 1; }

    info "匹配 ${#matches[@]} 项:"
    for dir in "${matches[@]}"; do info "  - $(basename "$dir")"; done

    local archive_name="$pattern-$date_stamp.tar.gz"
    if $DRY_RUN; then
      info "  将创建 $archive_dir/$archive_name"
    else
      local rel=()
      for dir in "${matches[@]}"; do rel+=("$(basename "$dir")"); done
      tar czf "$archive_dir/$archive_name" -C "$PLUME_ROOT/data" "${rel[@]}"
      ok "已归档: $archive_dir/$archive_name"
    fi
  fi
}

# ─── 命令：cron（写 digest 定时任务） ──────────────────────────
cmd_cron() {
  local config="$PLUME_ROOT/config.yml"

  command -v python3 &>/dev/null || { err "需要 python3 做时区转换"; exit 1; }
  command -v crontab &>/dev/null || { err "未找到 crontab。安装: sudo apt install cron / sudo dnf install cronie"; exit 1; }

  local scope; scope="$(grep -oP '^\s*default_scope:\s*"\K[^"]*' "$config" 2>/dev/null || true)"
  [ -z "$scope" ] && { err "config.yml 中 digest.default_scope 为空。先运行 ./install.sh"; exit 1; }

  local cron_marker="# plume-skills-digest:$scope"

  local config_cron cli_time
  config_cron="$(grep -oP '^\s*cron_time:\s*"\K[^"]*' "$config" 2>/dev/null || echo "06:00")"
  cli_time="${CRON_TIME:-}"
  local use_time="${cli_time:-$config_cron}"
  local target_hour="$((10#${use_time%%:*}))"
  local target_min="$((10#${use_time##*:}))"

  if [ -n "$cli_time" ] && [ "$cli_time" != "$config_cron" ]; then
    sed -i "s|^\(\s*cron_time:\).*|\1 \"$cli_time\"|" "$config"
    ok "config.yml cron_time 更新为 \"$cli_time\""
  fi

  local cron_result
  cron_result="$(python3 -c "
import datetime
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
note = f'跨天：{target_tz_name} {$target_hour:02d}:{$target_min:02d} = 本机前一天 {local_dt.strftime(\"%H:%M\")}' if day_diff != 0 else f'{target_tz_name} {$target_hour:02d}:{$target_min:02d} = 本机 {local_dt.strftime(\"%H:%M\")}'
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

  local date_cmd
  if [[ "$(uname)" == "Darwin" ]]; then
    date_cmd="\$(TZ=$tz_name date -v-1d +\\%Y-\\%m-\\%d)"
  else
    date_cmd="\$(TZ=$tz_name date -d yesterday +\\%Y-\\%m-\\%d)"
  fi

  local claude_bin; claude_bin="$(command -v claude 2>/dev/null || true)"
  [ -z "$claude_bin" ] && { err "未找到 claude CLI"; exit 1; }

  local cron_line="$cron_time * * * cd $project_dir && $claude_bin -p \"/digest daily $date_cmd --scope $scope\" --allowedTools \"Write Read Glob Grep Bash(head:*) Bash(stat:*) Bash(ls:*) Bash(mkdir:*) Bash(find:*)\" --output-format text >> $PLUME_ROOT/data/cron.log 2>&1 $cron_marker"

  echo ""
  info "日报 cron — scope: $scope（$tz_note）"

  if $DRY_RUN; then
    info "将写入 crontab:"
    echo "  $cron_line"
    return 0
  fi

  local existing filtered
  existing="$(crontab -l 2>/dev/null || true)"
  filtered="$(echo "$existing" | grep -v "$cron_marker" || true)"
  echo "${filtered:+$filtered
}$cron_line" | crontab -

  ok "crontab 已更新:"
  echo "  $cron_line"

  if command -v systemctl &>/dev/null; then
    if ! systemctl is-active --quiet cron 2>/dev/null && ! systemctl is-active --quiet crond 2>/dev/null; then
      warn "cron 服务未运行。启动: sudo systemctl start cron"
    fi
  fi
}

# ─── 帮助 & 入口 ─────────────────────────────────────────────
usage() {
  cat <<'EOF'
plume-skills v3 部署器

用法:
  ./install.sh [--dry-run]                            全新安装到 base-level (默认, 见下)
  ./install.sh --global [--dry-run]                   全新安装到 user-level (~/.claude/, 带强警告)
  ./install.sh --base <path> [--dry-run]              全新安装到指定路径 <path>/.claude/
  ./install.sh --update [scope-flag] [--dry-run]      同步 skills / hooks / 权限
  ./install.sh --repair [scope-flag] [--dry-run]      全量重建
  ./install.sh --uninstall [scope-flag] [--dry-run]   卸载指定 scope (保留源文件)
  ./install.sh --doctor                               诊断所有 scope 状态 + 错配检测
  ./install.sh cron [HH:MM]                           写 digest 日报 cron
  ./install.sh archive <keyword|--all>                归档 data/ 项目数据
  ./install.sh --help                                 显示帮助

  其中 [scope-flag] 是 --global / --base <path> 之一, 不传则用默认 base-level。

选项:
  (无 scope-flag) 默认: base-level, 部署到 <PLUME_ROOT 父目录>/.claude/
                       仅在 cwd 处于该父目录下时, Claude Code 才加载本仓库 skills
  --global         部署到 ~/.claude/ (user-level), 全机生效, 带强警告
  --base <path>    部署到 <path>/.claude/ (自定义独立 scope)
  --dry-run        预览不执行（仍会列出即将删除的项目）
  --yes            自动确认所有删除（跳过交互提示，非交互场景用）

为什么默认是 base-level (不是 user-level)?
  Claude Code 加载规则: enterprise > personal (user-level) > project (base-level)。
  user-level 永远覆盖同名 project-level skill。装在 user-level 会让所有其他 clone
  的 base-level 隔离失效。因此默认装到本仓库父目录的 .claude/, 多 clone 天然隔离;
  若你确定全机只会有一份 plume-skills, 显式 --global 即可。

部署模型（多 scope 互不干扰）:
  每个 scope（~/.claude/ 或 <base>/.claude/）独立部署，自有 marker 与 symlinks，
  全部指向同一份 git 仓库源。git pull 一次，各 scope 各自跑 --update 即可同步。

删除安全:
  任何删除操作（卸载 / 遗留 skill 链接 / 废弃 data 文件 / config 字段）
  都会先列出完整路径和大小，等待 [y/N] 确认。默认保守（拒绝即跳过）。

Scope 隔离铁律:
  所有 --update / --repair / --uninstall 只操作 marker 记录的 deploy_root。
  若要切换部署点, 先在原点 --uninstall 清理。

示例:
  # 默认 (多 clone 友好, 装到 PLUME_ROOT 父目录)
  ./install.sh

  # 全机生效 (确认只会有一份 clone 时使用)
  ./install.sh --global

  # 任意自定义 scope (项目隔离 / 多环境并存)
  ./install.sh --base /opt/work-project

  # 升级 / 修复 / 卸载 (跟首装时同样的 scope-flag)
  git pull
  ./install.sh --update                       # 更新默认 base-level
  ./install.sh --update --global              # 更新 user-level
  ./install.sh --update --base /opt/work      # 更新自定义 scope
  ./install.sh --uninstall --global           # 卸 user-level

  # 诊断
  ./install.sh --doctor
EOF
}

CMD=""
ARCHIVE_PATTERN=""
CRON_TIME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)     CMD="update"; shift ;;
    --repair)     CMD="repair"; shift ;;
    --uninstall)  CMD="uninstall"; shift ;;
    --doctor)     CMD="doctor"; shift ;;
    cron)         CMD="cron"; shift
                  if [ "${1:-}" ] && [[ "$1" =~ ^[0-9] ]]; then
                    CRON_TIME="$1"; shift
                  fi ;;
    archive)      CMD="archive"; shift; ARCHIVE_PATTERN="${1:---all}"; shift 2>/dev/null || true ;;
    --base)       shift; BASE_DIR="${1:?--base 需要指定路径}"; shift ;;
    --global)     USE_USER_LEVEL=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --yes|-y)     ASSUME_YES=true; shift ;;
    --help|-h)    usage; exit 0 ;;
    *)            err "未知选项: $1"; usage; exit 1 ;;
  esac
done

# --base 与 --global 互斥
if [ -n "$BASE_DIR" ] && $USE_USER_LEVEL; then
  err "--base 与 --global 互斥, 不能同时使用"
  exit 1
fi

# 默认命令：全新安装
[ -z "$CMD" ] && CMD="install"

case "$CMD" in
  install)   cmd_install ;;
  update)    cmd_update ;;
  repair)    cmd_repair ;;
  uninstall) cmd_uninstall ;;
  doctor)    cmd_doctor ;;
  cron)      cmd_cron ;;
  archive)   cmd_archive "$ARCHIVE_PATTERN" ;;
  *)         usage; exit 1 ;;
esac
