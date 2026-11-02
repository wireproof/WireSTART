import WidgetKit
import SwiftUI
import AppIntents
import ExternalAccessory
import UIKit

private let green = Color(red: 0.63, green: 0.94, blue: 0.24)
private func widgetBackground(_ scheme: ColorScheme) -> some View {
    LinearGradient(colors: scheme == .dark
        ? [Color(red: 0.23, green: 0.26, blue: 0.31), Color(red: 0.11, green: 0.14, blue: 0.19)]
        : [Color(red: 0.27, green: 0.30, blue: 0.35), Color(red: 0.14, green: 0.17, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
}
@ViewBuilder private func widgetIcon(_ name: String) -> some View {
    if #available(iOS 18.0, *) { Image(systemName: name).widgetAccentedRenderingMode(.fullColor) }
    else { Image(systemName: name) }
}

private func signalIcon(_ scheme: ColorScheme, connected: Bool, valet: Bool, sending: Bool) -> some View {
    return widgetIcon("antenna.radiowaves.left.and.right")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(sending ? Color.blue : (connected ? green : Color.gray))
        .symbolEffect(.pulse, options: .repeating.speed(3), value: sending)
        .shadow(color: connected && scheme == .light ? Color.black.opacity(0.65) : .clear, radius: 0.8, x: 0, y: 0.5)
        .accessibilityLabel(connected ? "SmartStart available at last update" : "SmartStart unavailable at last update")
}

private func widgetStatus(_ status: String, scheme: ColorScheme, connected: Bool, reported: Bool, valet: Bool, fontSize: CGFloat = 9) -> some View {
    let text: String
    let color: Color
    let displayStatus = !reported || !connected ? "" : (valet ? "Valet" : status)
    switch displayStatus {
    case "Locked", "Running": text = displayStatus; color = scheme == .dark ? green : Color(red: 0.16, green: 0.48, blue: 0.12)
    case "Connected": text = displayStatus; color = green
    case "Unlocked", "Panic", "Trunk error", "Start error", "Send failed", "Disconnected", "Not Connected", "NOT CONNECTED", "SESSION UNAVAILABLE": text = displayStatus == "NOT CONNECTED" ? "Not Connected" : displayStatus; color = .red
    case "Trunk Opened": text = displayStatus; color = scheme == .dark ? Color(red: 0.35, green: 0.72, blue: 1) : Color(red: 0.05, green: 0.34, blue: 0.65)
    case "Valet": text = displayStatus; color = scheme == .dark ? .white : .black
    case "Unconfirmed", "Stopped": text = displayStatus; color = .gray
    case "Sent", "SENDING", "READY", "":
        text = ""; color = green
    default: text = ""; color = .gray
    }
    return Text(text.isEmpty ? "WIRESTART" : text)
        .tracking(text.isEmpty || text == "Valet" ? 1.1 : 0)
        .font(.system(size: fontSize, weight: .bold))
        .foregroundStyle(text.isEmpty ? (scheme == .dark ? Color.white : Color.black) : color)
        .shadow(color: text == "Connected" && scheme == .light ? Color.black.opacity(0.65) : .clear, radius: 0.8, x: 0, y: 0.5)
        .lineLimit(1).minimumScaleFactor(0.7)
}

private struct ConnectAccessoryButton: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    private func buttonImage() -> UIImage {
        let size = CGSize(width: 100, height: 36)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let fill = renderingMode == .fullColor ? UIColor(red: 0.63, green: 0.94, blue: 0.24, alpha: 1) : UIColor.white
            fill.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: UIColor.black]
            let text = "Connect" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
    }
    var body: some View {
        Button(intent: ConnectAccessoryIntent()) {
            if #available(iOS 18.0, *) {
                Image(uiImage: buttonImage()).renderingMode(.original).resizable()
                    .widgetAccentedRenderingMode(.fullColor).frame(width: 100, height: 36)
            } else {
                Text("Connect").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(green, in: Capsule())
            }
        }.buttonStyle(.plain).accessibilityLabel("Connect SmartStart")
    }
}

private enum WidgetState {
    static let defaults = UserDefaults.standard
    static var reported: Bool { UserDefaults(suiteName: "group.com.wireproof.wirestart")?.bool(forKey: "appReported") ?? false }
    static var valet: Bool { UserDefaults(suiteName: "group.com.wireproof.wirestart")?.bool(forKey: "valetDetected") ?? false }
    static func connected(at date: Date) -> Bool {
        guard let shared = UserDefaults(suiteName: "group.com.wireproof.wirestart") else { return false }
        if shared.bool(forKey: "appSessionReady") { return true }
        let recentReply = shared.double(forKey: "widgetResponseAt") + 30 > date.timeIntervalSince1970
        return recentReply && EAAccessoryManager.shared().connectedAccessories.contains { $0.isConnected && $0.protocolStrings.contains("com.directed.smartstartbt") }
    }
    static var pending: String? {
        guard let command = defaults.string(forKey: "pending"), defaults.double(forKey: "pendingUntil") > Date().timeIntervalSince1970 else { return nil }
        return command
    }
    static var status: String {
        let value = defaults.string(forKey: "status") ?? "READY"
        if value.hasPrefix("CONFIRM "), pending != nil { return value }
        if value == "SENDING", defaults.double(forKey: "statusUntil") > Date().timeIntervalSince1970 { return value }
        if let shared = WidgetFeedback.current() { return shared.status }
        return "READY"
    }
    static func clear() { defaults.removeObject(forKey: "pending"); defaults.removeObject(forKey: "pendingUntil") }
}

enum RemoteAction: String, AppEnum {
    case lock, unlock, trunk, start, panic, aux1, aux2, cancel
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Remote command")
    static var caseDisplayRepresentations: [RemoteAction: DisplayRepresentation] = [
        .lock: "Lock", .unlock: "Unlock", .trunk: "Trunk", .start: "Start", .panic: "Panic", .aux1: "Aux 1", .aux2: "Aux 2", .cancel: "Cancel"
    ]
    var iconColor: Color {
        switch self {
        case .unlock, .panic: return .red
        case .trunk: return Color(red: 0.35, green: 0.72, blue: 1.0)
        case .aux1, .aux2: return Color(red: 0.72, green: 0.76, blue: 0.79)
        default: return green
        }
    }
    var needsConfirmation: Bool { self == .trunk || self == .start || self == .panic }
    var label: String {
        switch self { case .start: return "Start"; case .aux1: return "Aux 1"; case .aux2: return "Aux 2"; default: return rawValue.capitalized }
    }
}

struct RemoteIntent: AppIntent {
    static var title: LocalizedStringResource = "WireSTART Remote"
    static var description = IntentDescription("Send a command to your SmartStart accessory.")
    @Parameter(title: "Command") var action: RemoteAction
    init() { action = .lock }
    init(_ action: RemoteAction) { self.action = action }
    @MainActor func perform() async throws -> some IntentResult {
        WidgetState.defaults.set(action.rawValue, forKey: "lastAction")
        let decision = WidgetConfirmation.decide(command: action.rawValue, requiresConfirmation: action.needsConfirmation,
            pending: WidgetState.defaults.string(forKey: "pending"), expiresAt: WidgetState.defaults.double(forKey: "pendingUntil"), now: Date().timeIntervalSince1970)
        if decision == .cancel { WidgetState.clear(); WidgetState.defaults.set("CANCELLED", forKey: "status"); WidgetCenter.shared.reloadAllTimelines(); return .result() }
        if decision == .stage {
            WidgetState.defaults.set(action.rawValue, forKey: "pending")
            WidgetState.defaults.set(Date().timeIntervalSince1970 + 20, forKey: "pendingUntil")
            WidgetState.defaults.set("CONFIRM \(action.label.uppercased())", forKey: "status")
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        WidgetState.clear()
        UserDefaults(suiteName: "group.com.wireproof.wirestart")?.set(Date().timeIntervalSince1970, forKey: "widgetActivityAt")
        WidgetState.defaults.set("SENDING", forKey: "status")
        WidgetState.defaults.set(Date().timeIntervalSince1970 + 15, forKey: "statusUntil")
        WidgetCenter.shared.reloadAllTimelines()
        let result = await WidgetSession().send(action.rawValue)
        WidgetState.defaults.set(result, forKey: "status")
        WidgetState.defaults.set(Date().timeIntervalSince1970 + 30, forKey: "statusUntil")
        WidgetFeedback.record(result)
        return .result()
    }
}

@MainActor private final class WidgetSession: NSObject, StreamDelegate {
    private var session: EASession?
    private var continuation: CheckedContinuation<String, Never>?
    private var remaining = Data()
    private var response = ""
    private var didWrite = false
    private var command = ""
    private var timeout: Task<Void, Never>?
    private var quietTimer: Task<Void, Never>?
    func send(_ command: String) async -> String {
        self.command = command
        let proto = "com.directed.smartstartbt"
        guard let accessory = EAAccessoryManager.shared().connectedAccessories.first(where: { $0.protocolStrings.contains(proto) }) else { return "NOT CONNECTED" }
        guard let next = EASession(accessory: accessory, forProtocol: proto), let input = next.inputStream, let output = next.outputStream else { return "SESSION UNAVAILABLE" }
        session = next; remaining = Data(command.utf8)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for stream in [input, output] { stream.delegate = self; stream.schedule(in: .main, forMode: .default); stream.open() }
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let reply = self.response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                self.finish(reply == "ERR" ? "Valet" : (self.didWrite ? "Sent" : "Send failed"))
            }
        }
    }
    nonisolated func stream(_ stream: Stream, handle event: Stream.Event) {
        Task { @MainActor in self.handle(stream, event) }
    }
    private func handle(_ stream: Stream, _ event: Stream.Event) {
        guard stream === session?.inputStream || stream === session?.outputStream else { return }
        switch event {
        case .hasSpaceAvailable:
            guard let output = stream as? OutputStream, !remaining.isEmpty else { return }
            let written = remaining.withUnsafeBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return output.write(base, maxLength: raw.count)
            }
            if written < 0 { finish(didWrite ? "CHECK VEHICLE" : "SEND FAILED") }
            else if written > 0 { didWrite = true; remaining.removeFirst(written) }
        case .hasBytesAvailable:
            guard let input = stream as? InputStream else { return }
            var bytes = [UInt8](repeating: 0, count: 128)
            let count = input.read(&bytes, maxLength: bytes.count)
            if count > 0 {
                response += String(decoding: bytes.prefix(count), as: UTF8.self)
                quietTimer?.cancel()
                let snapshot = response
                quietTimer = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled, let self, self.response == snapshot else { return }
                    if let status = WidgetReply.status(for: snapshot, command: self.command) { self.finish(status) }
                }
                if response.contains("\n") || response.contains("\r") {
                    let lines = response.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let status = lines.compactMap { WidgetReply.status(for: $0, command: command) }.first
                    finish(status ?? "Unconfirmed")
                }
            } else if count < 0 { finish(didWrite ? "CHECK VEHICLE" : "READ FAILED") }
        case .errorOccurred, .endEncountered: finish(didWrite ? "CHECK VEHICLE" : "SESSION UNAVAILABLE")
        default: break
        }
    }
    private func finish(_ message: String) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); quietTimer?.cancel()
        if didWrite && !response.isEmpty {
            let shared = UserDefaults(suiteName: "group.com.wireproof.wirestart")
            shared?.set(Date().timeIntervalSince1970, forKey: "widgetResponseAt")
            shared?.set(true, forKey: "appReported")
        }
        for stream in [session?.inputStream, session?.outputStream].compactMap({ $0 }) {
            stream.delegate = nil; stream.remove(from: .main, forMode: .default); stream.close()
        }
        session = nil
        continuation.resume(returning: message)
    }
}

enum WideCommand: String, AppEnum {
    case lock, unlock, start, trunk, panic
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Large button")
    static var caseDisplayRepresentations: [WideCommand: DisplayRepresentation] = [
        .lock: "Lock", .unlock: "Unlock", .start: "Start", .trunk: "Trunk", .panic: "Panic"
    ]
    var action: RemoteAction { RemoteAction(rawValue: rawValue)! }
}
struct WideWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "WireSTART Remote"
    static var description = IntentDescription("Select 2x2 Button Command")
    @Parameter(title: "Large button", default: .start) var command: WideCommand
}

struct WireSTARTEntry: TimelineEntry { let date: Date; let pending: String?; let status: String; let connected: Bool; let reported: Bool; let valet: Bool; var featured: RemoteAction = .start }
struct WireSTARTProvider: TimelineProvider {
    private func entry() -> WireSTARTEntry { WireSTARTEntry(date: .now, pending: WidgetState.pending, status: WidgetState.status, connected: WidgetState.connected(at: .now), reported: WidgetState.reported, valet: WidgetState.valet) }
    func placeholder(in context: Context) -> WireSTARTEntry { WireSTARTEntry(date: .now, pending: nil, status: "READY", connected: true, reported: false, valet: false) }
    func getSnapshot(in context: Context, completion: @escaping (WireSTARTEntry) -> Void) { completion(context.isPreview ? placeholder(in: context) : entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WireSTARTEntry>) -> Void) {
        let current = entry()
        let deadline = current.pending == nil ? (WidgetFeedback.current()?.expires ?? WidgetState.defaults.double(forKey: "statusUntil")) : WidgetState.defaults.double(forKey: "pendingUntil")
        if deadline > Date().timeIntervalSince1970 {
            let expiryDate = Date(timeIntervalSince1970: deadline + 0.1)
            let expired = WireSTARTEntry(date: expiryDate, pending: nil, status: "READY", connected: WidgetState.connected(at: expiryDate), reported: WidgetState.reported, valet: WidgetState.valet)
            completion(Timeline(entries: [current, expired], policy: .never))
        } else { completion(Timeline(entries: [current], policy: .never)) }
    }
}

struct WideWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WireSTARTEntry { WireSTARTProvider().placeholder(in: context) }
    func snapshot(for configuration: WideWidgetConfiguration, in context: Context) async -> WireSTARTEntry {
        var result = await withCheckedContinuation { continuation in WireSTARTProvider().getSnapshot(in: context) { continuation.resume(returning: $0) } }
        result.featured = configuration.command.action
        return result
    }
    func timeline(for configuration: WideWidgetConfiguration, in context: Context) async -> Timeline<WireSTARTEntry> {
        let timeline = await withCheckedContinuation { continuation in WireSTARTProvider().getTimeline(in: context) { continuation.resume(returning: $0) } }
        return Timeline(entries: timeline.entries.map { entry in var result = entry; result.featured = configuration.command.action; return result }, policy: timeline.policy)
    }
}

struct WireSTARTWidgetView: View {
    let entry: WireSTARTEntry
    var featured: RemoteAction = .start
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var textScheme: ColorScheme { renderingMode == .fullColor ? .dark : colorScheme }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                if entry.connected {
                    Button(intent: RemoteIntent(.lock)) { ZStack { AccessoryWidgetBackground(); Image(systemName: "lock.fill") } }.buttonStyle(.plain)
                } else {
                    Button(intent: ConnectAccessoryIntent()) { ZStack { AccessoryWidgetBackground(); Image(systemName: "antenna.radiowaves.left.and.right") } }.buttonStyle(.plain).accessibilityLabel("Connect SmartStart")
                }
            case .accessoryRectangular:
                LockScreenPair(entry: entry, first: .lock, second: .unlock)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    widgetStatus(entry.status, scheme: textScheme, connected: entry.connected, reported: entry.reported, valet: entry.valet, fontSize: 11)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 18)
                        .overlay(alignment: .trailing) { signalIcon(colorScheme, connected: entry.connected, valet: entry.valet, sending: entry.status == "SENDING") }
                    if let pending = entry.pending, let action = RemoteAction(rawValue: pending) {
                        confirmation(action, scheme: textScheme)
                    } else {
                        if family == .systemLarge || family == .systemMedium {
                            let others: [RemoteAction] = [.lock, .unlock, .start, .trunk, .panic].filter { $0 != featured }
                            HStack(spacing: 7) {
                                VStack(spacing: 7) {
                                    HStack(spacing: 7) {
                                        button(others[0], icon: lockScreenSymbol(others[0]), compact: family == .systemMedium)
                                        button(others[1], icon: lockScreenSymbol(others[1]), compact: family == .systemMedium)
                                    }
                                    HStack(spacing: 7) {
                                        button(others[2], icon: lockScreenSymbol(others[2]), compact: family == .systemMedium)
                                        button(others[3], icon: lockScreenSymbol(others[3]), compact: family == .systemMedium)
                                    }
                                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                                button(featured, icon: lockScreenSymbol(featured), featured: true, compact: family == .systemMedium)
                            }
                        } else {
                            VStack(spacing: 7) {
                                HStack(spacing: 7) {
                                    button(.lock, icon: "lock.fill", compact: true)
                                    button(.unlock, icon: "lock.open.fill", compact: true)
                                }
                                HStack(spacing: 7) {
                                    button(.start, icon: "power", compact: true)
                                    button(.trunk, icon: "car.rear.fill", compact: true)
                                }
                            }.frame(maxHeight: .infinity)
                        }
                    }
                }.padding(14)
                    .overlay { if !entry.connected { ConnectAccessoryButton() } }
            }
        }.containerBackground(for: .widget) { widgetBackground(colorScheme) }
    }
    private func button(_ action: RemoteAction, icon: String, featured: Bool = false, compact: Bool = false) -> some View {
        Button(intent: RemoteIntent(action)) {
            VStack(spacing: compact ? 2 : 7) { widgetIcon(icon).font(.system(size: featured ? (compact ? 24 : 30) : (compact ? 13 : 18), weight: .semibold)).foregroundStyle(action.iconColor); Text(action.label).font(.system(size: featured ? 14 : (compact ? 9 : 10), weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.buttonStyle(WidgetButtonStyle(color: .clear, padding: compact ? 4 : 8)).opacity(entry.connected ? 1 : 0.45).disabled(!entry.connected)
    }
}
private func confirmation(_ action: RemoteAction, scheme: ColorScheme) -> some View {
    VStack(spacing: 7) {
        Text("Confirm?")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(scheme == .dark ? Color.white : Color.black)
            .frame(maxWidth: .infinity)
        HStack(spacing: 7) {
            Button(intent: RemoteIntent(.cancel)) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Color.white : Color.black).frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(WidgetButtonStyle(color: .clear)).accessibilityLabel("Cancel \(action.label)")
            Button(intent: RemoteIntent(action)) {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(action == .panic ? Color.red : green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(WidgetButtonStyle(color: .clear)).accessibilityLabel("Confirm \(action.label)")
        }.frame(maxHeight: .infinity)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
}

private struct WidgetButtonStyle: ButtonStyle {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let color: Color
    var darkText = false
    var padding: CGFloat = 8
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(padding).foregroundStyle(darkText ? Color.black : Color.white)
            .background {
                if renderingMode == .fullColor {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(LinearGradient(colors: [Color.white.opacity(configuration.isPressed ? 0.24 : 0.20), Color.white.opacity(configuration.isPressed ? 0.12 : 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.14))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(renderingMode == .fullColor ? 0.13 : 0.20), lineWidth: 0.7))
    }
}
struct WireSTARTWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ViperRemote", intent: WideWidgetConfiguration.self, provider: WideWidgetProvider()) { WireSTARTWidgetView(entry: $0, featured: $0.featured) }
            .configurationDisplayName("WireSTART Remote")
            .description("Select 2x2 Button Command")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
            .contentMarginsDisabled()
    }
}


enum SingleCommand: String, AppEnum {
    case lock, unlock, trunk, start, panic, aux1, aux2
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Command")
    static var caseDisplayRepresentations: [SingleCommand: DisplayRepresentation] = [
        .lock: "Lock", .unlock: "Unlock", .trunk: "Trunk", .start: "Start",
        .panic: "Panic", .aux1: "Aux 1", .aux2: "Aux 2"
    ]
    var action: RemoteAction { RemoteAction(rawValue: rawValue)! }
    var icon: String {
        switch self {
        case .lock: return "lock.fill"
        case .unlock: return "lock.open.fill"
        case .trunk: return "car.rear.fill"
        case .start: return "power"
        case .panic: return "speaker.wave.3.fill"
        case .aux1: return "1.square"
        case .aux2: return "2.square"
        }
    }
}

struct SingleCommandConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "WireSTART Command"
    static var description = IntentDescription("Choose Button Command")
    @Parameter(title: "Command", default: .lock) var command: SingleCommand
}

struct SingleCommandEntry: TimelineEntry {
    let date: Date
    let command: SingleCommand
    let pending: Bool
    let status: String
    let connected: Bool
    let reported: Bool
    let valet: Bool
}

struct SingleCommandProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleCommandEntry {
        SingleCommandEntry(date: .now, command: .lock, pending: false, status: "", connected: false, reported: false, valet: false)
    }
    private func entry(_ configuration: SingleCommandConfiguration) -> SingleCommandEntry {
        let command = configuration.command
        let pending = WidgetState.pending == command.rawValue
        let status = WidgetState.status
        return SingleCommandEntry(date: .now, command: command, pending: pending, status: status, connected: WidgetState.connected(at: .now), reported: WidgetState.reported, valet: WidgetState.valet)
    }
    func snapshot(for configuration: SingleCommandConfiguration, in context: Context) async -> SingleCommandEntry { entry(configuration) }
    func timeline(for configuration: SingleCommandConfiguration, in context: Context) async -> Timeline<SingleCommandEntry> {
        let current = entry(configuration)
        let expiry = current.pending ? WidgetState.defaults.double(forKey: "pendingUntil") : (WidgetFeedback.current()?.expires ?? WidgetState.defaults.double(forKey: "statusUntil"))
        if expiry > Date().timeIntervalSince1970 {
            let expiryDate = Date(timeIntervalSince1970: expiry + 0.1)
            let expired = SingleCommandEntry(date: expiryDate, command: current.command, pending: false, status: "", connected: WidgetState.connected(at: expiryDate), reported: WidgetState.reported, valet: WidgetState.valet)
            return Timeline(entries: [current, expired], policy: .never)
        }
        return Timeline(entries: [current], policy: .never)
    }
}

struct SingleCommandView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var textScheme: ColorScheme { renderingMode == .fullColor ? .dark : colorScheme }
    let entry: SingleCommandEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            widgetStatus(entry.status, scheme: textScheme, connected: entry.connected, reported: entry.reported, valet: entry.valet)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
                .overlay(alignment: .trailing) { signalIcon(colorScheme, connected: entry.connected, valet: entry.valet, sending: entry.status == "SENDING") }
            if entry.pending {
                confirmation(entry.command.action, scheme: textScheme)
            } else {
                Button(intent: RemoteIntent(entry.command.action)) {
                    VStack(alignment: .center, spacing: 9) {
                        widgetIcon(entry.command.icon).font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(entry.command == .start ? green : entry.command.action.iconColor)
                        Text(entry.command.action.label).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }.buttonStyle(WidgetButtonStyle(color: .clear)).opacity(entry.connected ? 1 : 0.45).disabled(!entry.connected)
            }
        }.padding(14)
            .overlay { if !entry.connected { ConnectAccessoryButton() } }
            .containerBackground(for: .widget) { widgetBackground(colorScheme) }
    }
}

struct SingleCommandWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ViperSingleCommand", intent: SingleCommandConfiguration.self, provider: SingleCommandProvider()) { SingleCommandView(entry: $0) }
            .configurationDisplayName("WireSTART Command")
            .description("Choose Button Command")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

private func lockScreenSymbol(_ action: RemoteAction) -> String {
    switch action {
    case .lock: return "lock.fill"
    case .unlock: return "lock.open.fill"
    case .start: return "power"
    case .trunk: return "car.rear.fill"
    case .panic: return "speaker.wave.3.fill"
    case .aux1: return "1.square"
    case .aux2: return "2.square"
    default: return "antenna.radiowaves.left.and.right"
    }
}

private struct LockScreenPair: View {
    let entry: WireSTARTEntry
    let first: RemoteAction
    let second: RemoteAction
    var body: some View {
      Group {
        if !entry.connected {
            Button(intent: ConnectAccessoryIntent()) {
                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
            }.buttonStyle(.plain).accessibilityLabel("Connect SmartStart")
        } else if let pending = entry.pending, let action = RemoteAction(rawValue: pending), action == first || action == second {
            HStack(spacing: 6) {
                Button(intent: RemoteIntent(.cancel)) { Label("Cancel", systemImage: "xmark") }
                    .accessibilityLabel("Cancel \(action.label)")
                Button(intent: RemoteIntent(action)) { Label("Confirm", systemImage: "checkmark") }
                    .accessibilityLabel("Confirm \(action.label)")
            }.font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).buttonStyle(.plain)
        } else {
            HStack(spacing: 4) { command(first); command(second) }
        }
      }.containerBackground(for: .widget) { Color.clear }
    }
    private func command(_ action: RemoteAction) -> some View {
        Button(intent: RemoteIntent(action)) {
            VStack(spacing: 3) {
                Image(systemName: lockScreenSymbol(action)).font(.system(size: 17, weight: .semibold))
                Text(action == .start ? "Start" : action.label).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.buttonStyle(.plain).accessibilityLabel(action.label)
    }
}

private struct LockScreenSingle: View {
    let entry: WireSTARTEntry
    let action: RemoteAction
    var body: some View {
      Group {
        if !entry.connected {
            Button(intent: ConnectAccessoryIntent()) {
                VStack(spacing: 3) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 17, weight: .semibold))
                    Text("Connect").font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Connect SmartStart")
        } else {
            let confirming = entry.pending == action.rawValue
            Button(intent: RemoteIntent(action)) {
                VStack(spacing: 3) {
                    Image(systemName: confirming ? "checkmark" : lockScreenSymbol(action)).font(.system(size: 17, weight: .semibold))
                    Text(confirming ? "Confirm" : action.label).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel(confirming ? "Confirm \(action.label)" : action.label)
        }
      }.containerBackground(for: .widget) { Color.clear }
    }
}

struct LockScreenStartTrunkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WireSTARTLockScreenStartTrunk", provider: WireSTARTProvider()) { LockScreenPair(entry: $0, first: .start, second: .trunk) }
            .configurationDisplayName("Start & Trunk").description("Start and Trunk controls.").supportedFamilies([.accessoryRectangular])
    }
}
struct LockScreenLockWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "WireSTARTLockScreenLock", provider: WireSTARTProvider()) { LockScreenSingle(entry: $0, action: .lock) }.configurationDisplayName("Lock").description("Lock your vehicle.").supportedFamilies([.accessoryCircular]) }
}
struct LockScreenUnlockWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "WireSTARTLockScreenUnlock", provider: WireSTARTProvider()) { LockScreenSingle(entry: $0, action: .unlock) }.configurationDisplayName("Unlock").description("Unlock your vehicle.").supportedFamilies([.accessoryCircular]) }
}
struct LockScreenStartWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "WireSTARTLockScreenStart", provider: WireSTARTProvider()) { LockScreenSingle(entry: $0, action: .start) }.configurationDisplayName("Start").description("Confirm Start.").supportedFamilies([.accessoryCircular]) }
}
struct LockScreenTrunkWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "WireSTARTLockScreenTrunk", provider: WireSTARTProvider()) { LockScreenSingle(entry: $0, action: .trunk) }.configurationDisplayName("Trunk").description("Confirm Trunk.").supportedFamilies([.accessoryCircular]) }
}
struct LockScreenPanicWidget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "WireSTARTLockScreenPanic", provider: WireSTARTProvider()) { LockScreenSingle(entry: $0, action: .panic) }.configurationDisplayName("Panic").description("Confirm Panic.").supportedFamilies([.accessoryCircular]) }
}
struct LockScreenAux1Widget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "WireSTARTLockScreenAux1", provider: WireSTARTProvider()) { LockScreenSingle(entry: $0, action: .aux1) }.configurationDisplayName("Aux 1").description("Send Aux 1.").supportedFamilies([.accessoryCircular]) }
}
struct LockScreenAux2Widget: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "WireSTARTLockScreenAux2", provider: WireSTARTProvider()) { LockScreenSingle(entry: $0, action: .aux2) }.configurationDisplayName("Aux 2").description("Send Aux 2.").supportedFamilies([.accessoryCircular]) }
}

@main struct WireSTARTWidgetBundle: WidgetBundle {
    var body: some Widget {
        WireSTARTWidget(); SingleCommandWidget(); LockScreenStartTrunkWidget()
        LockScreenLockWidget(); LockScreenUnlockWidget(); LockScreenStartWidget(); LockScreenTrunkWidget(); LockScreenPanicWidget()
        LockScreenAux1Widget(); LockScreenAux2Widget()
    }
}
