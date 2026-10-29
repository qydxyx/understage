import Foundation

enum PlanStep: Equatable, Sendable {
    case process(executable: String, arguments: [String])
    case trash(URL)
    case copyFile(from: URL, to: URL)
    case move(from: URL, to: URL)
    case copyPasteboard(String)
    case select([URL])
    case openTerminal(URL)
    case mergePDF(sources: [URL], dest: URL)
    case splitPDF(source: URL, destFolder: URL)
    case ocr(sources: [URL], destTxt: URL?, copyToPasteboard: Bool)
}

struct CommandPlan: Equatable, Sendable {
    var query: String
    var summary: String
    var steps: [PlanStep]
    var creates: [URL]
    var trashes: [URL]
    var reveal: [URL]
    var autoRun: Bool
    var missingTool: String? = nil
    var error: String? = nil
    var readyResult: String? = nil
    var workingDirectory: URL? = nil
}
