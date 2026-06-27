import Foundation
import SwiftData

@MainActor
final class HistoryStore {
    let maxUnpinned = 200
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    func capture(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = firstItem(withContent: trimmed) {
            existing.lastUsedAt = Date()
            save()
            return
        }

        context.insert(ClipItem(content: trimmed))
        save()
        cleanup()
    }

    func search(_ query: String) -> [ClipItem] {
        let items = (try? context.fetch(FetchDescriptor<ClipItem>())) ?? []
        let filtered: [ClipItem]
        if query.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { $0.content.localizedCaseInsensitiveContains(query) }
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        save()
    }

    func markUsed(_ item: ClipItem) {
        item.lastUsedAt = Date()
        save()
    }

    private func firstItem(withContent content: String) -> ClipItem? {
        let all = (try? context.fetch(FetchDescriptor<ClipItem>())) ?? []
        return all.first { $0.content == content }
    }

    private func cleanup() {
        let all = (try? context.fetch(FetchDescriptor<ClipItem>())) ?? []
        let unpinned = all.filter { !$0.isPinned }.sorted { $0.lastUsedAt > $1.lastUsedAt }
        guard unpinned.count > maxUnpinned else { return }
        for item in unpinned[maxUnpinned...] {
            context.delete(item)
        }
        save()
    }

    private func save() {
        try? context.save()
    }
}
