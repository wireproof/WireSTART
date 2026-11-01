import Foundation

struct ResponseFramer {
    private var buffer = Data()
    private let maximumBytes = 4096

    var partialText: String? {
        guard !buffer.isEmpty, buffer.count <= 120,
              buffer.allSatisfy({ (0x20...0x7e).contains($0) }),
              let text = String(data: buffer, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

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
