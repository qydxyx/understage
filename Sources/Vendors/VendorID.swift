import Foundation

enum VendorKind: Equatable, Sendable {
    case openaiCompat
    case anthropic
}

enum VendorID: String, CaseIterable, Identifiable, Codable, Sendable {
    case openai
    case anthropic
    case openrouter
    case xai
    case deepseek
    case ollama
    case lmstudio
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .openrouter: "OpenRouter"
        case .xai: "xAI"
        case .deepseek: "DeepSeek"
        case .ollama: "Ollama"
        case .lmstudio: "LM Studio"
        case .custom: "Custom"
        }
    }

    var kind: VendorKind {
        self == .anthropic ? .anthropic : .openaiCompat
    }

    var needsKey: Bool {
        switch self {
        case .ollama, .lmstudio: false
        default: true
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: "gpt-4.1-mini"
        case .anthropic: "claude-haiku-4-5"
        case .openrouter: "openai/gpt-4.1-mini"
        case .xai: "grok-4-fast-non-reasoning"
        case .deepseek: "deepseek-chat"
        case .ollama: "llama3.1"
        case .lmstudio: ""
        case .custom: "gpt-4.1-mini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .xai: "https://api.x.ai/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .ollama: "http://127.0.0.1:11434/v1"
        case .lmstudio: "http://127.0.0.1:1234/v1"
        case .custom: "https://api.openai.com/v1"
        }
    }
}
