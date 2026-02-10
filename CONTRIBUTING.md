# Contributing

欢迎通过 Issue / PR 参与开发。

## Workflow

请先阅读 `docs/process/WORKFLOW.md`，包含：

- Issue -> Branch -> PR -> Review -> Merge 的流程
- 分支命名与提交规范（Conventional Commits）
- 用 `gh` CLI 将 plan 文档创建为 Issue 的方式

## Xcode Project Format (CI Compatibility)

CI currently builds the macOS app with Xcode 15.x. If you open/save the
`AIVoiceKeyboard.xcodeproj` with a newer Xcode, it may upgrade the project file
format (`objectVersion`) and cause CI to fail with a "future Xcode project file
format" error.

We enforce this via `scripts/check_xcodeproj_objectversion.sh` (runs in CI).
