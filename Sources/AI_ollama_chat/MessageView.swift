import Foundation
import SwiftUI
import AppKit

// MARK: - Message Bubble Component

public struct MessageView: View {
    public let message: ChatMessage
    public let isStreaming: Bool
    public let onCopy: (String) -> Void
    
    @State private var isHovering = false
    @State private var copiedRecently = false
    
    public init(
        message: ChatMessage,
        isStreaming: Bool = false,
        onCopy: @escaping (String) -> Void
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.onCopy = onCopy
    }
    
    private var isUser: Bool {
        message.role == "user"
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 48)
                userMessageBubble
            } else {
                assistantMessageBubble
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    // MARK: - User Message Bubble
    
    private var userMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                if isHovering {
                    copyButton
                        .transition(.opacity)
                }
                
                Text(message.content)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            
            HStack(spacing: 6) {
                if let tokens = message.tokenCount {
                    Text("~\(tokens) tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.trailing, 4)
        }
    }
    
    // MARK: - Assistant Message Bubble
    
    private var assistantMessageBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            // Assistant Avatar
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                // Header (Role & Actions)
                HStack(alignment: .center, spacing: 8) {
                    Text("Assistant")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    if let tokens = message.tokenCount {
                        Text("~\(tokens) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if isHovering || copiedRecently {
                        copyButton
                            .transition(.opacity)
                    }
                }
                
                // Rich Markdown & Code Blocks Body
                MarkdownContentView(content: message.content, isStreaming: isStreaming)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
    
    private var copyButton: some View {
        Button {
            onCopy(message.content)
            copiedRecently = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                copiedRecently = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copiedRecently ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                if copiedRecently {
                    Text("Copied")
                        .font(.caption2)
                }
            }
            .foregroundStyle(copiedRecently ? .green : .secondary)
            .padding(5)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Copy message")
    }
}

// MARK: - Markdown & Code Block Parser & Renderer

public struct MarkdownContentView: View {
    public let content: String
    public let isStreaming: Bool
    
    public init(content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
    }
    
    public var body: some View {
        let blocks = parseMarkdownBlocks(from: content)
        
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block {
                case .text(let id, let text):
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(LocalizedStringKey(text))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(.primary)
                        
                        if isStreaming && id == blocks.last?.id {
                            BlinkingCursor()
                        }
                    }
                    
                case .codeBlock(_, let lang, let code):
                    CodeBlockView(language: lang, code: code)
                }
            }
            
            if blocks.isEmpty && isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func parseMarkdownBlocks(from raw: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let pattern = "```"
        let parts = raw.components(separatedBy: pattern)
        
        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                // Regular Text Block
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(.text(id: UUID(), content: trimmed))
                }
            } else {
                // Code Block: first line can be language (e.g. "swift\nlet a = 1")
                var lines = part.components(separatedBy: "\n")
                var language = "code"
                var codeBody = part
                
                if let first = lines.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty && !first.contains(" ") {
                    language = first
                    lines.removeFirst()
                    codeBody = lines.joined(separator: "\n")
                }
                
                let trimmedCode = codeBody.trimmingCharacters(in: .newlines)
                blocks.append(.codeBlock(id: UUID(), language: language, code: trimmedCode))
            }
        }
        
        return blocks
    }
}

public enum ContentBlock: Identifiable {
    case text(id: UUID, content: String)
    case codeBlock(id: UUID, language: String, code: String)
    
    public var id: UUID {
        switch self {
        case .text(let id, _): return id
        case .codeBlock(let id, _, _): return id
        }
    }
}

// MARK: - Styled Code Block with Copy Action

public struct CodeBlockView: View {
    public let language: String
    public let code: String
    
    @State private var isCopied = false
    
    public init(language: String, code: String) {
        self.language = language
        self.code = code
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack {
                Text(language.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            
            Divider()
                .overlay(Color.white.opacity(0.08))
            
            // Code Content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .textColor))
                    .lineSpacing(3)
                    .padding(12)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.2))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - Blinking Cursor for Streaming

public struct BlinkingCursor: View {
    @State private var isVisible = true
    
    public var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 7, height: 15)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    isVisible.toggle()
                }
            }
    }
}
