# Development Workflow

本仓库目标：用规范的 Issue / 分支 / PR 流程推进开发，并让计划（plan）可追踪、可审阅、可落地。

## 1) 以 Issue 驱动开发

- 任何工作（feature/bug/chore）必须对应一个 Issue。
- PR 必须在描述里关联 Issue（例如：`Closes #123`），合并后自动关闭。

## 2) Plan -> Issue（用 gh CLI）

- Plan 文档放在 `docs/plans/`。
- 通过脚本把 plan 创建为 GitHub Issue（标签 `plan`）：

```bash
./scripts/plan_to_issue.sh docs/plans/<plan>.md
```

## 3) 分支命名

建议使用：

- `feat/<issue>-<slug>`
- `fix/<issue>-<slug>`
- `chore/<issue>-<slug>`

示例：

- `feat/12-macos-insert-mode`
- `fix/34-clipboard-restore`

## 4) 提交规范（Conventional Commits）

示例：

- `feat: add Apple Speech streaming stt`
- `fix: restore clipboard after insertion`
- `chore: init repo scaffolding`

## 5) PR 规范

- 必须填写 PR 模板（测试、权限影响、截图/录屏等）
- PR 描述必须包含足够上下文，建议最少包含：背景/目标、主要变更点、不包含项（刻意留到后续的范围）、测试方式/命令、关键文件导读/影响面
- 至少 1 个 review
- CI 必须通过

## 6) Security / Secrets

- API Key 必须存 Keychain（实现阶段会落地）
- 仓库禁止提交任何 `.env` / key 文件（`.gitignore` 已默认忽略）
