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
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let raw = message["command"] as? String else { replyHandler(["result": "Invalid command"]); return }
        Task { @MainActor in
            let result = await self.perform(raw)
            replyHandler(["result": result])
        }
    }
    private func perform(_ raw: String) async -> String {
        guard let command = ViperConnection.Command(rawValue: raw) else { return "Unsupported command" }
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
        for _ in 0..<40 {
            if car.ready { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard car.ready else { return "SmartStart unavailable" }
        guard car.send(command) else { return "iPhone is busy" }
        return "iPhone accepted. Check vehicle."
    }
}
