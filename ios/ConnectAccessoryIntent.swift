import AppIntents
import Foundation

@available(iOS 17.0, *)
struct ConnectAccessoryIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Connect SmartStart"
    static var description = IntentDescription("Connect WireSTART to an available SmartStart accessory.")
    @MainActor func perform() async throws -> some IntentResult {
        #if WIRESTART_PHONE_APP
        let car = PhoneModel.shared.car
        guard car.connectKnownAccessory() else { return .result() }
        for _ in 0..<60 {
            if car.ready { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #endif
        return .result()
    }
}
