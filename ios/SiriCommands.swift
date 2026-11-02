import AppIntents
import Foundation

@MainActor private enum SiriCommandRunner {
    static func send(_ command: WireSTARTConnection.Command) async -> Bool {
        let car = PhoneModel.shared.car
        guard !car.paused else { return false }
        car.cancelScheduledRelease()
        if !car.ready { car.reconnect() }
        for _ in 0..<60 {
            if car.ready { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard car.ready else { return false }
        defer { car.releaseAfterIdle() }
        return await withCheckedContinuation { continuation in
            var completed = false
            func finish(_ success: Bool) {
                guard !completed else { return }
                completed = true
                continuation.resume(returning: success)
            }
            guard car.send(command, completion: { finish($0) }) else { finish(false); return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !completed else { return }
                car.cancelPendingWrite()
                finish(false)
            }
        }
    }
}

struct LockVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock Vehicle"
    static var description = IntentDescription("Send a lock command with WireSTART.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if await SiriCommandRunner.send(.lock) { return .result(dialog: "Lock command sent.") }
        return .result(dialog: "Could not send the lock command. Check your SmartStart connection.")
    }
}

struct UnlockVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock Vehicle"
    static var description = IntentDescription("Send an unlock command with WireSTART.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        if await SiriCommandRunner.send(.unlock) { return .result(dialog: "Unlock command sent.") }
        return .result(dialog: "Could not send the unlock command. Check your SmartStart connection.")
    }
}

struct StartVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Vehicle"
    static var description = IntentDescription("Send a start command after confirmation.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation()
        if await SiriCommandRunner.send(.start) { return .result(dialog: "Start command sent.") }
        return .result(dialog: "Could not send the start command. Check your SmartStart connection.")
    }
}

struct OpenTrunkIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Trunk"
    static var description = IntentDescription("Send a trunk command after confirmation.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation()
        if await SiriCommandRunner.send(.trunk) { return .result(dialog: "Trunk command sent.") }
        return .result(dialog: "Could not send the trunk command. Check your SmartStart connection.")
    }
}

struct PanicVehicleIntent: AppIntent {
    static var title: LocalizedStringResource = "Vehicle Panic"
    static var description = IntentDescription("Send a panic command after confirmation.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation()
        if await SiriCommandRunner.send(.panic) { return .result(dialog: "Panic command sent.") }
        return .result(dialog: "Could not send the panic command. Check your SmartStart connection.")
    }
}

struct WireSTARTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LockVehicleIntent(), phrases: ["Lock my car with \(.applicationName)"], shortTitle: "Lock", systemImageName: "lock.fill")
        AppShortcut(intent: UnlockVehicleIntent(), phrases: ["Unlock my car with \(.applicationName)"], shortTitle: "Unlock", systemImageName: "lock.open.fill")
        AppShortcut(intent: StartVehicleIntent(), phrases: ["Start my car with \(.applicationName)"], shortTitle: "Start", systemImageName: "power")
        AppShortcut(intent: OpenTrunkIntent(), phrases: ["Open my trunk with \(.applicationName)"], shortTitle: "Trunk", systemImageName: "car.rear.fill")
        AppShortcut(intent: PanicVehicleIntent(), phrases: ["Activate panic with \(.applicationName)"], shortTitle: "Panic", systemImageName: "speaker.wave.3.fill")
    }
}
