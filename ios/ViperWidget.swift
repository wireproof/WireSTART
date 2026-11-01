import WidgetKit
import SwiftUI
import AppIntents
import ExternalAccessory

private let green = Color(red: 0.63, green: 0.94, blue: 0.24)
private let widgetBackground = Color(red: 0.025, green: 0.035, blue: 0.031)

private enum WidgetState {
    static let defaults = UserDefaults.standard
    static var pending: String? {
        guard let command = defaults.string(forKey: "pending"), defaults.double(forKey: "pendingUntil") > Date().timeIntervalSince1970 else { return nil }
        return command
    }
    static var status: String {
        let value = defaults.string(forKey: "status") ?? "READY"
        return value.hasPrefix("CONFIRM ") && pending == nil ? "READY" : value
    }
    static func clear() { defaults.removeObject(forKey: "pending"); defaults.removeObject(forKey: "pendingUntil") }
}

enum RemoteAction: String, AppEnum {
    case lock, unlock, trunk, start, panic, cancel
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Remote command")
    static var caseDisplayRepresentations: [RemoteAction: DisplayRepresentation] = [
        .lock: "Lock", .unlock: "Unlock", .trunk: "Trunk", .start: "Start / Stop", .panic: "Panic", .cancel: "Cancel"
    ]
    var needsConfirmation: Bool { self == .trunk || self == .start || self == .panic }
    var label: String { self == .start ? "Start / Stop" : rawValue.capitalized }
}

struct RemoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Viper Remote"
    static var description = IntentDescription("Send a command to your SmartStart accessory.")
    @Parameter(title: "Command") var action: RemoteAction
    init() { action = .lock }
    init(_ action: RemoteAction) { self.action = action }
    @MainActor func perform() async throws -> some IntentResult {
        let decision = WidgetConfirmation.decide(command: action.rawValue, requiresConfirmation: action.needsConfirmation,
            pending: WidgetState.defaults.string(forKey: "pending"), expiresAt: WidgetState.defaults.double(forKey: "pendingUntil"), now: Date().timeIntervalSince1970)
        if decision == .cancel { WidgetState.clear(); WidgetState.defaults.set("CANCELLED", forKey: "status"); return .result() }
        if decision == .stage {
            WidgetState.defaults.set(action.rawValue, forKey: "pending")
            WidgetState.defaults.set(Date().timeIntervalSince1970 + 20, forKey: "pendingUntil")
            WidgetState.defaults.set("CONFIRM \(action.label.uppercased())", forKey: "status")
            return .result()
        }
        WidgetState.clear()
        let result = await WidgetSession().send(action.rawValue)
        WidgetState.defaults.set(result, forKey: "status")
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
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.finish(self.didWrite ? "SENT · CHECK VEHICLE" : "SESSION TIMED OUT")
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
                if response.contains("\n") || response.contains("\r") {
                    let line = response.uppercased()
                    let expected = command == "start" ? (line.contains("START OK") || line.contains("STOP OK")) : line.contains("\(command.uppercased()) OK")
                    finish(expected ? "ACCESSORY ACKNOWLEDGED" : "REPLY · CHECK VEHICLE")
                }
            } else if count < 0 { finish(didWrite ? "CHECK VEHICLE" : "READ FAILED") }
        case .errorOccurred, .endEncountered: finish(didWrite ? "CHECK VEHICLE" : "SESSION UNAVAILABLE")
        default: break
        }
    }
    private func finish(_ message: String) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel()
        for stream in [session?.inputStream, session?.outputStream].compactMap({ $0 }) {
            stream.delegate = nil; stream.remove(from: .main, forMode: .default); stream.close()
        }
        session = nil
        continuation.resume(returning: message)
    }
}

struct ViperEntry: TimelineEntry { let date: Date; let pending: String?; let status: String }
struct ViperProvider: TimelineProvider {
    private func entry() -> ViperEntry { ViperEntry(date: .now, pending: WidgetState.pending, status: WidgetState.status) }
    func placeholder(in context: Context) -> ViperEntry { ViperEntry(date: .now, pending: nil, status: "READY") }
    func getSnapshot(in context: Context, completion: @escaping (ViperEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ViperEntry>) -> Void) { completion(Timeline(entries: [entry()], policy: .never)) }
}

struct ViperWidgetView: View {
    let entry: ViperEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Button(intent: RemoteIntent(.lock)) { ZStack { AccessoryWidgetBackground(); Image(systemName: "lock.fill") } }.buttonStyle(.plain)
            case .accessoryRectangular:
                HStack(spacing: 12) { compactButton(.lock, icon: "lock.fill"); compactButton(.unlock, icon: "lock.open.fill") }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.shield.fill").foregroundStyle(green)
                        Text("VIPER").tracking(1.5).foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Text(entry.status).foregroundStyle(green).lineLimit(1).minimumScaleFactor(0.65)
                    }.font(.system(size: 9, weight: .bold))
                    if let pending = entry.pending, let action = RemoteAction(rawValue: pending) {
                        HStack(spacing: 8) {
                            Button(intent: RemoteIntent(.cancel)) { Text("Cancel").frame(maxWidth: .infinity) }.buttonStyle(WidgetButtonStyle(color: .white.opacity(0.12)))
                            Button(intent: RemoteIntent(action)) { Text("Confirm \(action.label)").frame(maxWidth: .infinity) }.buttonStyle(WidgetButtonStyle(color: action == .panic ? .red : green, darkText: action != .panic))
                        }
                    } else {
                        HStack(spacing: 7) {
                            button(.lock, icon: "lock.fill")
                            button(.unlock, icon: "lock.open.fill")
                            if family != .systemSmall { button(.trunk, icon: "car.rear.fill"); button(.start, icon: "power"); button(.panic, icon: "speaker.wave.3.fill") }
                        }
                    }
                }.padding(14)
            }
        }.containerBackground(for: .widget) { widgetBackground }
    }
    private func compactButton(_ action: RemoteAction, icon: String) -> some View {
        Button(intent: RemoteIntent(action)) { Label(action.label, systemImage: icon) }.buttonStyle(.plain)
    }
    private func button(_ action: RemoteAction, icon: String) -> some View {
        Button(intent: RemoteIntent(action)) {
            VStack(spacing: 7) { Image(systemName: icon).font(.system(size: 18, weight: .semibold)); Text(action.label).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.buttonStyle(WidgetButtonStyle(color: action == .panic ? Color.red.opacity(0.25) : .white.opacity(0.07)))
    }
}
private struct WidgetButtonStyle: ButtonStyle {
    let color: Color
    var darkText = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(8).foregroundStyle(darkText ? Color.black : Color.white)
            .background(color.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 11))
    }
}
@main struct ViperWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ViperRemote", provider: ViperProvider()) { ViperWidgetView(entry: $0) }
            .configurationDisplayName("Viper Remote")
            .description("Control your SmartStart accessory over Bluetooth.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
            .contentMarginsDisabled()
    }
}
