import AppKit
import IslandCore
import Vision

/// "Grab text": drag over any part of the screen and get the text in it, read on this Mac.
enum TextGrabber {
    enum Outcome {
        case text(String)
        case noText
        case cancelled
    }

    /// Reads the text in an image using the system's on-device text recognition.
    static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Lets the user drag a region (the system's own screenshot crosshair), then reads it.
    /// macOS asks for Screen Recording permission the first time.
    static func grab(completion: @escaping @MainActor (Outcome) -> Void) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("island-grab-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", file.path] // interactive selection, no shutter sound
        process.terminationHandler = { _ in
            defer { try? FileManager.default.removeItem(at: file) }
            // No file means the user pressed Esc.
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                Task { @MainActor in completion(.cancelled) }
                return
            }
            let text = recognizeText(in: image)
            Task { @MainActor in completion(text.isEmpty ? .noText : .text(text)) }
        }
        do {
            try process.run()
        } catch {
            Task { @MainActor in completion(.cancelled) }
        }
    }
}

/// The list of programs listening on network ports, for the Ports tab.
@MainActor
final class PortsModel: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var isLoading = false

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let output = Self.runLsof()
            let parsed = PortScanner.parse(output)
            await MainActor.run {
                self.ports = parsed
                self.isLoading = false
            }
        }
    }

    /// Asks the program to quit (the same polite signal as `kill <pid>`), then refreshes the list.
    func stop(_ port: ListeningPort) {
        kill(port.pid, SIGTERM)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            refresh()
        }
    }

    nonisolated private static func runLsof() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = PortScanner.lsofArguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
