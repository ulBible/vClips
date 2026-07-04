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
        case .email: return "envelope.fill"
        case .filePath: return "folder.fill"
        case .text: return "text.alignleft"
        }
    }

    /// Short human-readable name shown in the row's metadata line.
    var label: String {
        switch self {
        case .url: return "Link"
        case .email: return "Email"
        case .filePath: return "File"
        case .text: return "Text"
        }
    }

    private static func matchesEmail(_ s: String) -> Bool {
        guard !s.contains(" "), !s.contains("\n") else { return false }
        let pattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}
