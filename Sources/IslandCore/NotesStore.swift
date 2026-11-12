import Foundation

/// A note is just a Markdown file on disk. The file URL is its identity.
public struct Note: Identifiable, Equatable, Hashable {
    public let id: URL
    public var body: String
    public var modified: Date

    public init(id: URL, body: String, modified: Date) {
        self.id = id
        self.body = body
        self.modified = modified
    }

    private var contentLines: [String] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// First non-empty line, without Markdown heading / list markers.
    public var title: String {
        guard let first = contentLines.first else { return "Untitled" }
        let cleaned = Note.stripMarkers(first)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// Second non-empty line, used as a one-line preview in the list.
    public var preview: String {
        contentLines.dropFirst().first.map(Note.stripMarkers) ?? ""
    }

    public var isBlank: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func stripMarkers(_ line: String) -> String {
        var s = Substring(line)
        for prefix in ["- [ ] ", "- [x] ", "- [X] "] where s.hasPrefix(prefix) {
            s = s.dropFirst(prefix.count)
        }
        while s.first == "#" { s = s.dropFirst() }
        if s.hasPrefix("- ") || s.hasPrefix("* ") { s = s.dropFirst(2) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

/// Reads and writes notes as plain `.md` files in one folder. No database, no server.
@MainActor
public final class NotesStore: ObservableObject {
    @Published public private(set) var notes: [Note] = []
    public let folder: URL
    private let fm = FileManager.default

    public nonisolated static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Island Notes", isDirectory: true)
    }

    public init(folder: URL = NotesStore.defaultFolder) {
        self.folder = folder
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    /// Re-reads the folder, so edits made in other editors show up.
    public func reload() {
        let urls = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        notes = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url in
                guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return Note(id: url, body: body, modified: date)
            }
            .sorted { $0.modified > $1.modified }
    }

    public func note(_ id: URL?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    @discardableResult
    public func create(body: String = "") -> Note? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = formatter.string(from: Date())

        var url = folder.appendingPathComponent("\(base).md")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).md")
            n += 1
        }

        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        let note = Note(id: url, body: body, modified: Date())
        notes.insert(note, at: 0)
        return note
    }

    public func save(_ id: URL, body: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[i].body != body else { return }
        try? body.write(to: id, atomically: true, encoding: .utf8)
        var note = notes.remove(at: i)
        note.body = body
        note.modified = Date()
        notes.insert(note, at: 0)
    }

    /// Moves a note to the Trash (recoverable), never a hard delete.
    public func trash(_ id: URL) {
        try? fm.trashItem(at: id, resultingItemURL: nil)
        notes.removeAll { $0.id == id }
    }

    /// Removes notes that were created but never written in.
    public func removeBlankNotes() {
        for note in notes where note.isBlank {
            try? fm.removeItem(at: note.id)
        }
        notes.removeAll(where: \.isBlank)
    }

    public func search(_ query: String) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notes }
        return notes.filter { $0.body.localizedCaseInsensitiveContains(q) }
    }
}
