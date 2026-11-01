import SwiftUI
import WatchConnectivity

@MainActor final class WatchRemote: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status = "Connecting to iPhone…"
    @Published var busy = false
    @Published var reachable = false
    @Published var accessoryReady = false
    @Published var blinkActive = false
    @Published var blinkOn = false
    @Published var blinkColor: Color = .blue
    private var blinkID = UUID()
    private var currentRequest: UUID?
    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        else { status = "iPhone connection unavailable" }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.reachable = error == nil && activationState == .activated && session.isReachable; self.accessoryReady = session.receivedApplicationContext["accessoryReady"] as? Bool ?? false; self.status = self.reachable ? "Ready" : "iPhone unavailable" }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let ready = context["accessoryReady"] as? Bool else { return }
        Task { @MainActor in self.accessoryReady = ready }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = session.activationState == .activated && session.isReachable; if !self.busy { self.status = self.reachable ? "Ready" : "iPhone unavailable" } }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let code = message["accessoryError"] as? String, code.uppercased() == "ERR" else { return }
        Task { @MainActor in self.status = "Accessory error. Check vehicle."; self.flash(.yellow) }
    }
    private func flash(_ color: Color) {
        let id = UUID()
        blinkID = id; blinkColor = color; blinkActive = true
        Task { @MainActor in
            for phase in 0..<6 {
                guard self.blinkID == id else { return }
                self.blinkOn = phase % 2 == 0
                try? await Task.sleep(nanoseconds: 166_666_667)
            }
            guard self.blinkID == id else { return }
            self.blinkActive = false; self.blinkOn = false
        }
    }
    func send(_ command: WatchCommand) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { status = "iPhone unavailable"; flash(.red); return }
        guard !busy else { return }
        let request = UUID()
        currentRequest = request
        busy = true; status = "Contacting iPhone…"
        flash(.blue)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard self.currentRequest == request else { return }
            self.currentRequest = nil; self.busy = false; self.status = "No reply. Check vehicle."; self.flash(.red)
        }
        session.sendMessage(["command": command.rawValue, "sentAt": Date().timeIntervalSince1970], replyHandler: { reply in
            Task { @MainActor in
                guard self.currentRequest == request else { return }
                self.currentRequest = nil; self.busy = false; self.status = reply["result"] as? String ?? "Check vehicle"
                if self.status != "Command sent" { self.flash(.red) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.currentRequest == request else { return }
                self.currentRequest = nil; self.busy = false; self.status = "Could not reach iPhone"; self.flash(.red)
            }
        })
    }
}
enum WatchCommand: String, Identifiable {
    case lock, unlock, trunk, start, aux1, aux2, panic
    var id: String { rawValue }
    var label: String {
        switch self { case .start: return "Remote Start"; case .aux1: return "Aux 1"; case .aux2: return "Aux 2"; default: return rawValue.capitalized }
    }
    var icon: String {
        switch self { case .lock: return "lock.fill"; case .unlock: return "lock.open.fill"; case .trunk: return "car.rear.fill"; case .start: return "power"; case .aux1: return "1.square"; case .aux2: return "2.square"; case .panic: return "speaker.wave.3.fill" }
    }
    var iconColor: Color {
        switch self {
        case .unlock, .panic: return .red
        case .trunk: return Color(red: 0.35, green: 0.72, blue: 1.0)
        case .start: return Color(red: 1.0, green: 0.68, blue: 0.25)
        case .aux1, .aux2: return Color(red: 0.72, green: 0.76, blue: 0.79)
        default: return Color(red: 0.63, green: 0.94, blue: 0.24)
        }
    }
    var needsConfirmation: Bool { self == .trunk || self == .start || self == .panic }
}
struct WatchRemoteView: View {
    @StateObject private var remote = WatchRemote()
    @State private var pending: WatchCommand?
    private let green = Color(red: 0.63, green: 0.94, blue: 0.24)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(remote.blinkActive ? (remote.blinkOn ? remote.blinkColor : Color.gray) : (!remote.reachable ? Color.gray : (remote.accessoryReady ? green : Color.orange)))
                        .accessibilityLabel(!remote.reachable ? "iPhone unavailable" : (remote.accessoryReady ? "iPhone and SmartStart connected" : "iPhone reachable; SmartStart disconnected"))
                        .frame(maxWidth: .infinity)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach([WatchCommand.lock, .unlock, .trunk, .start, .aux1, .aux2]) { command in control(command) }
                }
                control(.panic)
            }.padding(.horizontal, 3).padding(.top, 16)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
    private func control(_ command: WatchCommand) -> some View {
        Group {
            if pending == command {
                VStack(spacing: 3) {
                    Text("Confirm?").font(.system(size: 11, weight: .semibold))
                    HStack(spacing: 6) {
                        Button { pending = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 30).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityLabel("Cancel \(command.label)")
                        Button { pending = nil; remote.send(command) } label: {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(command == .panic ? Color.red : green)
                                .frame(maxWidth: .infinity, minHeight: 30).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityLabel("Confirm \(command.label)")
                    }
                }.frame(maxWidth: .infinity, minHeight: 42)
            } else {
                Button {
                    if command.needsConfirmation { pending = command } else { remote.send(command) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: command.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(command.iconColor)
                        Text(command.label).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity, minHeight: 42)
                }.buttonStyle(.plain)
            }
        }.padding(5)
            .opacity(remote.reachable && remote.accessoryReady ? 1 : 0.45)
            .background(command == .panic ? Color.red.opacity(0.2) : command.iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            .disabled(remote.busy)
    }
}
@main struct WireSTARTWatchApp: App { var body: some Scene { WindowGroup { WatchRemoteView() } } }
