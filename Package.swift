// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AI-ollama-chat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OllamaChat",
            targets: ["AI_ollama_chat"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "AI_ollama_chat",
            path: "Sources/AI_ollama_chat"
        ),
    ]
)
