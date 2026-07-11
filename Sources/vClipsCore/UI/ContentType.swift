import SwiftUI

enum ContentType {
    case url
    case email
    case filePath
    case text

    static func detect(_ text: String) -> ContentType {
        // The head of the content decides the type; prefix-bounding avoids
        // trimming and scanning multi-megabyte clips on every call.
        let head = String(text.prefix(320)).trimmingCharacters(in: .whitespacesAndNewlines)
        // URL/path prefixes win over the email pattern — "https://user@host/x"
        // and "git@host:repo" style strings contain an @ but are not emails.
        if head.range(of: "http://", options: [.caseInsensitive, .anchored]) != nil ||
           head.range(of: "https://", options: [.caseInsensitive, .anchored]) != nil {
            return .url
        }
        if head.hasPrefix("/") || head.hasPrefix("~/") { return .filePath }
        // Emails are short; only match when the head covers the whole content.
        if text.utf8.count <= 320, matchesEmail(head) { return .email }
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

    /// Chip background color, kept beside symbolName/label so adding a case
    /// updates icon, label, and color in one place.
    var tint: Color {
        switch self {
        case .url: return .blue
        case .email: return .green
        case .filePath: return .orange
        case .text: return Color(nsColor: .systemGray)
        }
    }

    private static func matchesEmail(_ s: String) -> Bool {
        guard !s.contains(" "), !s.contains("\n") else { return false }
        let pattern = "^[^@\\s:/]+@[^@\\s:/]+\\.[^@\\s:/]+$"
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}
