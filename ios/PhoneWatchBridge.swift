import Foundation
import WatchConnectivity
import UIKit

@MainActor final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    private let car: ViperConnection
    private var inFlight = false
    private var closeTask: Task<Void, Never>?
    init(car: ViperConnection) {
        self.car = car
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            record("Watch session activation requested")
        }
    }
    private func record(_ message: String) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = directory.appendingPathComponent("watch-relay-log.json")
        var entries = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([[String: String]].self, from: $0) } ?? []
        entries.append(["time": ISO8601DateFormatter().string(from: Date()), "event": message])
        if entries.count > 50 { entries.removeFirst(entries.count - 50) }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.record(error == nil ? "Watch session activated: \(activationState.rawValue)" : "Watch session activation failed") }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let raw = message["command"] as? String, let sentAt = message["sentAt"] as? Double else {
            replyHandler(["result": "Update Watch app"]); return
        }
        Task { @MainActor in
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Viper Watch request")
            defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
            self.record("Received Watch request: \(raw)")
            let result = await self.perform(raw, sentAt: sentAt)
            self.record("Watch request result: \(result)")
            replyHandler(["result": result])
        }
    }
    private func perform(_ raw: String, sentAt: Double) async -> String {
        guard let command = ViperConnection.Command(rawValue: raw) else { return "Unsupported command" }
        guard abs(Date().timeIntervalSince1970 - sentAt) < 8 else { return "Request expired" }
        guard !inFlight else { return "iPhone is busy" }
        guard !car.paused else { return "Connect Viper on iPhone" }
        inFlight = true
        closeTask?.cancel()
        defer {
            inFlight = false
            closeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled, UIApplication.shared.applicationState != .active else { return }
                self?.car.suspendForWidget()
            }
        }
        if !car.ready { car.reconnect() }
        for _ in 0..<60 {
            if car.ready { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard car.ready else { return "SmartStart unavailable" }
        guard abs(Date().timeIntervalSince1970 - sentAt) < 8 else { return "Request expired" }
        guard car.send(command) else { return "iPhone is busy" }
        return "iPhone accepted. Check vehicle."
    }
}
