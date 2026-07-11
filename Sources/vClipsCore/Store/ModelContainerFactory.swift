import Foundation
import SwiftData

enum ModelContainerFactory {
    static func onDisk() throws -> ModelContainer {
        let schema = Schema([ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func inMemory() throws -> ModelContainer {
        let schema = Schema([ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
