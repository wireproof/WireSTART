import Foundation

enum AccessoryReply {
    static func message(for value: String, incomplete: Bool) -> String {
        let text = String(value.prefix(120))
        switch text.uppercased() {
        case "ERR": return "Valet Mode Detected"
        case "LOCK OK" where !incomplete: return "Vehicle Locked"
        case "UNLOCK OK" where !incomplete: return "Vehicle Unlocked"
        case "START OK" where !incomplete: return "SmartStart acknowledged Start."
        case "STOP OK" where !incomplete: return "SmartStart acknowledged Stop."
        default:
            return incomplete ? "Accessory sent ‘\(text)’ (incomplete reply). Check vehicle." : "SmartStart replied: \(text)"
        }
    }
}
