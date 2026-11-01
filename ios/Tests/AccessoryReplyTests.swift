@main struct AccessoryReplyTests {
    static func main() {
        precondition(AccessoryReply.message(for: "ERR", incomplete: true) == "Valet Mode Detected")
        precondition(AccessoryReply.message(for: "err", incomplete: false) == "Valet Mode Detected")
        precondition(AccessoryReply.message(for: "LOCK OK", incomplete: false) == "Vehicle Locked")
        precondition(AccessoryReply.message(for: "UNLOCK OK", incomplete: false) == "Vehicle Unlocked")
        precondition(AccessoryReply.message(for: "LOCK OK", incomplete: true) != "Vehicle Locked")
        precondition(!AccessoryReply.message(for: "ERROR", incomplete: false).contains("Valet"))
        print("Accessory reply checks passed")
    }
}
