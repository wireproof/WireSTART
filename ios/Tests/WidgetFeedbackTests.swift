import Foundation
@main struct WidgetFeedbackTests {
    static func main() {
        let suite = "wirestart.widget-feedback-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_000)
        precondition(WidgetFeedback.current(defaults: defaults, now: now) == nil)
        WidgetFeedback.record("Valet", defaults: defaults, now: now)
        precondition(defaults.bool(forKey: "valetDetected"))
        WidgetFeedback.record("Sent", defaults: defaults, now: now)
        precondition(defaults.bool(forKey: "valetDetected"))
        WidgetFeedback.record("Locked", defaults: defaults, now: now)
        precondition(!defaults.bool(forKey: "valetDetected"))
        precondition(WidgetFeedback.current(defaults: defaults, now: now)?.status == "Locked")
        WidgetFeedback.record("Valet", defaults: defaults, now: now)
        WidgetFeedback.record("Unlocked", defaults: defaults, now: now.addingTimeInterval(1))
        precondition(!defaults.bool(forKey: "valetDetected"))
        precondition(WidgetFeedback.current(defaults: defaults, now: now.addingTimeInterval(2))?.status == "Unlocked")
        precondition(WidgetFeedback.current(defaults: defaults, now: now.addingTimeInterval(32)) == nil)
        print("Shared widget feedback checks passed")
    }
}
