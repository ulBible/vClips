import Foundation
import SwiftData

@Model
final class ClipItem {
    var content: String
    var createdAt: Date
    var isPinned: Bool
    var lastUsedAt: Date

    init(content: String) {
        self.content = content
        let now = Date()
        self.createdAt = now
        self.isPinned = false
        self.lastUsedAt = now
    }
}
