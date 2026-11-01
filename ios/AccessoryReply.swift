import Foundation

enum AccessoryReply {
    static func message(for value: String, incomplete: Bool) -> String {
        let text = String(value.prefix(120))
        switch text.uppercased() {
        case "ERR": return "Valet Mode On? Check vehicle."
        case "LOCK OK" where !incomplete: return "SmartStart acknowledged Lock."
        case "UNLOCK OK" where !incomplete: return "SmartStart acknowledged Unlock."
        case "START OK" where !incomplete: return "SmartStart acknowledged Start."
        case "STOP OK" where !incomplete: return "SmartStart acknowledged Stop."
        default:
            return incomplete ? "Accessory sent ‘\(text)’ (incomplete reply). Check vehicle." : "SmartStart replied: \(text)"
        }
    }
}
