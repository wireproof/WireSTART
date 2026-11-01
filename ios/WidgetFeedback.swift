import Foundation

enum WidgetFeedback {
    private static let key = "sharedWidgetFeedback"
    static let lifetime: TimeInterval = 30

    static func record(_ status: String, defaults: UserDefaults? = UserDefaults(suiteName: "group.com.wireproof.wirestart"), now: Date = Date()) {
        defaults?.set(["status": status, "expires": now.timeIntervalSince1970 + lifetime], forKey: key)
    }
    static func current(defaults: UserDefaults? = UserDefaults(suiteName: "group.com.wireproof.wirestart"), now: Date = Date()) -> (status: String, expires: TimeInterval)? {
        guard let record = defaults?.dictionary(forKey: key), let status = record["status"] as? String,
              let expires = record["expires"] as? TimeInterval, expires > now.timeIntervalSince1970 else { return nil }
        return (status, expires)
    }
}
