@main struct WidgetConfirmationTests {
    static func main() {
        func decision(_ cmd: String, _ needs: Bool, _ pending: String?, _ expiry: Double, _ now: Double) -> WidgetConfirmation.Decision {
            WidgetConfirmation.decide(command: cmd, requiresConfirmation: needs, pending: pending, expiresAt: expiry, now: now)
        }
        precondition(decision("lock", false, nil, 0, 10) == .send)
        precondition(decision("trunk", true, nil, 0, 10) == .stage)
        precondition(decision("trunk", true, "trunk", 20, 10) == .send)
        precondition(decision("trunk", true, "trunk", 10, 10) == .stage)
        precondition(decision("panic", true, "trunk", 20, 10) == .stage)
        precondition(decision("cancel", false, "panic", 20, 10) == .cancel)
        print("Widget confirmation checks passed")
    }
}
