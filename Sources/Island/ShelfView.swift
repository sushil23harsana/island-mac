import AppKit
import IslandCore
import SwiftUI
import UniformTypeIdentifiers

/// Shelf tab: park files here, switch apps, then drag them out wherever they need to go.
struct ShelfView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var shelf: ShelfStore
    @State private var targeted = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .foregroundStyle(Theme.shelf)
                Text(shelf.items.isEmpty ? "Shelf is empty"
                     : shelf.items.count == 1 ? "1 file parked" : "\(shelf.items.count) files parked")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Drag files in, then drag them out anywhere")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                if !shelf.items.isEmpty {
                    SmallButton(title: "Clear") { shelf.clear() }
                        .help("Empties the shelf. Your files are not deleted.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .field()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shelf.items) { item in
                        ShelfCell(item: item) { shelf.remove(item.id) }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if shelf.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26))
                        Text("Drop files here, or straight onto the pill")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(targeted ? Theme.shelf : .white.opacity(0.3))
                }
            }
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.shelf, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .opacity(targeted ? 1 : 0)
            )
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            FileDrop.load(providers) { urls in _ = shelf.add(urls) }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}

private struct ShelfCell: View {
    let item: ShelfItem
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(hovered ? 0.09 : 0.04)))
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Remove from shelf (the file stays where it is)")
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Remove from Shelf", action: remove)
        }
        .help(item.path)
    }
}

/// Reads the file locations out of a drag-and-drop.
enum FileDrop {
    static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let box = URLBox()
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    box.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = box.urls
            MainActor.assumeIsolated { completion(urls) }
        }
    }

    /// Collects results from the providers' background callbacks.
    private final class URLBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URL] = []

        func append(_ url: URL) {
            lock.lock()
            storage.append(url)
            lock.unlock()
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
