# Issue 24 Plan: 【Insert Only】接入 Apple Speech 本地 STT：录音→转写→粘贴插入光标

Issue: https://github.com/superbloom-tech/ai-voice-keyboard/issues/24

## 目标与范围

交付一个“可日用”的 Insert-only 最小闭环：
- 热键：`⌥Space` 开始录音，再按一次停止。
- 流程：录音 -> Apple Speech STT 转写 -> 将文本插入当前应用光标处。
- 首版插入策略：写入剪贴板 + 发送 `Cmd+V` 粘贴；随后 best-effort 恢复原剪贴板。

非目标（本 Issue 不做）：
- Edit 模式（选区读取/替换/预览确认）。
- 云端 STT。
- 轻量清理/轻模型润色（见 Issue #26）。
- Accessibility(AX) 原生插入（见 Issue #27）。

## 技术方案（架构）

在 macOS app 侧引入最小的“Insert Pipeline”，并明确可扩展口：

- `AudioCapture`：本期可直接依赖 `AVAudioEngine` 输入节点 tap（由转写器内部管理）。
- `STTEngine`（可替换）：先实现 Apple Speech 版本。
- `TextInserter`（可替换）：首版实现 Paste 插入；后续替换为 AX 原生插入。

建议本期实现落在 app（`apps/macos/AIVoiceKeyboard`）内，先不侵入 `VoiceKeyboardCore`，避免 core 在没有可运行测试环境时增加不确定性。

### Apple Speech 转写策略

- `SFSpeechAudioBufferRecognitionRequest` + `SFSpeechRecognizer`。
- `shouldReportPartialResults = true`：录音时持续更新 `latestText`。
- 停止录音时：`endAudio()`，等待 `isFinal` 结果；若短时间未收到 final，则用最新 partial 作为 best-effort。

### 粘贴插入策略

- 记录 `PasteboardSnapshot`（已有实现），写入剪贴板为转写文本。
- 合成 `Cmd+V`（`CGEvent`）发送到系统。
- 延迟 150~300ms 后 best-effort 恢复剪贴板（避免目标 app 还没读取完剪贴板）。

## 文件改动清单

新增（建议路径）：
- `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/Speech/SpeechTranscriber.swift`
- `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/TextInsertion/PasteTextInserter.swift`

修改：
- `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/AppDelegate.swift`

可选（如需要设置项/开关）：
- `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/AIVoiceKeyboardApp.swift`（SettingsView 增加 STT 引擎选择占位）

## 实现步骤

1) 权限与状态机
- Insert 开始前检查：`Microphone` 与 `Speech Recognition` 权限。
- 权限不足：进入 `.error`，菜单栏显示可执行提示（并保留 Settings 入口）。

2) Apple Speech 转写器
- 实现 `SpeechTranscriber`：`start()` / `stop(timeoutSeconds)`。
- stop 时的 timeout 策略：优先返回 final；超时返回 latest partial；都没有则抛错。

3) Text inserter（Paste）
- 实现 `PasteTextInserter.insert(text:)`：snapshot -> set clipboard -> send Cmd+V -> restore clipboard（delay）。
- 对空字符串直接 no-op 或抛错（选择一种并在 UI 中友好提示）。

4) 接入热键（Insert only）
- 在 `toggleInsertRecording`：
  - Start：进入 `.recordingInsert` + 启动 transcriber。
  - Stop：进入 `.processing` -> stop transcriber -> inserter -> append history -> 回到 `.idle`。

5) History 行为
- 将最终插入文本写入 History（mode: insert）。
- 保留 debug placeholder 入口（仅 DEBUG 下）但不影响主流程。

## 风险与边界情况

- 用户未授权 Speech Recognition：Apple Speech 无法工作；需清晰提示并引导打开系统设置。
- `Cmd+V` 注入在某些环境不生效（比如安全策略/焦点问题）：需要错误提示；后续可 fallback（例如把文本放剪贴板并提示用户手动粘贴）。
- 粘贴后剪贴板恢复时机：恢复过早可能导致目标 app 粘贴失败；过晚会短暂影响用户剪贴板。建议先 200ms，后续按反馈微调。
- 语言/locale：默认 `.current`；后续可以加设置项。

## 测试策略

- 由于本机可能没有完整 Xcode 环境：
  - 以 CI 的 `macos_app_build` 为编译验证。
  - 本地用 Xcode 手动跑：在 Notes/Slack/浏览器输入框测试一次完整闭环。

建议最小手动验收清单：
- 首次运行：授权 Mic + Speech。
- 在任意文本框：⌥Space 录音说一句话 -> 停止 -> 文本被插入。
- 插入后：剪贴板内容未丢（或仅短暂变化）。
- 权限拒绝：菜单栏显示可操作提示。

## 交付物

- PR：实现上述闭环，`Closes #24`。
- CI：必绿。
- Review：逐条处理与回复，等待二次 review 通过后再合入。
