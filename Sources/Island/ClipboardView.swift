import AppKit
import IslandCore
import SwiftUI

/// Clipboard tab: searchable history on the left, a preview of the selected item on the right.
struct ClipboardView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var monitor: ClipboardMonitor
    @EnvironmentObject private var history: ClipboardHistory

    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selection: UUID?
    @State private var confirmClear = false
    @State private var canAutoPaste = false

    private var visibleItems: [ClipItem] { history.search(query) }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            HStack(spacing: 0) {
                list
                    .frame(width: 290)
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                preview
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onAppear {
            selection = visibleItems.first?.id
            canAutoPaste = monitor.canAutoPaste
            focusSearchSoon()
        }
        .onChange(of: query) { selection = visibleItems.first?.id }
        .onReceive(controller.commands) { handle($0) }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                TextField("Search clipboard history", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                Text("\(visibleItems.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))

            if confirmClear {
                Text("Clear unpinned?")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                SmallButton(title: "Clear", tint: .red) {
                    history.clearUnpinned()
                    selection = visibleItems.first?.id
                    confirmClear = false
                }
                SmallButton(title: "Cancel") { confirmClear = false }
            } else {
                IconButton(symbol: monitor.isPaused ? "play.circle" : "pause.circle",
                           help: monitor.isPaused ? "Resume recording copies" : "Pause recording copies",
                           tint: monitor.isPaused ? .orange : nil) {
                    monitor.isPaused.toggle()
                }
                IconButton(symbol: "trash", help: "Clear history (pinned items stay)") {
                    confirmClear = true
                }
                .disabled(history.items.allSatisfy(\.pinned))
            }
        }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleItems) { item in
                            ClipRow(item: item, selected: item.id == selection, history: history)
                                .id(item.id)
                                .onTapGesture(count: 2) { controller.paste(item) }
                                .simultaneousGesture(TapGesture().onEnded { selection = item.id })
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }
            .overlay { emptyState }

            footer
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if visibleItems.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: monitor.isPaused ? "pause.circle" : "doc.on.clipboard")
                    .font(.system(size: 22))
                Text(!query.isEmpty ? "No matches"
                     : monitor.isPaused ? "Recording is paused" : "Copy something and it shows up here")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.35))
            .padding()
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if canAutoPaste {
                Text("⏎ paste · ⌘P pin · ⌘⌫ delete")
            } else {
                Text("⏎ copies")
                Button("Turn on auto-paste") {
                    monitor.requestAutoPastePermission()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.yellow.opacity(0.85))
                .help("Lets Island press ⌘V for you (Settings → Privacy & Security → Accessibility)")
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("Paste") { controller.paste(item) }
        Button(item.pinned ? "Unpin" : "Pin") { history.togglePin(item.id) }
        if item.kind == .files {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) })
            }
        }
        Divider()
        Button("Delete", role: .destructive) { delete(item.id) }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if let item = history.item(selection) {
            VStack(alignment: .leading, spacing: 10) {
                Text(metadata(item))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                previewBody(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack(spacing: 8) {
                    Spacer()
                    IconButton(symbol: item.pinned ? "pin.fill" : "pin", help: item.pinned ? "Unpin (⌘P)" : "Pin (⌘P)",
                               tint: item.pinned ? .yellow : nil) {
                        history.togglePin(item.id)
                    }
                    IconButton(symbol: "trash", help: "Delete (⌘⌫)") { delete(item.id) }
                    Button { controller.paste(item) } label: {
                        Label(canAutoPaste ? "Paste" : "Copy", systemImage: "arrow.turn.down.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(.yellow))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        } else {
            Text("Nothing selected")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func previewBody(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let url = history.imageURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.filePaths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((path as NSString).lastPathComponent)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text((path as NSString).deletingLastPathComponent)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
        case .text:
            if let rgb = item.hexColor {
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                        .frame(height: 120)
                    Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    Text("rgb(\(Int(rgb.r * 255)), \(Int(rgb.g * 255)), \(Int(rgb.b * 255)))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .textSelection(.enabled)
                }
            } else {
                ScrollView {
                    Text(item.text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if item.isLink, let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Button("Open in browser") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow.opacity(0.85))
                }
            }
        }
    }

    private func metadata(_ item: ClipItem) -> String {
        var parts: [String] = []
        if let app = item.sourceApp { parts.append(app) }
        parts.append(item.date.formatted(.relative(presentation: .named)))
        if item.kind == .text { parts.append("\(item.text.count) chars") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func handle(_ command: IslandController.Command) {
        switch command {
        case .focusCapture, .focusSearch:
            focusSearchSoon()
        case .moveSelection(let delta):
            let items = visibleItems
            guard !items.isEmpty else { return }
            let current = items.firstIndex { $0.id == selection } ?? -1
            let next = min(max(current + delta, 0), items.count - 1)
            selection = items[next].id
        case .pasteSelection:
            if let item = history.item(selection) { controller.paste(item) }
        case .togglePinSelection:
            if let selection { history.togglePin(selection) }
        case .deleteSelection:
            if let selection { delete(selection) }
        default:
            break
        }
    }

    private func delete(_ id: UUID) {
        let items = visibleItems
        let index = items.firstIndex { $0.id == id } ?? 0
        history.delete(id)
        if selection == id {
            let remaining = visibleItems
            selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }

    private func focusSearchSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
    }
}

// MARK: - Row

private struct ClipRow: View {
    let item: ClipItem
    let selected: Bool
    let history: ClipboardHistory

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "(whitespace)" : item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.yellow.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let when = item.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return [item.sourceApp, when].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let url = history.imageURL(for: item), let thumb = Thumbnails.image(at: url) {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                symbol("photo")
            }
        case .files:
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.filePaths.first ?? "/"))
                .resizable()
        case .text:
            if let rgb = item.hexColor {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2)))
                    .padding(3)
            } else {
                symbol(item.isLink ? "link" : "text.alignleft")
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
    }
}

/// Small in-memory cache so image rows don't re-decode full PNGs while scrolling.
@MainActor
private enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - Small controls

private struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint ?? .white.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct SmallButton: View {
    let title: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? .white.opacity(0.8))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
