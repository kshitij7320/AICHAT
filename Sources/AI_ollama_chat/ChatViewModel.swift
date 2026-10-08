import Foundation
import SwiftUI
import AppKit

@Observable
@MainActor
public final class ChatViewModel {
    // MARK: - Dependencies
    public let ollamaService: OllamaService
    public let contextManager: ContextManager
    public let store: ConversationStore
    
    // MARK: - Persisted Conversations
    public var conversations: [Conversation] = []
    
    // MARK: - Connection & Models State
    public var connectionStatus: ConnectionStatus = .checking
    public var availableModels: [OllamaModel] = []
    public var selectedModelName: String = "llama3.2"
    
    // MARK: - Active Interaction State
    public var selectedConversationID: UUID?
    public var inputPrompt: String = ""
    public var isStreaming: Bool = false
    public var streamingMessageID: UUID?
    public var streamingContent: String = ""
    
    // MARK: - Context Strategy State
    public var contextConfig: ContextConfiguration = .preset8K
    public var lastContextReport: ContextReport?
    
    // MARK: - Error Handling
    public var errorMessage: String?
    public var showErrorBanner: Bool = false
    
    // MARK: - UI & Navigation
    public var searchQuery: String = ""
    public var showRenameSheet: Bool = false
    public var renamingConversation: Conversation?
    public var renameText: String = ""
    public var showSettingsPopover: Bool = false
    
    private var streamingTask: Task<Void, Never>?
    
    // MARK: - Init
    
    public init(
        ollamaService: OllamaService = OllamaService(),
        contextManager: ContextManager = ContextManager(),
        store: ConversationStore = ConversationStore.shared
    ) {
        self.ollamaService = ollamaService
        self.contextManager = contextManager
        self.store = store
        self.conversations = store.load()
        
        if let first = self.conversations.first {
            self.selectedConversationID = first.id
        }
    }
    
    // MARK: - Health & Model Loading
    
    public func checkConnection() async {
        connectionStatus = .checking
        errorMessage = nil
        showErrorBanner = false
        
        do {
            let models = try await ollamaService.fetchAvailableModels()
            availableModels = models
            connectionStatus = .connected(modelCount: models.count)
            
            // Select first model if current selection is not in list
            if !models.contains(where: { $0.name == selectedModelName }), let first = models.first {
                selectedModelName = first.name
            }
        } catch let err as OllamaError {
            connectionStatus = .unreachable(message: err.localizedDescription)
            errorMessage = err.localizedDescription
            showErrorBanner = true
        } catch {
            let desc = error.localizedDescription
            connectionStatus = .unreachable(message: desc)
            errorMessage = desc
            showErrorBanner = true
        }
    }
    
    // MARK: - Messaging & Streaming Flow
    
    public func sendMessage(in conversation: Conversation) {
        let trimmed = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        
        // 1. Create and append User Message
        let userMessage = ChatMessage(
            role: "user",
            content: trimmed,
            timestamp: Date(),
            tokenCount: ContextManager.estimateTokens(for: trimmed)
        )
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()
        
        // Auto-title if it's the first message
        if conversation.title == "New Chat" || conversation.title.trimmingCharacters(in: .whitespaces).isEmpty {
            conversation.title = generateTitle(from: trimmed)
        }
        
        // Sync selected model with conversation
        conversation.selectedModel = selectedModelName
        
        // Clear input bar
        inputPrompt = ""
        
        // 2. Prepare context window with pruning strategy
        let (payload, report) = contextManager.buildContext(
            systemPrompt: conversation.systemPrompt,
            messages: conversation.messages,
            configuration: contextConfig
        )
        self.lastContextReport = report
        
        // 3. Create placeholder Assistant Message
        let assistantMessageID = UUID()
        let assistantMessage = ChatMessage(
            id: assistantMessageID,
            role: "assistant",
            content: "",
            timestamp: Date(),
            tokenCount: nil
        )
        conversation.messages.append(assistantMessage)
        
        saveChanges()
        
        // 4. Start Streaming Task
        isStreaming = true
        streamingMessageID = assistantMessageID
        streamingContent = ""
        errorMessage = nil
        showErrorBanner = false
        
        streamingTask = Task { [weak self, weak conversation] in
            guard let self = self, let conversation = conversation else { return }
            
            do {
                let stream = await self.ollamaService.streamChat(
                    model: conversation.selectedModel,
                    messages: payload,
                    contextWindowSize: self.contextConfig.tokenBudget
                )
                
                for try await token in stream {
                    if Task.isCancelled { break }
                    
                    self.streamingContent += token
                    assistantMessage.content = self.streamingContent
                }
                
                // Finalize assistant message
                assistantMessage.tokenCount = ContextManager.estimateTokens(for: assistantMessage.content)
                conversation.updatedAt = Date()
                self.saveChanges()
                
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.showErrorBanner = true
                    
                    // If streaming failed with no tokens, remove empty assistant message
                    if assistantMessage.content.isEmpty {
                        conversation.messages.removeAll { $0.id == assistantMessageID }
                        self.saveChanges()
                    }
                }
            }
            
            self.isStreaming = false
            self.streamingMessageID = nil
            self.streamingContent = ""
        }
    }
    
    public func stopGeneration(in conversation: Conversation) {
        streamingTask?.cancel()
        streamingTask = nil
        
        if let id = streamingMessageID,
           let assistantMessage = conversation.messages.first(where: { $0.id == id }) {
            assistantMessage.content = streamingContent
            assistantMessage.tokenCount = ContextManager.estimateTokens(for: assistantMessage.content)
            conversation.updatedAt = Date()
            saveChanges()
        }
        
        isStreaming = false
        streamingMessageID = nil
        streamingContent = ""
    }
    
    // MARK: - Conversation Management
    
    @discardableResult
    public func createConversation() -> Conversation {
        let newConv = Conversation(
            title: "New Chat",
            createdAt: Date(),
            updatedAt: Date(),
            selectedModel: selectedModelName,
            systemPrompt: "You are a helpful, concise, and highly capable AI assistant running locally on macOS."
        )
        conversations.insert(newConv, at: 0)
        selectedConversationID = newConv.id
        saveChanges()
        return newConv
    }
    
    public func deleteConversation(_ conversation: Conversation) {
        if selectedConversationID == conversation.id {
            selectedConversationID = nil
        }
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversationID == nil, let first = conversations.first {
            selectedConversationID = first.id
        }
        saveChanges()
    }
    
    public func promptRename(for conversation: Conversation) {
        renamingConversation = conversation
        renameText = conversation.title
        showRenameSheet = true
    }
    
    public func commitRename() {
        guard let conv = renamingConversation else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            conv.title = trimmed
            conv.updatedAt = Date()
            saveChanges()
        }
        renamingConversation = nil
        showRenameSheet = false
    }
    
    public func saveChanges() {
        store.save(conversations)
    }
    
    // MARK: - Export
    
    public func exportConversation(_ conversation: Conversation, format: ExportFormat) -> String {
        switch format {
        case .markdown:
            var md = "# \(conversation.title)\n\n"
            md += "- **Model:** \(conversation.selectedModel)\n"
            md += "- **Created:** \(conversation.createdAt.formatted(date: .abbreviated, time: .shortened))\n"
            if let sys = conversation.systemPrompt, !sys.isEmpty {
                md += "- **System Prompt:** \(sys)\n"
            }
            md += "\n---\n\n"
            
            for msg in conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
                let roleName = msg.role.capitalized
                let timeStr = msg.timestamp.formatted(date: .omitted, time: .shortened)
                md += "### \(roleName) (\(timeStr))\n\n"
                md += "\(msg.content)\n\n"
            }
            return md
            
        case .json:
            struct ExportMessage: Codable {
                let id: String
                let role: String
                let content: String
                let timestamp: String
                let tokenCount: Int?
            }
            struct ExportChat: Codable {
                let id: String
                let title: String
                let model: String
                let createdAt: String
                let systemPrompt: String?
                let messages: [ExportMessage]
            }
            
            let exportData = ExportChat(
                id: conversation.id.uuidString,
                title: conversation.title,
                model: conversation.selectedModel,
                createdAt: conversation.createdAt.ISO8601Format(),
                systemPrompt: conversation.systemPrompt,
                messages: conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }).map {
                    ExportMessage(
                        id: $0.id.uuidString,
                        role: $0.role,
                        content: $0.content,
                        timestamp: $0.timestamp.ISO8601Format(),
                        tokenCount: $0.tokenCount
                    )
                }
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(exportData), let jsonString = String(data: data, encoding: .utf8) {
                return jsonString
            }
            return "{}"
        }
    }
    
    public func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Helpers
    
    private func generateTitle(from text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 36 {
            return cleaned
        }
        let index = cleaned.index(cleaned.startIndex, offsetBy: 36)
        return String(cleaned[..<index]) + "..."
    }
}
