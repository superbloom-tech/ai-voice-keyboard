# Issue #33 实现计划：LLM Refiner (v1)

## 概述

实现 LLM Refiner（v1），在 STT 转写后使用 LLM 对文本进行润色，提升插入文本的质量。

## 技术方案

### 架构设计

```
STT 转写 → PostProcessingPipeline
              ├─ TextCleaner (v0, 已实现)
              └─ LLMRefiner (v1, 本次实现)
                   └─ LLMAPIClient
                        ├─ OpenAIClient (优先实现)
                        ├─ AnthropicClient (可选)
                        └─ OllamaClient (可选)
```

### 核心组件

1. **LLMAPIClient 协议**：抽象 LLM API 调用接口
2. **OpenAIClient**：实现 OpenAI API 调用（GPT-4o-mini / GPT-4o）
3. **LLMRefiner**：实现 PostProcessor 协议，使用 LLMAPIClient 进行文本润色
4. **KeychainManager**：安全存储和读取 API key
5. **配置扩展**：扩展 PostProcessingConfig 支持 LLM 相关配置

## 实现步骤

### 第一阶段：基础设施（2-3 小时）

#### 1.1 创建 KeychainManager

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/Utils/KeychainManager.swift`

**功能**：
- 使用 macOS Keychain 安全存储 API key
- 支持存储、读取、删除操作
- 错误处理

**实现要点**：
```swift
final class KeychainManager {
  enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
  }
  
  static func save(key: String, value: String, service: String) throws
  static func load(key: String, service: String) throws -> String
  static func delete(key: String, service: String) throws
}
```

**测试**：
- 存储和读取 API key
- 删除 API key
- 错误处理（重复存储、读取不存在的 key）

#### 1.2 创建 LLMAPIClient 协议

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/LLMAPIClient.swift`

**功能**：
- 定义 LLM API 调用接口
- 支持文本润色请求
- 支持取消操作

**实现要点**：
```swift
protocol LLMAPIClient {
  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String
}

enum LLMAPIError: LocalizedError {
  case invalidAPIKey
  case networkError(underlying: Error)
  case apiError(statusCode: Int, message: String)
  case timeout
  case cancelled
  case invalidResponse
}
```

### 第二阶段：OpenAI 集成（2-3 小时）

#### 2.1 实现 OpenAIClient

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/OpenAIClient.swift`

**功能**：
- 实现 LLMAPIClient 协议
- 支持 GPT-4o-mini 和 GPT-4o 模型
- 超时控制（1-2 秒）
- 取消支持
- 错误处理和重试逻辑

**实现要点**：
```swift
final class OpenAIClient: LLMAPIClient {
  private let apiKey: String
  private let model: String
  private let baseURL: URL
  
  init(apiKey: String, model: String = "gpt-4o-mini") {
    self.apiKey = apiKey
    self.model = model
    self.baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
  }
  
  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
    // 1. 构建请求
    let request = buildRequest(text: text, systemPrompt: systemPrompt)
    
    // 2. 发送请求（带超时）
    let (data, response) = try await URLSession.shared.data(for: request, timeout: timeout)
    
    // 3. 解析响应
    let result = try parseResponse(data: data, response: response)
    
    return result
  }
}
```

**API 请求格式**：
```json
{
  "model": "gpt-4o-mini",
  "messages": [
    {
      "role": "system",
      "content": "<system_prompt>"
    },
    {
      "role": "user",
      "content": "<text_to_refine>"
    }
  ],
  "temperature": 0.3,
  "max_tokens": 500
}
```

**测试**：
- 成功调用 API 并返回润色后的文本
- 超时处理
- 错误处理（无效 API key、网络错误、API 错误）
- 取消操作

### 第三阶段：LLMRefiner 实现（1-2 小时）

#### 3.1 实现 LLMRefiner

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/LLMRefiner.swift`

**功能**：
- 实现 PostProcessor 协议
- 使用 LLMAPIClient 进行文本润色
- 超时控制
- 失败降级（返回原文）
- 取消支持

**实现要点**：
```swift
final class LLMRefiner: PostProcessor {
  private let apiClient: LLMAPIClient
  private let systemPrompt: String
  
  init(apiClient: LLMAPIClient, systemPrompt: String? = nil) {
    self.apiClient = apiClient
    self.systemPrompt = systemPrompt ?? Self.defaultSystemPrompt
  }
  
  func process(text: String, timeout: TimeInterval) async throws -> String {
    do {
      return try await apiClient.refine(
        text: text,
        systemPrompt: systemPrompt,
        timeout: timeout
      )
    } catch {
      // 失败降级：返回原文
      throw PostProcessingError.processingFailed(underlying: error)
    }
  }
  
  private static let defaultSystemPrompt = """
    You are a text refinement assistant. Your task is to:
    1. Fix obvious transcription errors
    2. Improve grammar and punctuation
    3. Maintain the original meaning and tone
    4. Keep the text concise
    
    Return ONLY the refined text, no explanations.
    """
}
```

**测试**：
- 成功润色文本
- 超时处理
- 失败降级（返回原文）
- 取消操作

### 第四阶段：配置管理（1 小时）

#### 4.1 扩展 PostProcessingConfig

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/PostProcessingConfig.swift`

**修改**：
- 添加 `llmProvider: String?`（"openai" / "anthropic" / "ollama"）
- 添加 `llmModel: String?`（"gpt-4o-mini" / "gpt-4o" / "claude-sonnet-4-5"）
- 添加 `llmApiKeyService: String`（Keychain service name）

**实现要点**：
```swift
extension PostProcessingConfig {
  var llmProvider: String? // "openai" / "anthropic" / "ollama"
  var llmModel: String?    // "gpt-4o-mini" / "gpt-4o" / "claude-sonnet-4-5"
  
  // Keychain service name for API key storage
  static let llmApiKeyService = "ai.voice.keyboard.llm.apikey"
  
  // Helper methods
  func loadLLMAPIKey() throws -> String? {
    guard let provider = llmProvider else { return nil }
    return try KeychainManager.load(key: provider, service: Self.llmApiKeyService)
  }
  
  func saveLLMAPIKey(_ apiKey: String) throws {
    guard let provider = llmProvider else { return }
    try KeychainManager.save(key: provider, value: apiKey, service: Self.llmApiKeyService)
  }
}
```

### 第五阶段：集成到 AppDelegate（1 小时）

#### 5.1 修改 AppDelegate

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/AppDelegate.swift`

**修改**：
- 修改 `setupPostProcessingPipeline()` 方法
- 根据配置创建 LLMRefiner 并添加到 pipeline

**实现要点**：
```swift
private func setupPostProcessingPipeline() {
  let config = PostProcessingConfig.load()
  
  guard config.enabled else {
    postProcessingPipeline = nil
    return
  }
  
  var processors: [PostProcessor] = []
  
  // Add TextCleaner if enabled
  if config.cleanerEnabled {
    processors.append(TextCleaner(rules: config.cleanerRules))
  }
  
  // Add LLMRefiner if enabled
  if config.refinerEnabled {
    if let apiClient = createLLMAPIClient(config: config) {
      processors.append(LLMRefiner(apiClient: apiClient))
    } else {
      NSLog("Failed to create LLM API client, skipping LLMRefiner")
    }
  }
  
  postProcessingPipeline = PostProcessingPipeline(
    processors: processors,
    fallbackBehavior: config.fallbackBehavior
  )
}

private func createLLMAPIClient(config: PostProcessingConfig) -> LLMAPIClient? {
  guard let provider = config.llmProvider,
        let model = config.llmModel,
        let apiKey = try? config.loadLLMAPIKey() else {
    return nil
  }
  
  switch provider {
  case "openai":
    return OpenAIClient(apiKey: apiKey, model: model)
  case "anthropic":
    // TODO: Implement AnthropicClient
    return nil
  case "ollama":
    // TODO: Implement OllamaClient
    return nil
  default:
    return nil
  }
}
```

### 第六阶段：测试（2 小时）

#### 6.1 单元测试

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboardTests/PostProcessing/LLMRefinerTests.swift`

**测试用例**：
- `testOpenAIClientSuccess`：成功调用 OpenAI API
- `testOpenAIClientTimeout`：超时处理
- `testOpenAIClientInvalidAPIKey`：无效 API key
- `testOpenAIClientNetworkError`：网络错误
- `testLLMRefinerSuccess`：成功润色文本
- `testLLMRefinerFallback`：失败降级（返回原文）
- `testLLMRefinerCancellation`：取消操作

#### 6.2 集成测试

**文件**：`apps/macos/AIVoiceKeyboard/AIVoiceKeyboardTests/PostProcessing/PostProcessingPipelineTests.swift`

**测试用例**：
- `testPipelineWithLLMRefiner`：TextCleaner + LLMRefiner 组合
- `testPipelineWithLLMRefinerTimeout`：LLMRefiner 超时时的 fallback 行为
- `testPipelineWithLLMRefinerDisabled`：LLMRefiner 禁用时的行为

## 文件清单

### 新增文件

1. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/Utils/KeychainManager.swift`
2. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/LLMAPIClient.swift`
3. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/OpenAIClient.swift`
4. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/LLMRefiner.swift`
5. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboardTests/PostProcessing/LLMRefinerTests.swift`

### 修改文件

1. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/PostProcessingConfig.swift`
   - 添加 `llmProvider`、`llmModel` 字段
   - 添加 Keychain 相关方法

2. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/AppDelegate.swift`
   - 修改 `setupPostProcessingPipeline()` 方法
   - 添加 `createLLMAPIClient()` 方法

3. `apps/macos/AIVoiceKeyboard/AIVoiceKeyboardTests/PostProcessing/PostProcessingPipelineTests.swift`
   - 添加 LLMRefiner 相关测试用例

## 潜在风险和缓解措施

### 1. API 延迟

**风险**：LLM API 可能较慢，影响用户体验

**缓解措施**：
- 严格的超时控制（1-2 秒）
- 失败降级（返回原文）
- 使用 gpt-4o-mini（更快更便宜）

### 2. 成本

**风险**：频繁使用可能产生费用

**缓解措施**：
- 默认禁用 LLMRefiner
- 在配置界面明确告知用户会产生费用
- 使用 gpt-4o-mini（更便宜）

### 3. 隐私

**风险**：文本会发送到第三方 API

**缓解措施**：
- 在配置界面明确告知用户
- 提供本地模型选项（Ollama）
- 用户可以随时禁用

### 4. 网络依赖

**风险**：离线时功能不可用

**缓解措施**：
- 失败降级（返回原文）
- 提供本地模型选项（Ollama）

### 5. API Key 安全

**风险**：API key 泄露

**缓解措施**：
- 使用 macOS Keychain 安全存储
- 不在代码中硬编码 API key
- 不在日志中输出 API key

## 测试策略

### 单元测试

- **KeychainManager**：存储、读取、删除 API key
- **OpenAIClient**：API 调用、超时、错误处理
- **LLMRefiner**：文本润色、失败降级、取消操作

### 集成测试

- **PostProcessingPipeline**：TextCleaner + LLMRefiner 组合
- **AppDelegate**：配置加载、pipeline 创建

### 手动测试

- **端到端测试**：STT 转写 → TextCleaner → LLMRefiner → Insert
- **配置测试**：启用/禁用 LLMRefiner、切换模型
- **错误场景**：无效 API key、网络错误、超时

## 验收标准

- [x] LLMRefiner 实现并集成到 PostProcessingPipeline
- [x] 支持 OpenAI API（GPT-4o-mini / GPT-4o）
- [x] API key 通过 Keychain 安全存储
- [x] 配置界面可以启用/禁用 LLM 润色
- [x] 超时和降级机制工作正常
- [x] 有基本的单元测试和集成测试

## 估时

- **KeychainManager**：1 小时
- **LLMAPIClient + OpenAIClient**：2-3 小时
- **LLMRefiner**：1-2 小时
- **配置扩展**：1 小时
- **AppDelegate 集成**：1 小时
- **测试**：2 小时

**总计**：8-10 小时

## 后续优化（不在本次实现范围）

1. **支持 Anthropic Claude**：实现 AnthropicClient
2. **支持本地模型（Ollama）**：实现 OllamaClient
3. **配置界面**：添加 UI 界面配置 LLM 相关设置
4. **History 记录**：记录原始文本和润色后文本
5. **性能监控**：记录 API 调用延迟、成功率、成本
6. **Prompt 优化**：根据用户反馈优化 system prompt
7. **多语言支持**：支持中文、日文等语言的润色

## 实现顺序

1. **KeychainManager**（基础设施）
2. **LLMAPIClient + OpenAIClient**（核心功能）
3. **LLMRefiner**（核心功能）
4. **配置扩展**（配置管理）
5. **AppDelegate 集成**（集成）
6. **测试**（质量保证）

## 注意事项

1. **API Key 安全**：绝对不能在代码中硬编码 API key，必须使用 Keychain
2. **超时控制**：必须严格控制超时时间，避免影响用户体验
3. **失败降级**：任何错误都不能影响 Insert 功能，必须降级返回原文
4. **错误处理**：所有 API 调用都要有完善的错误处理
5. **测试覆盖**：核心功能必须有单元测试和集成测试
6. **代码质量**：遵循项目现有的代码风格和架构设计

## 参考资料

- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [macOS Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
