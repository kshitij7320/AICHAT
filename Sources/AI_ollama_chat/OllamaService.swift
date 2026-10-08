import Foundation

public enum OllamaError: LocalizedError, Sendable {
    case invalidURL(String)
    case serverUnreachable(URL, underlying: String)
    case modelNotFound(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case streamingFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid Ollama endpoint URL: \(url)"
        case .serverUnreachable(let url, let underlying):
            return "Cannot reach Ollama daemon at \(url.absoluteString). Ensure Ollama is running (`ollama serve`). Details: \(underlying)"
        case .modelNotFound(let model):
            return "The model '\(model)' was not found on your local Ollama instance. Run `ollama pull \(model)` in Terminal."
        case .httpError(let statusCode, let body):
            return "Ollama returned HTTP error \(statusCode): \(body)"
        case .decodingError(let details):
            return "Failed to parse Ollama response: \(details)"
        case .streamingFailed(let message):
            return "Ollama streaming error: \(message)"
        case .cancelled:
            return "Generation was cancelled."
        }
    }
}

public actor OllamaService {
    public static let defaultBaseURL = URL(string: "http://localhost:11434")!
    
    private let baseURL: URL
    private let session: URLSession
    
    public init(baseURL: URL = defaultBaseURL, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Health Check & Model Discovery
    
    public func checkHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("api/version")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
    
    public func fetchAvailableModels() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.serverUnreachable(baseURL, underlying: "Invalid response from server")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "No body"
                throw OllamaError.httpError(statusCode: httpResponse.statusCode, body: body)
            }
            
            do {
                let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
                return tagsResponse.models
            } catch {
                throw OllamaError.decodingError(error.localizedDescription)
            }
        } catch let err as OllamaError {
            throw err
        } catch {
            throw OllamaError.serverUnreachable(baseURL, underlying: error.localizedDescription)
        }
    }
    
    // MARK: - Streaming Chat API (`POST /api/chat`)
    
    public func streamChat(
        model: String,
        messages: [OllamaMessageDTO],
        contextWindowSize: Int? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let url = baseURL.appendingPathComponent("api/chat")
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let options = OllamaChatOptions(
                        numCtx: contextWindowSize,
                        temperature: temperature
                    )
                    
                    let payload = OllamaChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        options: options
                    )
                    
                    request.httpBody = try JSONEncoder().encode(payload)
                    
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await self.session.bytes(for: request)
                    } catch {
                        if Task.isCancelled {
                            continuation.finish(throwing: OllamaError.cancelled)
                            return
                        }
                        throw OllamaError.serverUnreachable(self.baseURL, underlying: error.localizedDescription)
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OllamaError.serverUnreachable(self.baseURL, underlying: "Invalid HTTP response")
                    }
                    
                    if httpResponse.statusCode == 404 {
                        throw OllamaError.modelNotFound(model)
                    }
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw OllamaError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
                    }
                    
                    let decoder = JSONDecoder()
                    
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: OllamaError.cancelled)
                            return
                        }
                        
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }
                        
                        guard let data = trimmed.data(using: .utf8) else { continue }
                        
                        do {
                            let chunk = try decoder.decode(OllamaChatStreamChunk.self, from: data)
                            if let token = chunk.message?.content, !token.isEmpty {
                                continuation.yield(token)
                            }
                            
                            if chunk.done {
                                continuation.finish()
                                return
                            }
                        } catch {
                            // If a single line fails to parse, check if it's an error payload: {"error": "..."}
                            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let errorMsg = errorJson["error"] as? String {
                                throw OllamaError.streamingFailed(errorMsg)
                            }
                            // Otherwise, ignore malformed heartbeat/comment lines
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: OllamaError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
