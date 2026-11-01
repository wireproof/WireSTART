enum WidgetConfirmation {
    enum Decision { case cancel, stage, send }
    static func decide(command: String, requiresConfirmation: Bool, pending: String?, expiresAt: Double, now: Double) -> Decision {
        if command == "cancel" { return .cancel }
        guard requiresConfirmation else { return .send }
        return pending == command && now < expiresAt ? .send : .stage
    }
}
