# Milestone 0: Repo Init Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** 初始化仓库到可协作开发状态：目录结构、文档、模板、CI，并对接 GitHub（remote + push + 用 gh 创建 Issue）。

**Architecture:** 先落文档与规范（PRD/Workflow/模板），再落 Core 包骨架，让 CI 有稳定的测试入口。

**Tech Stack:** Git + GitHub + GitHub Actions + SwiftPM (Core) + (later) Xcode/macOS App.

## Task 1: Scaffold files

**Files (create/modify):**
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `.editorconfig`
- Create: `docs/process/WORKFLOW.md`
- Create: `docs/plans/2026-02-07-macos-voice-keyboard-prd.md`
- Create: `docs/plans/2026-02-07-macos-voice-keyboard-implementation-plan.md`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/workflows/ci.yml`
- Create: `scripts/plan_to_issue.sh`

**Verification:**
- `git status --porcelain` shows new files only

## Task 2: Add SwiftPM Core skeleton

**Files (create):**
- `packages/VoiceKeyboardCore/Package.swift`
- `packages/VoiceKeyboardCore/Sources/VoiceKeyboardCore/VoiceKeyboardCore.swift`
- `packages/VoiceKeyboardCore/Tests/VoiceKeyboardCoreTests/VoiceKeyboardCoreTests.swift`

**Verification:**
- Run: `cd packages/VoiceKeyboardCore && swift test`
- Expected: PASS

## Task 3: GitHub connection + first push

**Steps:**
- Add remote: `git remote add origin git@github.com:superbloom-tech/ai-voice-keyboard.git`
- Commit: `git commit -m "chore: initial repo scaffold"`
- Push: `git push -u origin main`

## Task 4: Create initial tracking issues (gh)

**Steps:**
- Create label(s): `plan`, `macos`, `provider` (skip if already exists)
- Create issue for Milestone 0 (plan)
- Create issue(s) for Milestone 1 (Core) and Milestone 2 (macOS app skeleton)

