---
name: <skill-name>
description: "<从 vendor SKILL.md 的 description 复制，可按需微调措辞>"
---

<PLUME-OVERRIDE>
No overrides yet. Follow the vendor skill as-is.
</PLUME-OVERRIDE>

Now read and follow the vendor skill's complete content:

1. Use the Read tool to read: `PLUME_ROOT/vendor/superpowers/<skill-name>/SKILL.md` (replace PLUME_ROOT with the path from `[PLUME_ROOT: ...]` in your session context)
2. Follow all instructions in that file
3. Where the vendor skill conflicts with `<PLUME-OVERRIDE>` above, the override wins
4. Everything else: follow the vendor skill exactly

<!--
WRAPPER 编写指南
================

1. FRONTMATTER
   - name: 必须与 skills/ 下的目录名一致
   - description: 决定 Claude 何时自动触发此 skill
     - 从 vendor SKILL.md 复制 description 作为起点
     - 可按需调整触发条件的严格程度（参考 brainstorming 双版本）
     - 避免与其他 skill 的 description 语义重叠，防止误触发

2. <PLUME-OVERRIDE> 块
   - 暂无定制时写 "No overrides yet. Follow the vendor skill as-is."
   - 有定制时写具体覆盖规则，vendor 未提及的部分不受影响
   - 常见覆盖场景：
     - 输出路径（如 `<project-root>/docs/plume-skills/specs/` 替代 `docs/superpowers/`）
     - 流程门控（如 spec review 后等待用户确认）
     - 粒度要求（如任务拆分到半天可完成）
     - 触发条件变更（如仅显式请求时激活）

3. VENDOR 引用
   - 路径必须使用 PLUME_ROOT 显式引用，不可用相对路径
   - PLUME_ROOT 来自 session context 中 hook 注入的 [PLUME_ROOT: ...] 行
   - vendor 路径格式: PLUME_ROOT/vendor/superpowers/<skill-name>/SKILL.md

4. 部署注册
   - 核心 skill: 在 install.sh 的 CORE_PLUME_SKILLS 数组中添加
   - 项目 skill: 在 install.sh 的 PROJECT_SKILLS 数组中添加
   - 社区 vendor: 在 CORE_VENDOR_SKILLS 数组中添加（格式 "vendor/path:deploy-name"）

5. 注意事项
   - wrapper 目录名 = 部署后的 skill 名（install.sh 按目录名 symlink）
   - 如需通用/项目双版本，用不同目录名（如 brainstorming-universal vs brainstorming）
   - override 只写差异，不重复 vendor 原文内容
   - description 是唯一的触发机制，无 commands 字段，措辞要精准
-->
