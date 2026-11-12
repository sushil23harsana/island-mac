import CryptoKit
import Foundation

/// One thing that was copied: text, an image, or files from Finder.
public struct ClipItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
        case files
    }

    public let id: UUID
    public var kind: Kind
    /// The text, or newline-separated file paths. Empty for images.
    public var text: String
    /// File name of the PNG inside the history's image folder.
    public var imageFile: String?
    public var imageWidth: Double?
    public var imageHeight: Double?
    /// SHA-256 of the image data, used to avoid storing the same image twice.
    public var imageHash: String?
    public var sourceApp: String?
    public var date: Date
    public var pinned: Bool

    public var filePaths: [String] {
        kind == .files ? text.split(separator: "\n").map(String.init) : []
    }

    /// True for a single http(s) link.
    public var isLink: Bool {
        guard kind == .text else { return false }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace),
              let url = URL(string: t), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// "#ff8800" style colors, so the list can show a swatch.
    public var hexColor: (r: Double, g: Double, b: Double)? {
        guard kind == .text else { return nil }
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    /// One-line summary for the list.
    public var title: String {
        switch kind {
        case .text:
            let firstLine = text.split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            return firstLine.trimmingCharacters(in: .whitespaces)
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image \(Int(w))×\(Int(h))" }
            return "Image"
        case .files:
            let names = filePaths.map { ($0 as NSString).lastPathComponent }
            return names.count == 1 ? names[0] : "\(names[0]) + \(names.count - 1) more"
        }
    }
}

/// Clipboard history kept on this Mac only: a JSON file plus a folder of PNGs.
@MainActor
public final class ClipboardHistory: ObservableObject {
    @Published public private(set) var items: [ClipItem] = []

    /// Most unpinned items kept. Pinned items are never trimmed.
    public var limit: Int {
        didSet {
            guard limit != oldValue else { return }
            trim()
            save()
        }
    }
    /// Texts longer than this are skipped (huge logs, base64 blobs…).
    public static let maxTextLength = 500_000
    /// Images larger than this are skipped.
    public static let maxImageBytes = 15 * 1024 * 1024

    public let directory: URL
    private var historyFile: URL { directory.appendingPathComponent("clipboard.json") }
    public var imagesFolder: URL { directory.appendingPathComponent("clipboard-images", isDirectory: true) }
    private let fm = FileManager.default
    private let now: () -> Date

    public nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Island", isDirectory: true)
    }

    public init(directory: URL = ClipboardHistory.defaultDirectory,
                limit: Int = 200,
                now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.limit = limit
        self.now = now
        try? fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        load()
    }

    // MARK: Adding

    public func addText(_ text: String, sourceApp: String? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= Self.maxTextLength else { return }
        if let i = items.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            bump(at: i, sourceApp: sourceApp)
            return
        }
        insert(ClipItem(id: UUID(), kind: .text, text: text, sourceApp: sourceApp, date: now(), pinned: false))
    }

    public func addFiles(_ paths: [String], sourceApp: String? = nil) {
        guard !paths.isEmpty else { return }
        let joined = paths.joined(separator: "\n")
        if let i = items.firstIndex(where: { $0.kind == .files && $0.text == joined }) {
            bump(at: i, sourceApp: sourceApp)
            return
        }
        insert(ClipItem(id: UUID(), kind: .files, text: joined, sourceApp: sourceApp, date: now(), pinned: false))
    }

    public func addImage(png: Data, width: Double, height: Double, sourceApp: String? = nil) {
        guard !png.isEmpty, png.count <= Self.maxImageBytes else { return }
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        if let i = items.firstIndex(where: { $0.imageHash == hash }) {
            bump(at: i, sourceApp: sourceApp)
            return
        }
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        do {
            try png.write(to: imagesFolder.appendingPathComponent(fileName), options: .atomic)
        } catch {
            return
        }
        insert(ClipItem(id: id, kind: .image, text: "", imageFile: fileName,
                        imageWidth: width, imageHeight: height, imageHash: hash,
                        sourceApp: sourceApp, date: now(), pinned: false))
    }

    // MARK: Managing

    public func item(_ id: UUID?) -> ClipItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    public func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesFolder.appendingPathComponent($0) }
    }

    /// Moves an item back to the top, e.g. after pasting it again.
    public func markUsed(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        bump(at: i, sourceApp: nil)
    }

    public func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    public func delete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        removeFiles(of: items[i])
        items.remove(at: i)
        save()
    }

    /// Clears history but keeps pinned items.
    public func clearUnpinned() {
        items.filter { !$0.pinned }.forEach(removeFiles)
        items.removeAll { !$0.pinned }
        save()
    }

    /// Pinned items first, then newest first. Filtered by `query` if not empty.
    public func search(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = q.isEmpty ? items : items.filter {
            $0.text.localizedCaseInsensitiveContains(q)
                || $0.title.localizedCaseInsensitiveContains(q)
                || ($0.sourceApp?.localizedCaseInsensitiveContains(q) ?? false)
        }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }

    // MARK: Internals

    private func insert(_ item: ClipItem) {
        items.insert(item, at: 0)
        trim()
        save()
    }

    private func bump(at index: Int, sourceApp: String?) {
        var item = items.remove(at: index)
        item.date = now()
        if let sourceApp { item.sourceApp = sourceApp }
        items.insert(item, at: 0)
        save()
    }

    private func trim() {
        var unpinnedSeen = 0
        var kept: [ClipItem] = []
        for item in items {
            if item.pinned {
                kept.append(item)
            } else if unpinnedSeen < limit {
                unpinnedSeen += 1
                kept.append(item)
            } else {
                removeFiles(of: item)
            }
        }
        items = kept
    }

    private func removeFiles(of item: ClipItem) {
        if let url = imageURL(for: item) { try? fm.removeItem(at: url) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyFile),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        // Drop image entries whose file has gone missing.
        items = decoded.filter { item in
            guard let url = imageURL(for: item) else { return true }
            return fm.fileExists(atPath: url.path)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: historyFile, options: .atomic)
    }
}
