# Issue 30 Plan: 【Bug】Apple Speech 偶发 1101：自动重试一次 + 更清晰提示

Issue: https://github.com/superbloom-tech/ai-voice-keyboard/issues/30

## 现象
- Insert 录音停止后偶发进入 error。
- 控制台出现：`kAFAssistantErrorDomain Code=1101`，指向 `com.apple.speech.localspeechrecognition`。
- 间歇性，重启后通常恢复。

## 目标
- 识别到 1101 时：自动重试一次（不死循环）。
- 若重试成功：继续插入流程。
- 若仍失败：给出更可操作的错误提示（包含 domain/code）。
- 不引入云端 STT。

## 技术方案

### Root cause 假设
- 系统本地语音识别服务偶发不可用/卡死；错误在 stop/finalize 阶段冒泡。

### 重试策略（克制）
- 在 `AppleSpeechTranscriber`：
  - stop 阶段如果回调收到 error 且是 `kAFAssistantErrorDomain/1101`：不立刻 fail，而是记录该错误并继续等待 `isFinal` 或 timeout。
  - timeout 时：如果已有 `latestText`，则返回 best-effort 文本；否则抛出带 domain/code 的错误。
- 在 `AppDelegate`：
  - `stopTranscriptionAndInsert()` 如果 catch 到 1101：`Task.sleep(300~800ms)` 后调用一次 `stopTranscriptionAndInsert()` 的“仅 stop+取文本”重试路径（或直接调用 transcriber 的 stop 再取 best-effort）。
  - 仅重试一次；第二次仍失败则进入 error，并提示用户“稍后重试/必要时重启”。

### 初始化时机
- 不强行重构为 lazy init（避免改动过大），但可在 start 前确保权限已授权；后续如仍不稳再后移创建。

## 文件改动
- `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/Speech/AppleSpeechTranscriber.swift`
- `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/AppDelegate.swift`

## 风险
- 1101 的可复现性弱：需要以防御性实现为主，不能依赖本地复现。
- 过度重试会让 UX 变慢：必须限制为 1 次。

## 验收
- 1101 发生时不会立即硬失败；有一次自动重试。
- 失败时错误提示包含 domain/code，并提示可操作动作。
- CI 绿。
