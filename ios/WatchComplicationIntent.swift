import AppIntents
import Foundation

enum ComplicationAction: String, AppEnum {
    case lock, unlock, start, trunk, panic
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Vehicle command")
    static var caseDisplayRepresentations: [ComplicationAction: DisplayRepresentation] = [
        .lock: "Lock", .unlock: "Unlock", .start: "Remote Start", .trunk: "Trunk", .panic: "Panic"
    ]
    var needsConfirmation: Bool { self == .start || self == .trunk || self == .panic }
}

struct WatchComplicationIntent: AppIntent {
    static var title: LocalizedStringResource = "WireSTART Watch Command"
    static var description = IntentDescription("Send a command through your iPhone.")
    static var openAppWhenRun: Bool = true
    @Parameter(title: "Command") var action: ComplicationAction
    init() { action = .lock }
    init(_ action: ComplicationAction) { self.action = action }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if action.needsConfirmation { try await requestConfirmation() }
        #if WIRESTART_WATCH_APP
        guard let command = WatchCommand(rawValue: action.rawValue) else { return .result(dialog: "Command unavailable.") }
        let remote = WatchRemote.shared
        for _ in 0..<50 {
            if remote.reachable { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard remote.reachable else { return .result(dialog: "iPhone unavailable.") }
        remote.send(command, source: "complication")
        return .result(dialog: "Command requested.")
        #else
        return .result(dialog: "Open WireSTART on your Watch to send the command.")
        #endif
    }
}
