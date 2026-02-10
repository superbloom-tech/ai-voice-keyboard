# AI Voice Keyboard

AI 驱动的语音输入工具（macOS 优先），以 **低时延** 为核心：语音转文字 + 轻量润色；并支持“选中文本后用语音下编辑指令”的改写工作流。

## Status

Pre-alpha（仓库初始化中）。

## MVP（v0.1）范围

- 菜单栏 App + 全局快捷键
- 两个模式（两个快捷键）：
  - Insert（语音输入）：录音 -> STT -> 轻量润色 -> 写入光标位置
  - Edit（语音编辑）：选区 -> 录音说编辑指令 -> 生成改写稿 -> 预览对比 -> 确认替换
- Provider 可配置：
  - STT：Apple Speech（默认）/ Whisper（本地 CLI）/ Remote STT（OpenAI-compatible）
  - LLM：用户自配 API（多 Provider 适配）
- 历史记录：仅记录本 App 产生的识别/改写历史；并在我们临时覆盖剪贴板时保存“覆盖前剪贴板快照”，防止丢剪贴板
- 菜单栏图标随状态变化（Idle/Recording/Processing/Preview/Error）

## Repo 结构（约定）

- `docs/plans/`：PRD / 设计 / 实现计划
- `docs/process/`：协作流程与规范
- `packages/VoiceKeyboardCore/`：可复用 Core（协议、文本处理、Provider 适配层）
- `apps/macos/`：macOS App（后续添加）

## Development

运行 Core 单测：

```bash
cd packages/VoiceKeyboardCore
swift test
```

## STT Providers

本项目支持可切换的 STT Provider（在 macOS App 的 Settings 中配置）：

### 1) Apple Speech（默认）
- 纯本地、低延迟
- 需要 macOS 的 Speech Recognition 权限

### 2) Whisper Local (CLI)
- 依赖本机安装 `openai-whisper` 提供的 `whisper` 命令

安装：
```bash
brew install openai-whisper
whisper --help
```

Settings 参数说明：
- Executable Path：可留空（默认会尝试探测常见 Homebrew 路径）
- Model：例如 `turbo` / `base` / `small`
- Language：可留空（自动识别），或填 `en` / `zh` 等
- Timeout：首次运行可能下载模型文件，建议适当调大

### 3) Remote STT (OpenAI-compatible)
- 配置 `Base URL` / `Model` / `API Key ID`
- API Key 明文仅存 Keychain；配置只保存 `API Key ID`
- Endpoint 会自动拼接：`{baseURL}/audio/transcriptions`

## Contributing

见 `docs/process/WORKFLOW.md`。
