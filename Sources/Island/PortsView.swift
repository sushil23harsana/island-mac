import IslandCore
import SwiftUI

/// Ports tab: which programs are listening on which port, with a button to stop them.
/// (The classic "something is already using port 3000" fix.)
struct PortsView: View {
    @EnvironmentObject private var model: PortsModel
    /// The row whose Stop button was clicked once and is waiting for a confirming click.
    @State private var confirming: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(Theme.ports)
                Text(model.ports.isEmpty ? "Nothing is listening"
                     : model.ports.count == 1 ? "1 program listening" : "\(model.ports.count) programs listening")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("TCP ports opened by your apps")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: "Refresh") { model.refresh() }
                    .opacity(model.isLoading ? 0.4 : 1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .field()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.ports) { port in
                        row(port)
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if model.ports.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 24))
                        Text(model.isLoading ? "Looking…" : "Start a dev server and it shows up here")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.3))
                }
            }
            .card()
        }
        .onAppear { model.refresh() }
    }

    private func row(_ port: ListeningPort) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: ":\(port.port)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ports)
                .frame(width: 68, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(port.command)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(verbatim: [port.hint, "pid \(port.pid)", port.isLocalOnly ? "this Mac only" : "open to the network"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if confirming == port.id {
                SmallButton(title: "Stop it", tint: Theme.alert) {
                    confirming = nil
                    model.stop(port)
                }
                SmallButton(title: "Cancel") { confirming = nil }
            } else {
                SmallButton(title: "Stop") { confirming = port.id }
                    .help("Ask \(port.command) to quit, which frees port \(port.port)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .rowBackground(selected: confirming == port.id, accent: Theme.alert)
    }
}
