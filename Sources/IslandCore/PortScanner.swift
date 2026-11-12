import Foundation

/// A program on this Mac that is listening for network connections on a TCP port.
public struct ListeningPort: Identifiable, Equatable, Hashable, Sendable {
    public let pid: Int32
    public let command: String
    public let port: Int
    /// "*" (all interfaces), "127.0.0.1", "[::1]"…
    public let address: String

    public var id: String { "\(pid):\(port)" }

    /// Only reachable from this Mac.
    public var isLocalOnly: Bool { address == "127.0.0.1" || address == "[::1]" || address == "localhost" }

    /// A guess at what usually runs on this port.
    public var hint: String? { PortScanner.wellKnown[port] }
}

public enum PortScanner {
    /// The command whose output `parse` understands.
    public static let lsofArguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]

    static let wellKnown: [Int: String] = [
        3000: "Node / React / Rails", 3001: "Node", 4200: "Angular", 4321: "Astro",
        5000: "Flask", 5173: "Vite", 5432: "PostgreSQL", 5500: "Live Server",
        6379: "Redis", 8000: "Django / Python", 8080: "Web server", 8081: "Metro / React Native",
        8888: "Jupyter", 9000: "PHP / SonarQube", 27017: "MongoDB", 3306: "MySQL", 1234: "Parcel",
    ]

    /// Parses `lsof -F pcn` output: a `p<pid>` line, a `c<command>` line, then `n<address>:<port>` lines.
    public static func parse(_ output: String) -> [ListeningPort] {
        var result: [ListeningPort] = []
        var seen = Set<String>()
        var pid: Int32?
        var command = ""

        for line in output.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = value.replacingOccurrences(of: "\\x20", with: " ")
            case "n":
                guard let pid, let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                let entry = ListeningPort(pid: pid, command: command, port: port,
                                          address: String(value[..<colon]))
                // The same port often appears twice (IPv4 and IPv6); keep one row per process and port.
                if seen.insert(entry.id).inserted { result.append(entry) }
            default:
                continue
            }
        }
        return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }
}
