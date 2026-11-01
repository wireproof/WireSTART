import Foundation

struct ResponseFramer {
    private var buffer = Data()
    private let maximumBytes = 4096

    mutating func append(_ bytes: Data) -> [String] {
        buffer.append(bytes)
        guard buffer.count <= maximumBytes else { buffer.removeAll(); return [] }
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0a) {
            let frame = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let value = String(data: frame, encoding: .utf8) else { continue }
            let line = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
