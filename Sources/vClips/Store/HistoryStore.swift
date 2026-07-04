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
        // Match and order in the store instead of fetching the whole table
        // and filtering in memory on every keystroke.
        var descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        if !query.isEmpty {
            descriptor.predicate = #Predicate { $0.content.localizedStandardContains(query) }
        }
        let items = (try? context.fetch(descriptor)) ?? []
        // Pinned first, preserving recency order within each group.
        return items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        save()
    }

    func markUsed(_ item: ClipItem) {
        item.lastUsedAt = Date()
        save()
    }

    func delete(_ item: ClipItem) {
        context.delete(item)
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
