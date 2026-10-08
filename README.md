# OllamaChat for macOS

A native, high-performance, offline macOS chat client built with **Swift 5.10+**, **SwiftUI**, and **SwiftData** for local Large Language Models powered by [Ollama](https://ollama.ai).

---

## Highlights & Features

- **100% Native & Dependency-Free:** Relies strictly on standard Apple frameworks (`SwiftUI`, `SwiftData`, `URLSession`, `AppKit`). Zero third-party dependencies.
- **Dual-Pane Native Interface:** `NavigationSplitView` sidebar and detail view adhering to macOS Sonoma/Sequoia HIG.
- **Local Persistence via SwiftData:** Multi-turn conversations, timestamps, selected models, and messages stored offline with cascade deletion.
- **Streaming Response Pipeline:** Non-blocking `URLSession.shared.bytes` HTTP streaming directly mapped to `@Observable` state on `@MainActor`.
- **Token-Aware Context Strategy:** Dedicated `ContextManager` that enforces sliding-window token budgets (4K, 8K, 16K, 32K), guarantees root system prompt retention at index `0`, and automatically prunes mid-thread turns when safe limits are reached.
- **Rich Markdown & Code Rendering:** Monospaced code blocks with syntax styling, language banners, and one-click copy buttons.
- **Error Boundaries & Health Checks:** Real-time polling and status indicator for `localhost:11434` with user-friendly recovery banners (`ollama serve`).
- **Productivity Shortcuts:**
  - `Cmd + N`: Start New Chat
  - `Cmd + K`: Focus Search Filter
  - `Return`: Send Message
  - `Shift + Return`: Insert Newline
  - Stop button to cancel generation mid-stream.
  - Chat Export as **Markdown (.md)** and **JSON (.json)** via native `NSSavePanel`.

---

## Project Structure

```text
AI-ollama-chat/
├── Package.swift                             # Swift Package Manager configuration (macOS 14+)
├── OllamaChat.entitlements                   # App Sandbox network client permissions
├── Sources/
│   ├── AI_ollama_chat/                       # Core library module
│   │   ├── Models.swift                      # SwiftData models & Ollama REST DTOs
│   │   ├── OllamaService.swift               # Concurrency actor for Ollama REST & bytes streaming
│   │   ├── ContextManager.swift              # Token estimation, sliding window & pruning
│   │   ├── ChatViewModel.swift               # Main @Observable view model & state coordinator
│   │   ├── MessageView.swift                 # Message bubbles, Markdown parser & code blocks
│   │   └── ContentView.swift                 # NavigationSplitView, sidebar & detail chat UI
│   └── OllamaChat/                           # Executable macOS App target
│       └── OllamaChatApp.swift               # @main App entry point & SwiftData ModelContainer
└── Tests/
    └── AI_ollama_chatTests/
        └── AI_ollama_chatTests.swift         # Unit test suite (Swift Testing)
```

---

## App Sandbox Entitlements

To connect to local daemons (`http://localhost:11434`) under macOS App Sandboxing, outgoing network client permissions are enabled in [`OllamaChat.entitlements`](file:///Users/kshitijhimanshu/Documents/Faltu-code/AI-ollama-chat/OllamaChat.entitlements):

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

---

## Getting Started

### 1. Ensure Ollama is Running
If Ollama is not already running on your machine:
```bash
ollama serve
```

Pull your favorite model (e.g. Llama 3.2 or Qwen 2.5 Coder):
```bash
ollama pull llama3.2
ollama pull qwen2.5-coder
```

### 2. Open and Run in Xcode
Open the Swift Package in Xcode:
```bash
open Package.swift
```
Select the **OllamaChat** executable scheme and click **Run (Cmd + R)**.

### 3. Run Unit Tests
Run the Swift Testing test suite:
```bash
swift test
```
# AICHAT
