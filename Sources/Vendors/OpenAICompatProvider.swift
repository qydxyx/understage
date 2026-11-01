import Foundation

struct OpenAICompatProvider: ChatProvider {
    var baseURL: URL
    var apiKey: String?
    var session: URLSession = .shared

    func complete(messages: [ChatMessage], model: String) async throws -> String {
        let url = join(baseURL, "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ChatProviderError.http(code, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ChatProviderError.emptyReply
        }
        return content
    }
}

func join(_ base: URL, _ path: String) -> URL {
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
        return base.appendingPathComponent(path)
    }
    let extra = path.hasPrefix("/") ? String(path.dropFirst()) : path
    var combined = components.percentEncodedPath
    if combined.isEmpty { combined = "/" }
    if !combined.hasSuffix("/") { combined += "/" }
    combined += extra
    while combined.contains("//") {
        combined = combined.replacingOccurrences(of: "//", with: "/")
    }
    components.percentEncodedPath = combined
    return components.url ?? base.appendingPathComponent(path)
}
