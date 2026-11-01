import Foundation
import WatchConnectivity
import UIKit

@MainActor final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    private let car: WireSTARTConnection
    private var inFlight = false
    init(car: WireSTARTConnection) {
        self.car = car
        super.init()
        car.onAccessoryError = { [weak self] code in
            guard let self, WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
            self.record("Forwarding accessory error to Watch")
            WCSession.default.sendMessage(["accessoryError": code], replyHandler: nil, errorHandler: nil)
        }
        car.onConnectionChange = { [weak self] _ in self?.publishConnectionState() }
        car.onSignalFlash = { color in
            guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
            WCSession.default.sendMessage(["signalFlash": color], replyHandler: nil, errorHandler: nil)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            record("Watch session activation requested")
        }
    }
    private func publishConnectionState() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["accessoryReady": car.ready, "vehicleState": car.vehicleState.rawValue])
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
        Task { @MainActor in self.record(error == nil ? "Watch session activated: \(activationState.rawValue)" : "Watch session activation failed"); self.publishConnectionState() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let raw = message["command"] as? String, let sentAt = message["sentAt"] as? Double else {
            replyHandler(["result": "Update Watch app"]); return
        }
        Task { @MainActor in
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "WireSTART Watch request")
            defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
            let state: String
            switch UIApplication.shared.applicationState {
            case .active: state = "active"
            case .inactive: state = "inactive"
            case .background: state = "background"
            @unknown default: state = "unknown"
            }
            self.record("Received Watch request: \(raw); iPhone app: \(state)")
            let result = await self.perform(raw, sentAt: sentAt)
            self.record("Watch request result: \(result)")
            replyHandler(["result": result])
        }
    }
    private func perform(_ raw: String, sentAt: Double) async -> String {
        guard let command = WireSTARTConnection.Command(rawValue: raw) else { return "Unsupported command" }
        guard abs(Date().timeIntervalSince1970 - sentAt) < 8 else { return "Request expired" }
        guard !inFlight else { return "iPhone is busy" }
        guard !car.paused else { return "Connect WireSTART on iPhone" }
        inFlight = true
        car.cancelScheduledRelease()
        defer {
            inFlight = false
            if UIApplication.shared.applicationState != .active { car.releaseAfterIdle(minimumDelay: 8) }
        }
        if !car.ready { car.reconnect() }
        for _ in 0..<60 {
            if car.ready { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard car.ready else { return "SmartStart unavailable" }
        guard abs(Date().timeIntervalSince1970 - sentAt) < 8 else { return "Request expired" }
        return await withCheckedContinuation { continuation in
            var completed = false
            func finish(_ result: String) {
                guard !completed else { return }
                completed = true
                continuation.resume(returning: result)
            }
            guard car.send(command, completion: { success in
                finish(success ? "Command sent" : "Send unconfirmed. Check vehicle.")
            }) else { finish("iPhone is busy"); return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !completed else { return }
                car.cancelPendingWrite()
                finish("Send unconfirmed. Check vehicle.")
            }
        }
    }
}
