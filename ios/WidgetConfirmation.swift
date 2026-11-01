enum WidgetConfirmation {
    enum Decision { case cancel, stage, send }
    static func decide(command: String, requiresConfirmation: Bool, pending: String?, expiresAt: Double, now: Double) -> Decision {
        if command == "cancel" { return .cancel }
        guard requiresConfirmation else { return .send }
        return pending == command && now < expiresAt ? .send : .stage
    }
}

import Foundation

enum WidgetReply {
    static func status(for reply: String, command: String) -> String? {
        let line = reply.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if line == "ERR" { return "Valet" }
        switch (command, line) {
        case ("lock", "LOCK OK"): return "Locked"
        case ("unlock", "UNLOCK OK"): return "Unlocked"
        case ("start", "START OK"), ("start", "REMOTE START OK"): return "Remote Start"
        case ("start", "STOP OK"): return "Stopped"
        case ("trunk", "TRUNK OK"): return "Trunk Opened"
        case ("panic", "PANIC OK"): return "Panic"
        case ("start", "START ERROR"), ("start", "START FAIL"), ("start", "START FAILED"), ("start", "REMOTE START ERROR"): return "Start error"
        case ("trunk", "TRUNK ERROR"), ("trunk", "TRUNK FAIL"), ("trunk", "TRUNK FAILED"): return "Trunk error"
        default: return nil
        }
    }
}
