import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit

public struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isInputFocused: Bool
    
    public init() {}
    
    private var filteredConversations: [Conversation] {
        if viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return viewModel.conversations
        }
        return viewModel.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(viewModel.searchQuery) ||
            $0.messages.contains(where: { $0.content.localizedCaseInsensitiveContains(viewModel.searchQuery) })
        }
    }
    
    private var activeConversation: Conversation? {
        viewModel.conversations.first(where: { $0.id == viewModel.selectedConversationID })
    }
    
    public var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 380)
        } detail: {
            detailChatView
        }
        .task {
            await viewModel.checkConnection()
            if viewModel.selectedConversationID == nil, let first = viewModel.conversations.first {
                viewModel.selectedConversationID = first.id
            }
        }
        .sheet(isPresented: $viewModel.showRenameSheet) {
            renameSheetView
        }
    }
    
    // MARK: - Sidebar View
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Sidebar Header & New Chat Button
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    let newConv = viewModel.createConversation()
                    viewModel.selectedConversationID = newConv.id
                    isInputFocused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: [.command])
                .help("New Chat (Cmd + N)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            // Search Bar with Cmd + K shortcut
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                
                TextField("Search chats (⌘K)...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .font(.system(size: 13))
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .onKeyPress(.escape) {
                viewModel.searchQuery = ""
                isSearchFocused = false
                return .handled
            }
            // Hidden button to catch Cmd+K shortcut
            .background(
                Button("") {
                    isSearchFocused = true
                }
                .keyboardShortcut("k", modifiers: [.command])
                .opacity(0)
            )
            
            Divider()
            
            // Conversations List
            if filteredConversations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(viewModel.searchQuery.isEmpty ? "No conversations yet" : "No results found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(selection: $viewModel.selectedConversationID) {
                    ForEach(filteredConversations) { conv in
                        ConversationRowView(
                            conversation: conv,
                            isSelected: viewModel.selectedConversationID == conv.id
                        )
                        .tag(conv.id)
                        .contextMenu {
                            Button {
                                viewModel.promptRename(for: conv)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Menu {
                                Button("Export as Markdown (.md)") {
                                    saveExportedFile(
                                        conversation: conv,
                                        format: .markdown
                                    )
                                }
                                Button("Export as JSON (.json)") {
                                    saveExportedFile(
                                        conversation: conv,
                                        format: .json
                                    )
                                }
                            } label: {
                                Label("Export Chat", systemImage: "square.and.arrow.up")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                viewModel.deleteConversation(conv)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            
            Divider()
            
            // Bottom Ollama Status Bar
            ollamaStatusBar
        }
    }
    
    // MARK: - Bottom Ollama Status Bar
    
    private var ollamaStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text("localhost:11434")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Button {
                Task {
                    await viewModel.checkConnection()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh Ollama Status")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }
    
    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case .connected: return .green
        case .checking: return .orange
        case .unreachable: return .red
        }
    }
    
    private var statusText: String {
        switch viewModel.connectionStatus {
        case .connected(let count):
            return "Ollama Connected (\(count) model\(count == 1 ? "" : "s"))"
        case .checking:
            return "Checking Ollama..."
        case .unreachable:
            return "Ollama Unreachable"
        }
    }
    
    // MARK: - Detail Chat View
    
    private var detailChatView: some View {
        Group {
            if let conv = activeConversation {
                VStack(spacing: 0) {
                    // Offline Error Banner if Ollama is unreachable
                    if viewModel.showErrorBanner {
                        errorBannerView
                    }
                    
                    // Chat Header Toolbar
                    chatHeaderView(for: conv)
                    
                    Divider()
                    
                    // Messages Thread with autoscroll
                    messagesScrollView(for: conv)
                    
                    Divider()
                    
                    // Bottom Message Input Bar
                    chatInputBar(for: conv)
                }
            } else {
                emptySelectionView
            }
        }
    }
    
    // MARK: - Error Banner View
    
    private var errorBannerView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollama is not reachable at http://localhost:11434")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Make sure Ollama is installed and running. Start it in Terminal:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Text("ollama serve")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    
                    Button("Copy") {
                        viewModel.copyToClipboard("ollama serve")
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                .padding(.top, 2)
            }
            
            Spacer()
            
            Button("Retry") {
                Task {
                    await viewModel.checkConnection()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.orange.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    // MARK: - Chat Header
    
    private func chatHeaderView(for conv: Conversation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text("\(conv.messages.count) messages • Created \(conv.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Model Selector Dropdown
            Picker("", selection: Binding(
                get: { conv.selectedModel },
                set: { newModel in
                    conv.selectedModel = newModel
                    viewModel.selectedModelName = newModel
                    viewModel.saveChanges()
                }
            )) {
                if viewModel.availableModels.isEmpty {
                    Text(conv.selectedModel).tag(conv.selectedModel)
                } else {
                    ForEach(viewModel.availableModels) { model in
                        Text(model.name).tag(model.name)
                    }
                }
            }
            .labelsHidden()
            .frame(width: 170)
            
            // Context Window & Strategy Inspector Popover
            Button {
                viewModel.showSettingsPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    Text("Context")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $viewModel.showSettingsPopover) {
                contextSettingsPopoverView(for: conv)
            }
            
            // Export Menu
            Menu {
                Button("Export as Markdown (.md)") {
                    saveExportedFile(conversation: conv, format: .markdown)
                }
                Button("Export as JSON (.json)") {
                    saveExportedFile(conversation: conv, format: .json)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Export Conversation")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.75))
    }
    
    // MARK: - Context Window Strategy Popover
    
    private func contextSettingsPopoverView(for conv: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Context Window & Prompt Strategy")
                .font(.headline)
            
            // Token Budget Selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Token Budget Window:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("", selection: $viewModel.contextConfig.tokenBudget) {
                    Text("4,096 tokens (4K)").tag(4096)
                    Text("8,192 tokens (8K)").tag(8192)
                    Text("16,384 tokens (16K)").tag(16384)
                    Text("32,768 tokens (32K)").tag(32768)
                }
                .pickerStyle(.segmented)
            }
            
            // Current Utilization
            if let report = viewModel.lastContextReport {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Estimated Context Used:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(report.totalInputTokens) / \(report.tokenBudget) tokens (\(Int(report.utilizationPercentage))%)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    ProgressView(value: min(1.0, Double(report.totalInputTokens) / Double(report.tokenBudget)))
                        .tint(report.utilizationPercentage > 85 ? .orange : .accentColor)
                    
                    HStack(spacing: 8) {
                        Text("Retained: \(report.retainedMessagesCount) msgs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if report.prunedMessagesCount > 0 {
                            Text("Pruned: \(report.prunedMessagesCount) older msgs")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            
            Divider()
            
            // System Prompt Editor
            VStack(alignment: .leading, spacing: 6) {
                Text("System Prompt (Root Instructions):")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: Binding(
                    get: { conv.systemPrompt ?? "" },
                    set: { newPrompt in
                        conv.systemPrompt = newPrompt
                        viewModel.saveChanges()
                    }
                ))
                .font(.system(size: 12))
                .frame(height: 70)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .frame(width: 340)
    }
    
    // MARK: - Messages Scroll View
    
    private func messagesScrollView(for conv: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if conv.messages.isEmpty {
                        emptyThreadPlaceholder(for: conv)
                    } else {
                        ForEach(conv.messages.sorted(by: { $0.timestamp < $1.timestamp })) { msg in
                            MessageView(
                                message: msg,
                                isStreaming: viewModel.isStreaming && viewModel.streamingMessageID == msg.id,
                                onCopy: { text in
                                    viewModel.copyToClipboard(text)
                                }
                            )
                            .id(msg.id)
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .onChange(of: conv.messages.count) {
                if let last = conv.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingContent) {
                if let streamingID = viewModel.streamingMessageID {
                    proxy.scrollTo(streamingID, anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Empty Thread Placeholder
    
    private func emptyThreadPlaceholder(for conv: Conversation) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.accentColor.opacity(0.8))
            
            Text("Ready to Chat with \(conv.selectedModel)")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Send a message below to start a local, private conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Suggestion chips
            HStack(spacing: 10) {
                suggestionButton("Explain Swift Concurrency", in: conv)
                suggestionButton("Write a Python script", in: conv)
                suggestionButton("Summarize text", in: conv)
            }
            .padding(.top, 8)
            
            Spacer(minLength: 40)
        }
        .padding(24)
    }
    
    private func suggestionButton(_ prompt: String, in conv: Conversation) -> some View {
        Button {
            viewModel.inputPrompt = prompt
            viewModel.sendMessage(in: conv)
        } label: {
            Text(prompt)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Input Bar
    
    private func chatInputBar(for conv: Conversation) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                // Expanding Text Field with Return to send, Shift+Return for newline
                TextField("Ask anything (Return to send, Shift + Return for newline)...", text: $viewModel.inputPrompt, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) {
                            // Let default Shift+Return add a newline
                            return .ignored
                        } else {
                            // Submit message
                            viewModel.sendMessage(in: conv)
                            return .handled
                        }
                    }
                
                // Action Buttons: Stop or Send
                if viewModel.isStreaming {
                    Button {
                        viewModel.stopGeneration(in: conv)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Generation")
                } else {
                    Button {
                        viewModel.sendMessage(in: conv)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(
                                viewModel.inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.4)
                                : Color.accentColor
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send Message (Return)")
                }
            }
            
            // Bottom Info Bar (Estimated tokens)
            HStack {
                let estimatedTokens = ContextManager.estimateTokens(for: viewModel.inputPrompt)
                if !viewModel.inputPrompt.isEmpty {
                    Text("~\(estimatedTokens) tokens in input")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(conv.selectedModel) • \(viewModel.contextConfig.tokenBudget / 1024)K Context")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Empty Selection View
    
    private var emptySelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor.opacity(0.7))
            
            Text("Select or Create a Conversation")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Run multi-turn LLMs locally with native macOS performance and offline persistence.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            
            Button {
                let newConv = viewModel.createConversation()
                viewModel.selectedConversationID = newConv.id
                isInputFocused = true
            } label: {
                Label("Start New Chat", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: [.command])
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Rename Sheet
    
    private var renameSheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Conversation")
                .font(.headline)
            
            TextField("Conversation title", text: $viewModel.renameText)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.showRenameSheet = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    viewModel.commitRename()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
    
    // MARK: - Export File Helper
    
    private func saveExportedFile(conversation: Conversation, format: ExportFormat) {
        let content = viewModel.exportConversation(conversation, format: format)
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        let safeTitle = conversation.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        savePanel.nameFieldStringValue = "\(safeTitle).\(format.fileExtension)"
        
        switch format {
        case .markdown:
            savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        case .json:
            savePanel.allowedContentTypes = [.json]
        }
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Conversation Row View

private struct ConversationRowView: View {
    let conversation: Conversation
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            HStack {
                if let lastMsg = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
                    Text(lastMsg.content.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No messages yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                
                Spacer()
                
                Text(conversation.selectedModel)
                    .font(.system(size: 9.5, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
