import Foundation

// MARK: - Context Configuration & Analytics

public struct ContextConfiguration: Sendable, Equatable {
    public var tokenBudget: Int
    public var reserveOutputTokens: Int
    public var maxTurnDepth: Int?
    
    public init(
        tokenBudget: Int = 8192,
        reserveOutputTokens: Int = 1024,
        maxTurnDepth: Int? = nil
    ) {
        self.tokenBudget = tokenBudget
        self.reserveOutputTokens = reserveOutputTokens
        self.maxTurnDepth = maxTurnDepth
    }
    
    public static let preset4K = ContextConfiguration(tokenBudget: 4096, reserveOutputTokens: 1024)
    public static let preset8K = ContextConfiguration(tokenBudget: 8192, reserveOutputTokens: 1024)
    public static let preset16K = ContextConfiguration(tokenBudget: 16384, reserveOutputTokens: 2048)
    public static let preset32K = ContextConfiguration(tokenBudget: 32768, reserveOutputTokens: 4096)
}

public struct ContextReport: Sendable, Equatable {
    public let totalInputTokens: Int
    public let tokenBudget: Int
    public let systemPromptTokens: Int
    public let retainedMessagesCount: Int
    public let prunedMessagesCount: Int
    public let reserveOutputTokens: Int
    
    public var utilizationPercentage: Double {
        guard tokenBudget > 0 else { return 0 }
        return min(1.0, Double(totalInputTokens) / Double(tokenBudget)) * 100.0
    }
    
    public var remainingTokens: Int {
        max(0, tokenBudget - totalInputTokens - reserveOutputTokens)
    }
}

// MARK: - Context Manager

public struct ContextManager: Sendable {
    
    public init() {}
    
    // MARK: - Token Estimation
    
    /// Fast, dependency-free offline token estimation for standard LLM tokenizers (Llama 3, Mistral, Qwen).
    /// Standard English text averages ~3.8-4 characters per token; code and punctuation are denser.
    public static func estimateTokens(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        
        var tokenCount: Double = 0
        var currentWordLength = 0
        var whitespaceCount = 0
        var punctuationCount = 0
        var digitCount = 0
        
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if currentWordLength > 0 {
                    tokenCount += max(1.0, Double(currentWordLength) / 3.8)
                    currentWordLength = 0
                }
                whitespaceCount += 1
            } else if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                if currentWordLength > 0 {
                    tokenCount += max(1.0, Double(currentWordLength) / 3.8)
                    currentWordLength = 0
                }
                punctuationCount += 1
            } else if CharacterSet.decimalDigits.contains(scalar) {
                digitCount += 1
            } else {
                currentWordLength += 1
            }
        }
        
        if currentWordLength > 0 {
            tokenCount += max(1.0, Double(currentWordLength) / 3.8)
        }
        
        // Punctuation and code symbols often tokenize to ~1 token per 1.5-2 characters
        tokenCount += Double(punctuationCount) * 0.75
        // Consecutive digits often tokenize in pairs or single digits
        tokenCount += Double(digitCount) * 0.7
        // Newlines and indentation tabs
        tokenCount += Double(whitespaceCount) * 0.25
        
        return max(1, Int(ceil(tokenCount)))
    }
    
    public static func estimateTokens(for message: OllamaMessageDTO) -> Int {
        // Overhead of message framing (e.g. ChatML <|im_start|>role\ncontent<|im_end|>) ~ 4 tokens
        let framingOverhead = 4
        return framingOverhead + estimateTokens(for: message.content)
    }
    
    public static func estimateTokens(for message: ChatMessage) -> Int {
        let framingOverhead = 4
        return framingOverhead + estimateTokens(for: message.content)
    }

    // MARK: - Context Window Construction & Dynamic Pruning
    
    /// Constructs a safe, token-budgeted message history for Ollama:
    /// 1. Injects the system prompt at index 0 (cost budgeted first).
    /// 2. Iterates backwards through messages from newest to oldest.
    /// 3. Retains the most recent conversation pairs that fit within the remaining token budget.
    /// 4. Discards older mid-thread messages while keeping the root instruction intact.
    public func buildContext(
        systemPrompt: String?,
        messages: [ChatMessage],
        configuration: ContextConfiguration
    ) -> (payload: [OllamaMessageDTO], report: ContextReport) {
        
        let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSystemPrompt = !(trimmedSystemPrompt?.isEmpty ?? true)
        
        // Calculate system prompt cost
        let systemPromptTokens: Int
        if hasSystemPrompt, let prompt = trimmedSystemPrompt {
            systemPromptTokens = Self.estimateTokens(for: OllamaMessageDTO(role: "system", content: prompt))
        } else {
            systemPromptTokens = 0
        }
        
        // Available tokens for conversation history
        let availableBudget = max(100, configuration.tokenBudget - configuration.reserveOutputTokens - systemPromptTokens)
        
        // Filter out any standalone system messages already stored in message log
        let conversationalMessages = messages.filter { $0.role != "system" }
        
        // Dynamic sliding window: select from newest backwards
        var accumulatedTokens = 0
        var retainedReversed: [ChatMessage] = []
        var turnCounter = 0
        
        for message in conversationalMessages.reversed() {
            // Check turn depth limit if configured
            if let maxTurns = configuration.maxTurnDepth {
                if message.role == "user" {
                    turnCounter += 1
                    if turnCounter > maxTurns {
                        break
                    }
                }
            }
            
            let messageTokens = message.tokenCount ?? Self.estimateTokens(for: message)
            
            // Ensure we include at least the very latest user message, even if it's tight
            if accumulatedTokens + messageTokens <= availableBudget || retainedReversed.isEmpty {
                retainedReversed.append(message)
                accumulatedTokens += messageTokens
            } else {
                // Cannot fit this older message; stop and prune
                break
            }
        }
        
        let retainedChronological = retainedReversed.reversed()
        let prunedCount = conversationalMessages.count - retainedChronological.count
        
        // Assemble final DTO payload
        var resultPayload: [OllamaMessageDTO] = []
        
        // Index 0: Root system prompt
        if hasSystemPrompt, let prompt = trimmedSystemPrompt {
            resultPayload.append(OllamaMessageDTO(role: "system", content: prompt))
        }
        
        // Append chronologically ordered retained messages
        for msg in retainedChronological {
            resultPayload.append(OllamaMessageDTO(role: msg.role, content: msg.content))
        }
        
        let totalInputTokens = systemPromptTokens + accumulatedTokens
        
        let report = ContextReport(
            totalInputTokens: totalInputTokens,
            tokenBudget: configuration.tokenBudget,
            systemPromptTokens: systemPromptTokens,
            retainedMessagesCount: retainedChronological.count,
            prunedMessagesCount: prunedCount,
            reserveOutputTokens: configuration.reserveOutputTokens
        )
        
        return (resultPayload, report)
    }
}
