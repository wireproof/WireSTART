import Foundation

enum VehicleNames {
    static let limit = 20
    static func key(for accessoryName: String) -> String {
        accessoryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func limited(_ name: String) -> String {
        String(name.filter { !$0.isNewline }.prefix(limit))
    }
    static func displayName(for accessoryName: String, names: [String: String]) -> String {
        let stored = names[key(for: accessoryName)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? accessoryName : stored
    }
}
