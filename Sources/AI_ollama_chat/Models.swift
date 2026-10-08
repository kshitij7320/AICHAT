import Foundation
import Observation

// MARK: - Local Persistence Models

@Observable
public final class Conversation: Identifiable, Codable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var selectedModel: String
    public var systemPrompt: String?
    public var messages: [ChatMessage] = []
    
    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, selectedModel, systemPrompt, messages
    }
    
    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        selectedModel: String = "llama3.2",
        systemPrompt: String? = "You are a helpful, concise, and highly capable AI assistant running locally on macOS.",
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.selectedModel = selectedModel
        self.systemPrompt = systemPrompt
        self.messages = messages
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.selectedModel = try container.decode(String.self, forKey: .selectedModel)
        self.systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        self.messages = try container.decode([ChatMessage].self, forKey: .messages)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
        try container.encode(messages, forKey: .messages)
    }
}

@Observable
public final class ChatMessage: Identifiable, Codable {
    public var id: UUID
    public var role: String // "system", "user", "assistant"
    public var content: String
    public var timestamp: Date
    public var tokenCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, tokenCount
    }
    
    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = Date(),
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokenCount = tokenCount
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decode(String.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
    }
}

// MARK: - Offline Storage Engine

@MainActor
public final class ConversationStore {
    public static let shared = ConversationStore()
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OllamaChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("conversations.json")
    }
    
    public func load() -> [Conversation] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([Conversation].self, from: data) else {
            return []
        }
        return items
    }
    
    public func save(_ conversations: [Conversation]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(conversations) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Ollama API DTOs

public struct OllamaTagsResponse: Codable, Sendable {
    public let models: [OllamaModel]
    
    public init(models: [OllamaModel]) {
        self.models = models
    }
}

public struct OllamaModel: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let modifiedAt: String?
    public let size: Int64?
    public let digest: String?
    public let details: OllamaModelDetails?
    
    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
        case digest
        case details
    }
    
    public init(
        name: String,
        modifiedAt: String? = nil,
        size: Int64? = nil,
        digest: String? = nil,
        details: OllamaModelDetails? = nil
    ) {
        self.name = name
        self.modifiedAt = modifiedAt
        self.size = size
        self.digest = digest
        self.details = details
    }
    
    public var formattedSize: String {
        guard let size = size else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

public struct OllamaModelDetails: Codable, Hashable, Sendable {
    public let format: String?
    public let family: String?
    public let families: [String]?
    public let parameterSize: String?
    public let quantizationLevel: String?
    
    enum CodingKeys: String, CodingKey {
        case format
        case family
        case families
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
    
    public init(
        format: String? = nil,
        family: String? = nil,
        families: [String]? = nil,
        parameterSize: String? = nil,
        quantizationLevel: String? = nil
    ) {
        self.format = format
        self.family = family
        self.families = families
        self.parameterSize = parameterSize
        self.quantizationLevel = quantizationLevel
    }
}

public struct OllamaMessageDTO: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct OllamaChatOptions: Codable, Sendable {
    public let numCtx: Int?
    public let temperature: Double?
    
    enum CodingKeys: String, CodingKey {
        case numCtx = "num_ctx"
        case temperature
    }
    
    public init(numCtx: Int? = nil, temperature: Double? = nil) {
        self.numCtx = numCtx
        self.temperature = temperature
    }
}

public struct OllamaChatRequest: Codable, Sendable {
    public let model: String
    public let messages: [OllamaMessageDTO]
    public let stream: Bool
    public let options: OllamaChatOptions?
    
    public init(
        model: String,
        messages: [OllamaMessageDTO],
        stream: Bool = true,
        options: OllamaChatOptions? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
    }
}

public struct OllamaChatStreamChunk: Codable, Sendable {
    public let model: String?
    public let createdAt: String?
    public let message: OllamaMessageDTO?
    public let done: Bool
    public let totalDuration: Int64?
    public let loadDuration: Int64?
    public let promptEvalCount: Int?
    public let evalCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case message
        case done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
    
    public init(
        model: String? = nil,
        createdAt: String? = nil,
        message: OllamaMessageDTO? = nil,
        done: Bool = false,
        totalDuration: Int64? = nil,
        loadDuration: Int64? = nil,
        promptEvalCount: Int? = nil,
        evalCount: Int? = nil
    ) {
        self.model = model
        self.createdAt = createdAt
        self.message = message
        self.done = done
        self.totalDuration = totalDuration
        self.loadDuration = loadDuration
        self.promptEvalCount = promptEvalCount
        self.evalCount = evalCount
    }
}

// MARK: - App State & Enums

public enum ConnectionStatus: Equatable, Sendable {
    case checking
    case connected(modelCount: Int)
    case unreachable(message: String)
    
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

public enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown (.md)"
    case json = "JSON (.json)"
    
    public var id: String { rawValue }
    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        }
    }
}
