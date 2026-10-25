import Foundation

struct ChatMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    var role: Role
    var content: String
}

protocol ChatProvider: Sendable {
    func complete(messages: [ChatMessage], model: String) async throws -> String
}

enum ChatProviderError: Error, LocalizedError {
    case notConfigured
    case badURL
    case http(Int, String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Add an API key or start a local model in Settings.")
        case .badURL: String(localized: "Vendor base URL is invalid.")
        case .http(let code, let body): "HTTP \(code): \(body.prefix(240))"
        case .emptyReply: String(localized: "The model returned an empty reply.")
        }
    }
}
