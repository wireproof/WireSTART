import SwiftUI
import WatchConnectivity

@MainActor final class WatchRemote: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status = "Connecting to iPhone…"
    @Published var busy = false
    private var currentRequest: UUID?
    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        else { status = "iPhone connection unavailable" }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.status = error == nil && activationState == .activated && session.isReachable ? "Ready" : "iPhone unavailable" }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in if !self.busy { self.status = session.isReachable ? "Ready" : "iPhone unavailable" } }
    }
    func send(_ command: WatchCommand) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { status = "iPhone unavailable"; return }
        guard !busy else { return }
        let request = UUID()
        currentRequest = request
        busy = true; status = "Contacting iPhone…"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard self.currentRequest == request else { return }
            self.currentRequest = nil; self.busy = false; self.status = "No reply. Check vehicle."
        }
        session.sendMessage(["command": command.rawValue, "sentAt": Date().timeIntervalSince1970], replyHandler: { reply in
            Task { @MainActor in
                guard self.currentRequest == request else { return }
                self.currentRequest = nil; self.busy = false; self.status = reply["result"] as? String ?? "Check vehicle"
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.currentRequest == request else { return }
                self.currentRequest = nil; self.busy = false; self.status = "Could not reach iPhone"
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
                HStack { Image(systemName: "bolt.shield.fill").foregroundStyle(green); Text("VIPER").font(.headline).tracking(1.2) }
                Text(remote.status).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach([WatchCommand.lock, .unlock, .trunk, .start, .aux1, .aux2]) { command in control(command) }
                }
                control(.panic)
            }.padding(.horizontal, 3)
        }
        .confirmationDialog(pending.map { "Send \($0.label)?" } ?? "Send command?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let action = pending {
                Button("Confirm", role: action == .panic ? .destructive : nil) { remote.send(action); pending = nil }
                Button("Cancel", role: .cancel) { pending = nil }
            }
        }
    }
    private func control(_ command: WatchCommand) -> some View {
        Button {
            if command.needsConfirmation { pending = command } else { remote.send(command) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: command.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(command.iconColor)
                Text(command.label).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity, minHeight: 42)
        }.buttonStyle(.plain).padding(5)
            .background(command == .panic ? Color.red.opacity(0.2) : command.iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            .disabled(remote.busy)
    }
}
@main struct ViperWatchApp: App { var body: some Scene { WindowGroup { WatchRemoteView() } } }
