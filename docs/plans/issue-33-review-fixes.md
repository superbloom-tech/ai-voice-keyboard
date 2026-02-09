# Issue #33 ReviewerB 审查意见修复计划

## 概述

本文档是针对 PR #34 的 ReviewerB 审查意见的修复计划。ReviewerB 指出了多个需要修复的问题，包括配置未生效、错误处理不完整、缺少测试等。本计划将这些问题分为三个优先级，并提供详细的修复方案。

## 问题分类

### P0（必须修复，阻塞合并）

1. **refinerTimeout 配置未生效**
   - 位置：`AppDelegate.swift:513`
   - 问题：硬编码 `timeout: 5.0`，`PostProcessingConfig.refinerTimeout` 没有被使用
   - 影响：用户配置的超时时间不生效

2. **Pipeline 超时机制不合理**
   - 位置：`PostProcessor.swift:70`
   - 问题：所有 processor 共享同一个 timeout
   - 影响：TextCleaner（本地，毫秒级）和 LLMRefiner（网络，秒级）需求不同

3. **错误映射不完整**
   - 位置：`OpenAIClient.swift:19`, `LLMAPIClient.swift:52`
   - 问题：
     - `OpenAIClient` 没有将网络错误映射到 `LLMAPIError`
     - HTTP 401/403 应该映射为 `invalidAPIKey`
     - `CancellationError` 没有被正确映射
   - 影响：上层只能拿到杂乱的底层错误，难以处理

4. **超时实现有风险**
   - 位置：`LLMAPIClient.swift:52`
   - 问题：对负数或异常大的 timeout 没有校验
   - 影响：可能导致崩溃或溢出

5. **缺少测试**
   - 问题：没有单元测试和集成测试
   - 影响：代码质量无法保证，回归风险高

### P1（重要优化，应该修复）

1. **Provider 使用字符串**
   - 位置：`AppDelegate.swift:468`, `PostProcessingConfig.swift:11`
   - 问题：`refinerProvider/refinerModel` 使用字符串容易出错
   - 建议：用 enum 替代

2. **Keychain 实现细节**
   - 位置：`KeychainManager.swift:32`
   - 问题：
     - 缺少 `kSecAttrAccessible` 设置
     - `save` 方法的 `duplicateItem` 分支不可达
     - 错误日志不够详细
   - 影响：安全性和可维护性

### P2（优化建议，可以后续优化）

1. **响应解析脆弱**
   - 位置：`OpenAIClient.swift:68`
   - 问题：使用弱类型字典解析，应该改为 Codable
   - 影响：API 结构变化时容易出错

2. **缺少输入长度限制**
   - 位置：`OpenAIClient.swift:19`
   - 问题：systemPrompt/text 可能很长，需要限制
   - 影响：token 成本和延迟风险

3. **隐私提示**
   - 问题：需要明确告知用户文本会发送到第三方服务
   - 影响：隐私合规

## 修复方案

### 阶段 1：P0 问题修复（必须完成）

#### 1.1 修复 refinerTimeout 配置未生效

**目标**：让 `PostProcessingConfig.refinerTimeout` 真正生效

**方案**：

1. **修改 `AppDelegate.swift`**：
   - 在 `stopTranscriptionAndInsert()` 方法中，将硬编码的 `timeout: 5.0` 替换为从配置读取
   - 计算 pipeline 总超时时间：`cleanerTimeout + refinerTimeout`（或使用最大值）

2. **修改 `PostProcessingConfig.swift`**：
   - 添加 `cleanerTimeout: TimeInterval` 字段（默认 1.0 秒）
   - 添加计算属性 `totalTimeout: TimeInterval`，返回所有启用的 processor 的超时时间之和

3. **修改 `PostProcessor.swift`**：
   - 选项 A（简单）：保持当前接口，但在文档中说明 timeout 是"单个 processor 的最大超时"
   - 选项 B（理想）：修改 `PostProcessor` 协议，不接受 timeout 参数，而是让每个 processor 自己管理超时
   - **推荐选项 A**：改动最小，且当前架构下已经可以工作

**实现步骤**：

```swift
// PostProcessingConfig.swift
struct PostProcessingConfig: Codable {
  // ... existing fields ...
  var cleanerTimeout: TimeInterval  // 新增
  
  var totalTimeout: TimeInterval {
    var total: TimeInterval = 0
    if cleanerEnabled {
      total += cleanerTimeout
    }
    if refinerEnabled {
      total += refinerTimeout
    }
    return total
  }
  
  static let `default` = PostProcessingConfig(
    // ... existing params ...
    cleanerTimeout: 1.0,  // 新增
    // ...
  )
}

// AppDelegate.swift
private func stopTranscriptionAndInsert() async throws -> (finalText: String, rawText: String?, processingResult: ProcessingResult?) {
  // ...
  let config = PostProcessingConfig.load()
  
  if let pipeline = postProcessingPipeline {
    do {
      // 使用配置的超时时间，而不是硬编码
      let timeout = config.refinerEnabled ? config.refinerTimeout : config.cleanerTimeout
      let result = try await pipeline.process(text: rawText, timeout: timeout)
      finalText = result.finalText
      processingResult = result
    } catch {
      // ...
    }
  }
  // ...
}
```

#### 1.2 完善错误映射

**目标**：确保所有错误都被正确映射到 `LLMAPIError`

**方案**：

1. **修改 `OpenAIClient.swift`**：
   - 在 `refine()` 方法中添加 do-catch 块
   - 捕获 `URLError` 并映射为 `.networkError(underlying:)`
   - 捕获 `CancellationError` 并映射为 `.cancelled`
   - 在 `parseResponse()` 中，对 HTTP 401/403 映射为 `.invalidAPIKey`

2. **修改 `LLMAPIClient.swift`**：
   - 在 `data(for:timeout:)` 方法中添加 timeout 校验
   - 捕获 `CancellationError` 并映射为 `.cancelled`

**实现步骤**：

```swift
// OpenAIClient.swift
func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
  do {
    // Build request
    let request = try buildRequest(text: text, systemPrompt: systemPrompt)
    
    // Send request with timeout
    let (data, response) = try await URLSession.shared.data(for: request, timeout: timeout)
    
    // Parse response
    return try parseResponse(data: data, response: response)
  } catch let error as LLMAPIError {
    // Already an LLMAPIError, just rethrow
    throw error
  } catch is CancellationError {
    // Task was cancelled
    throw LLMAPIError.cancelled
  } catch let error as URLError {
    // Network error
    if error.code == .timedOut {
      throw LLMAPIError.timeout
    }
    throw LLMAPIError.networkError(underlying: error)
  } catch {
    // Other errors (e.g., JSON decoding)
    throw LLMAPIError.invalidResponse
  }
}

private func parseResponse(data: Data, response: URLResponse) throws -> String {
  // Check HTTP status code
  guard let httpResponse = response as? HTTPURLResponse else {
    throw LLMAPIError.invalidResponse
  }
  
  // Map specific status codes
  switch httpResponse.statusCode {
  case 200...299:
    // Success, continue parsing
    break
  case 401, 403:
    // Invalid API key
    let errorMessage = try? parseErrorMessage(from: data)
    throw LLMAPIError.invalidAPIKey
  default:
    // Other API errors
    let errorMessage = try? parseErrorMessage(from: data)
    throw LLMAPIError.apiError(
      statusCode: httpResponse.statusCode,
      message: errorMessage ?? "Unknown error"
    )
  }
  
  // Parse JSON response
  // ... existing parsing logic ...
}

// LLMAPIClient.swift
extension URLSession {
  func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
    // Validate timeout
    guard timeout > 0 else {
      throw LLMAPIError.timeout
    }
    
    try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
      // Add the actual request task
      group.addTask {
        do {
          return try await self.data(for: request)
        } catch is CancellationError {
          throw LLMAPIError.cancelled
        } catch {
          throw error
        }
      }
      
      // Add the timeout task
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw LLMAPIError.timeout
      }
      
      // Wait for the first task to complete
      guard let result = try await group.next() else {
        throw LLMAPIError.cancelled
      }
      
      // Cancel the other task
      group.cancelAll()
      
      return result
    }
  }
}
```

#### 1.3 添加测试

**目标**：为核心功能添加单元测试和集成测试

**方案**：

1. **创建测试文件**：
   - `LLMRefinerTests.swift`：测试 LLMRefiner 的错误映射
   - `OpenAIClientTests.swift`：测试 OpenAIClient 的响应解析和错误映射
   - `KeychainManagerTests.swift`：测试 KeychainManager 的存取删除操作
   - `PostProcessingPipelineTests.swift`：测试 Pipeline 的集成行为

2. **Mock LLMAPIClient**：
   - 创建 `MockLLMAPIClient` 用于测试
   - 支持模拟 success/timeout/cancelled/error 等场景

3. **测试覆盖**：
   - LLMRefiner：success → finalText, timeout → PostProcessingError.timeout, cancelled → PostProcessingError.cancelled, other → PostProcessingError.processingFailed
   - OpenAIClient：响应解析、HTTP 401/403 → invalidAPIKey、网络错误 → networkError、超时 → timeout
   - KeychainManager：save/load/delete/exists
   - Pipeline：多个 processor 的组合、fallback 行为

**实现步骤**：

```swift
// LLMRefinerTests.swift
import XCTest
@testable import AIVoiceKeyboard

class LLMRefinerTests: XCTestCase {
  func testRefineSuccess() async throws {
    let mockClient = MockLLMAPIClient(result: .success("refined text"))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    let result = try await refiner.process(text: "original text", timeout: 2.0)
    
    XCTAssertEqual(result, "refined text")
  }
  
  func testRefineTimeout() async {
    let mockClient = MockLLMAPIClient(result: .failure(.timeout))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw timeout error")
    } catch let error as PostProcessingError {
      if case .timeout = error {
        // Success
      } else {
        XCTFail("Should throw PostProcessingError.timeout, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testRefineCancelled() async {
    let mockClient = MockLLMAPIClient(result: .failure(.cancelled))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw cancelled error")
    } catch let error as PostProcessingError {
      if case .cancelled = error {
        // Success
      } else {
        XCTFail("Should throw PostProcessingError.cancelled, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testRefineOtherError() async {
    let mockClient = MockLLMAPIClient(result: .failure(.invalidResponse))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw processing failed error")
    } catch let error as PostProcessingError {
      if case .processingFailed = error {
        // Success
      } else {
        XCTFail("Should throw PostProcessingError.processingFailed, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
}

// MockLLMAPIClient.swift
class MockLLMAPIClient: LLMAPIClient {
  let result: Result<String, LLMAPIError>
  
  init(result: Result<String, LLMAPIError>) {
    self.result = result
  }
  
  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
    switch result {
    case .success(let refined):
      return refined
    case .failure(let error):
      throw error
    }
  }
}
```

### 阶段 2：P1 问题修复（重要优化）

#### 2.1 Provider 使用 enum

**目标**：用 enum 替代字符串 provider，减少配置错误

**方案**：

1. **创建 `LLMProvider` enum**：
   - 定义 `openai`, `anthropic`, `ollama` 等 case
   - 实现 `Codable` 协议，支持字符串映射
   - 支持大小写不敏感的解码

2. **修改 `PostProcessingConfig`**：
   - 将 `refinerProvider: String?` 改为 `refinerProvider: LLMProvider?`
   - 保持向后兼容（旧版本的字符串配置可以正确解码）

3. **修改 `AppDelegate`**：
   - 使用 enum switch 替代字符串 switch

**实现步骤**：

```swift
// LLMProvider.swift
enum LLMProvider: String, Codable, CaseIterable {
  case openai = "openai"
  case anthropic = "anthropic"
  case ollama = "ollama"
  
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    
    // Case-insensitive matching
    guard let provider = LLMProvider.allCases.first(where: { $0.rawValue.lowercased() == rawValue.lowercased() }) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid LLM provider: \(rawValue)"
      )
    }
    
    self = provider
  }
}

// PostProcessingConfig.swift
struct PostProcessingConfig: Codable {
  // ... existing fields ...
  var refinerProvider: LLMProvider?  // 改为 enum
  // ...
}

// AppDelegate.swift
private func createLLMAPIClient(config: PostProcessingConfig) -> LLMAPIClient? {
  guard let provider = config.refinerProvider,
        let model = config.refinerModel,
        let apiKey = try? config.loadLLMAPIKey() else {
    NSLog("Failed to create LLM API client: missing provider, model, or API key")
    return nil
  }
  
  switch provider {
  case .openai:
    return OpenAIClient(apiKey: apiKey, model: model)
  case .anthropic:
    // TODO: Implement AnthropicClient
    NSLog("Anthropic client not implemented yet")
    return nil
  case .ollama:
    // TODO: Implement OllamaClient
    NSLog("Ollama client not implemented yet")
    return nil
  }
}
```

#### 2.2 Keychain 实现优化

**目标**：改进 Keychain 的安全性和可维护性

**方案**：

1. **添加 `kSecAttrAccessible` 设置**：
   - 使用 `kSecAttrAccessibleAfterFirstUnlock`（平衡安全性和可用性）
   - 在文档中说明不同设备不共享

2. **简化 save/update 逻辑**：
   - 移除不可达的 `duplicateItem` 分支
   - 或者改为"先 add，遇 duplicate 再 update"的逻辑

3. **改进错误日志**：
   - 在 `AppDelegate` 中区分"缺 key"与"Keychain 操作失败"

**实现步骤**：

```swift
// KeychainManager.swift
static func save(key: String, value: String, service: String) throws {
  guard let data = value.data(using: .utf8) else {
    throw KeychainError.invalidData
  }
  
  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: key,
    kSecValueData as String: data,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock  // 新增
  ]
  
  // Try to add first
  var status = SecItemAdd(query as CFDictionary, nil)
  
  if status == errSecDuplicateItem {
    // Item exists, update it
    let updateQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    
    let updateAttributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]
    
    status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
  }
  
  guard status == errSecSuccess else {
    throw KeychainError.unexpectedStatus(status)
  }
}

// AppDelegate.swift
private func createLLMAPIClient(config: PostProcessingConfig) -> LLMAPIClient? {
  guard let provider = config.refinerProvider,
        let model = config.refinerModel else {
    NSLog("Failed to create LLM API client: missing provider or model")
    return nil
  }
  
  // Try to load API key
  let apiKey: String
  do {
    guard let key = try config.loadLLMAPIKey() else {
      NSLog("Failed to create LLM API client: API key not found in Keychain")
      return nil
    }
    apiKey = key
  } catch {
    NSLog("Failed to create LLM API client: Keychain error - \(error.localizedDescription)")
    return nil
  }
  
  // ... rest of the method ...
}
```

### 阶段 3：P2 问题优化（可选，后续 PR）

#### 3.1 响应解析改为 Codable

**目标**：使用 Codable 定义响应结构，提高健壮性

**方案**：

1. **定义响应结构**：
   - `OpenAIResponse`
   - `OpenAIChoice`
   - `OpenAIMessage`

2. **修改 `parseResponse()`**：
   - 使用 `JSONDecoder` 解码
   - 在错误时附带截断的 body

**实现步骤**：

```swift
// OpenAIClient.swift

// Response structures
struct OpenAIResponse: Codable {
  let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
  let message: OpenAIMessage
}

struct OpenAIMessage: Codable {
  let content: String
}

struct OpenAIErrorResponse: Codable {
  let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
  let message: String
}

private func parseResponse(data: Data, response: URLResponse) throws -> String {
  // Check HTTP status code
  guard let httpResponse = response as? HTTPURLResponse else {
    throw LLMAPIError.invalidResponse
  }
  
  // Map specific status codes
  switch httpResponse.statusCode {
  case 200...299:
    // Success, parse response
    do {
      let decoder = JSONDecoder()
      let openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
      
      guard let content = openAIResponse.choices.first?.message.content else {
        throw LLMAPIError.emptyResponse
      }
      
      return content.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      // Attach truncated body for debugging
      let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
      throw LLMAPIError.invalidResponse
    }
    
  case 401, 403:
    // Invalid API key
    throw LLMAPIError.invalidAPIKey
    
  default:
    // Other API errors
    let errorMessage: String
    if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
      errorMessage = errorResponse.error.message
    } else {
      errorMessage = "Unknown error"
    }
    throw LLMAPIError.apiError(
      statusCode: httpResponse.statusCode,
      message: errorMessage
    )
  }
}
```

#### 3.2 输入长度限制

**目标**：限制 systemPrompt 和 text 的长度，控制成本和延迟

**方案**：

1. **定义最大长度**：
   - `maxSystemPromptLength = 1000`
   - `maxTextLength = 5000`

2. **在 `OpenAIClient.refine()` 中截断**：
   - 如果超过长度，截断并添加省略号

**实现步骤**：

```swift
// OpenAIClient.swift
private let maxSystemPromptLength = 1000
private let maxTextLength = 5000

func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
  // Truncate inputs if too long
  let truncatedSystemPrompt = systemPrompt.count > maxSystemPromptLength
    ? String(systemPrompt.prefix(maxSystemPromptLength)) + "..."
    : systemPrompt
  
  let truncatedText = text.count > maxTextLength
    ? String(text.prefix(maxTextLength)) + "..."
    : text
  
  // Build request with truncated inputs
  let request = try buildRequest(text: truncatedText, systemPrompt: truncatedSystemPrompt)
  
  // ... rest of the method ...
}
```

#### 3.3 隐私提示

**目标**：明确告知用户文本会发送到第三方服务

**方案**：

1. **在配置界面添加提示**：
   - 当用户启用 LLM Refiner 时，显示警告对话框
   - 说明文本会发送到 OpenAI/Anthropic 等第三方服务

2. **在 README 中添加隐私说明**：
   - 说明 LLM Refiner 的工作原理
   - 提供隐私政策链接

**实现步骤**：

```swift
// SettingsView.swift (假设有配置界面)
Toggle("Enable LLM Refiner", isOn: $config.refinerEnabled)
  .onChange(of: config.refinerEnabled) { newValue in
    if newValue {
      showPrivacyAlert = true
    }
  }
  .alert("Privacy Notice", isPresented: $showPrivacyAlert) {
    Button("Cancel", role: .cancel) {
      config.refinerEnabled = false
    }
    Button("I Understand") {
      // User acknowledged
    }
  } message: {
    Text("When LLM Refiner is enabled, your transcribed text will be sent to third-party AI services (OpenAI, Anthropic, etc.) for refinement. Please review our privacy policy for more information.")
  }
```

## 实施顺序

1. **阶段 1（P0）**：必须在合并前完成
   - 1.1 修复 refinerTimeout 配置未生效
   - 1.2 完善错误映射
   - 1.3 添加测试

2. **阶段 2（P1）**：应该在合并前完成
   - 2.1 Provider 使用 enum
   - 2.2 Keychain 实现优化

3. **阶段 3（P2）**：可以在后续 PR 中完成
   - 3.1 响应解析改为 Codable
   - 3.2 输入长度限制
   - 3.3 隐私提示

## 估时

- **阶段 1（P0）**：4-5 小时
  - 1.1 refinerTimeout：1 小时
  - 1.2 错误映射：1.5 小时
  - 1.3 测试：1.5-2 小时

- **阶段 2（P1）**：2-3 小时
  - 2.1 Provider enum：1 小时
  - 2.2 Keychain 优化：1-2 小时

- **阶段 3（P2）**：3-4 小时
  - 3.1 Codable：1.5 小时
  - 3.2 输入限制：0.5 小时
  - 3.3 隐私提示：1-2 小时

**总计**：9-12 小时（如果全部完成）

## 验收标准

### 阶段 1（P0）

- [ ] `PostProcessingConfig.refinerTimeout` 真正生效
- [ ] 所有错误都被正确映射到 `LLMAPIError`
- [ ] HTTP 401/403 映射为 `invalidAPIKey`
- [ ] `CancellationError` 映射为 `.cancelled`
- [ ] 超时校验正常工作
- [ ] 至少有 `LLMRefinerTests` 和 `OpenAIClientTests`
- [ ] 所有测试通过

### 阶段 2（P1）

- [ ] `refinerProvider` 使用 enum
- [ ] 向后兼容旧版本的字符串配置
- [ ] Keychain 设置 `kSecAttrAccessible`
- [ ] `save` 方法逻辑简化
- [ ] 错误日志区分"缺 key"与"Keychain 操作失败"

### 阶段 3（P2）

- [ ] 响应解析使用 Codable
- [ ] 输入长度限制生效
- [ ] 隐私提示在配置界面显示

## 注意事项

1. **向后兼容**：所有配置修改都要保持向后兼容，旧版本的配置应该能正确加载
2. **测试覆盖**：每个修复都应该有对应的测试用例
3. **错误处理**：所有错误都应该有清晰的错误信息，便于调试
4. **文档更新**：修改后需要更新相关文档（README、注释等）
5. **CI 通过**：所有修改都要确保 CI 通过

## 参考

- ReviewerB 审查报告：PR #34 comments
- 原始实现计划：`docs/plans/issue-33-plan.md`
- DEVELOPMENT.md：开发工作流规范
