@main struct AccessoryReplyTests {
    static func main() {
        precondition(AccessoryReply.message(for: "ERR", incomplete: true) == "Valet Mode On? Check vehicle.")
        precondition(AccessoryReply.message(for: "err", incomplete: false) == "Valet Mode On? Check vehicle.")
        precondition(AccessoryReply.message(for: "LOCK OK", incomplete: false) == "SmartStart acknowledged Lock.")
        precondition(!AccessoryReply.message(for: "LOCK OK", incomplete: true).contains("acknowledged"))
        precondition(!AccessoryReply.message(for: "ERROR", incomplete: false).contains("Valet"))
        print("Accessory reply checks passed")
    }
}
