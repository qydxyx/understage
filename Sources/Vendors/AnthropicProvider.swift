import Foundation

struct AnthropicProvider: ChatProvider {
    var baseURL: URL
    var apiKey: String
    var session: URLSession = .shared

    func complete(messages: [ChatMessage], model: String) async throws -> String {
        let url = join(baseURL, "v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
        let turns = messages.filter { $0.role != .system }.map {
            ["role": $0.role == .assistant ? "assistant" : "user", "content": $0.content]
        }
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "temperature": 0,
            "messages": turns,
        ]
        if !system.isEmpty { payload["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ChatProviderError.http(code, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else {
            throw ChatProviderError.emptyReply
        }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw ChatProviderError.emptyReply }
        return text
    }
}
