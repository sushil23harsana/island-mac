import AppKit
import IslandCore
import SwiftUI

/// Notes tab: quick capture bar on top, note list + editor below.
struct NotesView: View {
    @EnvironmentObject private var controller: IslandController
    @EnvironmentObject private var store: NotesStore

    private enum Field: Hashable { case capture, search, editor }
    @FocusState private var focus: Field?

    @State private var capture = ""
    @State private var query = ""
    @State private var selection: URL?
    @State private var draft = ""

    private var visibleNotes: [Note] { store.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            captureBar
                .padding(.bottom, 10)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 200)
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                editor
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onAppear {
            if store.note(selection) == nil { selection = store.notes.first?.id }
            loadDraft()
            focusSoon(.capture)
        }
        .onChange(of: selection) { loadDraft() }
        .onChange(of: draft) { _, newValue in
            if let selection { store.save(selection, body: newValue) }
        }
        .onReceive(controller.commands) { handle($0) }
    }

    // MARK: Capture

    private var captureBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
            TextField("Capture a thought…", text: $capture)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focus, equals: .capture)
                .onSubmit(saveCapture)
            Text(capture.isEmpty ? "esc to close" : "⏎ save · ⌘⏎ save & close")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focus, equals: .search)
                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("New note (⌘N)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(visibleNotes) { note in
                        NoteRow(note: note, selected: note.id == selection)
                            .onTapGesture { selection = note.id }
                            .contextMenu {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([note.id])
                                }
                                Button("Move to Trash", role: .destructive) { trash(note.id) }
                            }
                    }
                }
            }
            .scrollIndicators(.never)
            .overlay {
                if visibleNotes.isEmpty {
                    Text(query.isEmpty ? "No notes yet" : "No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            HStack {
                Text(store.notes.count == 1 ? "1 note" : "\(store.notes.count) notes")
                Spacer()
                Button {
                    NSWorkspace.shared.open(store.folder)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Open notes folder")
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(10)
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let note = store.note(selection) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(note.modified, format: .dateTime.day().month().hour().minute())
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Button { trash(note.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .help("Move to Trash")
                }
                TextEditor(text: $draft)
                    .font(.system(size: 13.5))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focus, equals: .editor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 28))
                Text("Type above to capture, or ⌘N for a new note")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Actions

    private func handle(_ command: IslandController.Command) {
        switch command {
        case .focusCapture: focusSoon(.capture)
        case .focusSearch: focus = .search
        case .newNote: newNote()
        case .saveCaptureAndClose:
            saveCapture()
            controller.collapse(restoreFocus: true)
        case .moveSelection, .pasteSelection, .togglePinSelection, .deleteSelection:
            break // clipboard-only commands
        }
    }

    private func saveCapture() {
        let text = capture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let note = store.create(body: text) else { return }
        capture = ""
        query = ""
        selection = note.id
    }

    private func newNote() {
        guard let note = store.create() else { return }
        query = ""
        selection = note.id
        focusSoon(.editor)
    }

    private func trash(_ id: URL) {
        let index = visibleNotes.firstIndex { $0.id == id } ?? 0
        store.trash(id)
        if selection == id {
            let remaining = visibleNotes
            selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }

    private func loadDraft() {
        draft = store.note(selection)?.body ?? ""
    }

    /// Focus after the window has become key, otherwise the request is dropped.
    private func focusSoon(_ field: Field) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = field }
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(note.modified, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                if !note.preview.isEmpty {
                    Text("·")
                    Text(note.preview).lineLimit(1)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.yellow.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
    }
}
