import Foundation

public struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var path: String
    public var added: Date

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
}

/// A temporary holding spot for files: drop them in, switch apps, drag them out.
/// Only the file locations are remembered; the files themselves are never copied or moved.
@MainActor
public final class ShelfStore: ObservableObject {
    @Published public private(set) var items: [ShelfItem] = []

    private let file: URL
    private let fm = FileManager.default

    public init(directory: URL) {
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("shelf.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            // Forget files that were deleted or moved since last time.
            items = saved.filter { fm.fileExists(atPath: $0.path) }
        }
    }

    /// Adds files that exist and aren't on the shelf yet. Returns how many were added.
    @discardableResult
    public func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            let path = url.standardizedFileURL.path
            guard fm.fileExists(atPath: path), !items.contains(where: { $0.path == path }) else { continue }
            items.append(ShelfItem(id: UUID(), path: path, added: Date()))
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
