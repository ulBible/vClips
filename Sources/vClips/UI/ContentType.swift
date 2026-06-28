import Foundation

enum ContentType {
    case url
    case email
    case filePath
    case text

    static func detect(_ text: String) -> ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if matchesEmail(trimmed) { return .email }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return .url }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") { return .filePath }
        return .text
    }

    var symbolName: String {
        switch self {
        case .url: return "link"
        case .email: return "envelope"
        case .filePath: return "doc"
        case .text: return "doc.on.clipboard"
        }
    }

    private static func matchesEmail(_ s: String) -> Bool {
        guard !s.contains(" "), !s.contains("\n") else { return false }
        let pattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}
