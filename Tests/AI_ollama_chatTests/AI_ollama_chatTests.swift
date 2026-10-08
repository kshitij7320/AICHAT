import Testing
import Foundation
@testable import AI_ollama_chat

@Suite("Token Estimation Suite")
struct TokenEstimationTests {
    
    @Test("Empty text yields zero tokens")
    func testEmptyText() {
        #expect(ContextManager.estimateTokens(for: "") == 0)
    }
    
    @Test("Plain text estimation gives reasonable token counts")
    func testPlainTextTokens() {
        let text = "Hello world! This is a test of the token estimator."
        let tokens = ContextManager.estimateTokens(for: text)
        // ~51 chars -> roughly 12-16 tokens
        #expect(tokens >= 10 && tokens <= 20)
    }
    
    @Test("Code snippet with punctuation and symbols has higher density")
    func testCodeTokenEstimation() {
        let code = """
        func addNumbers(a: Int, b: Int) -> Int {
            return a + b
        }
        """
        let tokens = ContextManager.estimateTokens(for: code)
        #expect(tokens >= 15 && tokens <= 35)
    }
    
    @Test("Message DTO accounts for framing overhead")
    func testMessageFramingOverhead() {
        let message = OllamaMessageDTO(role: "user", content: "Hi")
        let textTokens = ContextManager.estimateTokens(for: "Hi")
        let messageTokens = ContextManager.estimateTokens(for: message)
        #expect(messageTokens == textTokens + 4)
    }
}

@Suite("Context Sliding Window Strategy Suite")
struct ContextSlidingWindowTests {
    
    @Test("System prompt is always placed at index 0")
    func testSystemPromptPlacement() {
        let manager = ContextManager()
        let config = ContextConfiguration(tokenBudget: 4096, reserveOutputTokens: 1024)
        
        let messages = [
            ChatMessage(role: "user", content: "What is Swift?"),
            ChatMessage(role: "assistant", content: "Swift is a powerful programming language.")
        ]
        
        let (payload, report) = manager.buildContext(
            systemPrompt: "You are an expert iOS developer.",
            messages: messages,
            configuration: config
        )
        
        #expect(payload.count == 3)
        #expect(payload.first?.role == "system")
        #expect(payload.first?.content == "You are an expert iOS developer.")
        #expect(payload[1].role == "user")
        #expect(payload[2].role == "assistant")
        #expect(report.retainedMessagesCount == 2)
        #expect(report.prunedMessagesCount == 0)
    }
    
    @Test("Pruning occurs when messages exceed small token budget")
    func testContextPruningOnSmallBudget() {
        let manager = ContextManager()
        // Very tight budget: 150 tokens total, 50 reserved for output = 100 available
        let config = ContextConfiguration(tokenBudget: 150, reserveOutputTokens: 50)
        
        var messages: [ChatMessage] = []
        for i in 1...15 {
            messages.append(ChatMessage(role: "user", content: "Question number \(i) with some longer additional text here."))
            messages.append(ChatMessage(role: "assistant", content: "Answer number \(i) explaining everything in great detail here."))
        }
        
        let (payload, report) = manager.buildContext(
            systemPrompt: "Root system instruction.",
            messages: messages,
            configuration: config
        )
        
        // System prompt should still be index 0
        #expect(payload.first?.role == "system")
        // Older messages should have been pruned
        #expect(report.prunedMessagesCount > 0)
        #expect(payload.count < messages.count + 1)
        // Most recent message should be present
        #expect(payload.last?.content == messages.last?.content)
    }
    
    @Test("Turn depth limits retained messages")
    func testTurnDepthLimiting() {
        let manager = ContextManager()
        let config = ContextConfiguration(tokenBudget: 16384, reserveOutputTokens: 1024, maxTurnDepth: 2)
        
        var messages: [ChatMessage] = []
        for i in 1...10 {
            messages.append(ChatMessage(role: "user", content: "Query \(i)"))
            messages.append(ChatMessage(role: "assistant", content: "Response \(i)"))
        }
        
        let (payload, report) = manager.buildContext(
            systemPrompt: nil,
            messages: messages,
            configuration: config
        )
        
        // With maxTurnDepth = 2 user turns, at most 4 conversational messages should be retained
        #expect(payload.count <= 4)
        #expect(report.prunedMessagesCount > 0)
    }
}

@Suite("Ollama API DTO & Serialization Suite")
struct OllamaAPITests {
    
    @Test("Tags response decodes correctly from JSON")
    func testTagsDecoding() throws {
        let json = """
        {
          "models": [
            {
              "name": "llama3.2:latest",
              "modified_at": "2026-10-01T12:00:00Z",
              "size": 4321000000,
              "digest": "sha256:abcdef",
              "details": {
                "format": "gguf",
                "family": "llama",
                "parameter_size": "3.2B",
                "quantization_level": "Q4_K_M"
              }
            }
          ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        #expect(response.models.count == 1)
        #expect(response.models.first?.name == "llama3.2:latest")
        #expect(response.models.first?.details?.parameterSize == "3.2B")
    }
    
    @Test("Streaming chunk decodes token and done flag")
    func testStreamChunkDecoding() throws {
        let chunkJSON = """
        {
          "model": "llama3.2",
          "created_at": "2026-10-08T06:00:00Z",
          "message": {
            "role": "assistant",
            "content": "Hello!"
          },
          "done": false
        }
        """
        
        let data = chunkJSON.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OllamaChatStreamChunk.self, from: data)
        #expect(chunk.model == "llama3.2")
        #expect(chunk.message?.content == "Hello!")
        #expect(chunk.done == false)
    }
    
    @Test("Chat request serializes with stream and context options")
    func testChatRequestSerialization() throws {
        let request = OllamaChatRequest(
            model: "qwen2.5-coder",
            messages: [
                OllamaMessageDTO(role: "system", content: "Code assistant"),
                OllamaMessageDTO(role: "user", content: "Write quicksort")
            ],
            stream: true,
            options: OllamaChatOptions(numCtx: 8192, temperature: 0.7)
        )
        
        let data = try JSONEncoder().encode(request)
        let jsonString = String(data: data, encoding: .utf8)!
        
        #expect(jsonString.contains("qwen2.5-coder"))
        #expect(jsonString.contains("quicksort"))
        #expect(jsonString.contains("8192"))
    }
}
