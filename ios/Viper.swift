import SwiftUI
import ExternalAccessory
import UIKit

@MainActor final class ViperConnection: NSObject, ObservableObject, StreamDelegate {
    private static let accessoryProtocol = "com.directed.smartstartbt"
    @Published private(set) var connection = "Looking for SmartStart…"
    @Published private(set) var detail = "No command sent."
    @Published private(set) var ready = false
    @Published private(set) var paused = UserDefaults.standard.bool(forKey: "sessionPaused")
    @Published private(set) var pickerVisible = false
    private var previewControls = false
    private var accessory: EAAccessory?
    var accessoryDetails: EAAccessory? { accessory ?? EAAccessoryManager.shared().connectedAccessories.first { $0.protocolStrings.contains(Self.accessoryProtocol) } }
    private var session: EASession?
    private var pending = Data()
    private var responseFramer = ResponseFramer()
    private var pendingCommand: String?
    private var observations: [NSObjectProtocol] = []
    private var lastResponseHex = ""
    private var lastRecord = ""
    private var events: [[String: String]] = []
    private var responseGeneration = 0
    private var idleReleaseTask: Task<Void, Never>?
    private var writeCompletion: ((Bool) -> Void)?
    private var inputOpen = false
    private var outputOpen = false

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview-controls") {
            previewControls = true
            paused = false
            ready = true
            connection = "Connected to SmartStartBT-419F"
            detail = "Ready for a command."
            return
        }
        #endif
        EAAccessoryManager.shared().registerForLocalNotifications()
        for name in [NSNotification.Name.EAAccessoryDidConnect, .EAAccessoryDidDisconnect] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconnect() }
            })
        }
        if paused {
            connection = "Viper disconnected"
            detail = "Viper session closed. Bluetooth remains paired."
            persist()
        } else {
            reconnect()
        }
    }
    private func persist() {
        let state = ["connection": connection, "detail": detail, "ready": String(ready), "responseHex": lastResponseHex]
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("accessory-check.json"), options: .atomic)
        let fingerprint = "\(connection)|\(detail)|\(ready)|\(lastResponseHex)"
        if fingerprint != lastRecord {
            lastRecord = fingerprint
            events.append(["time": ISO8601DateFormatter().string(from: Date()), "connection": connection, "detail": detail, "ready": String(ready), "responseHex": lastResponseHex])
            if events.count > 50 { events.removeFirst(events.count - 50) }
            if let history = try? JSONSerialization.data(withJSONObject: events, options: [.sortedKeys]) {
                try? history.write(to: directory.appendingPathComponent("accessory-events.json"), options: .atomic)
            }
        }
    }
    func connect() {
        paused = false
        UserDefaults.standard.set(false, forKey: "sessionPaused")
        let devices = EAAccessoryManager.shared().connectedAccessories
        if devices.contains(where: { $0.protocolStrings.contains(Self.accessoryProtocol) }) {
            reconnect()
            return
        }
        guard !pickerVisible else { return }
        pickerVisible = true
        connection = "Find SmartStart"
        detail = "Select your SmartStart Bluetooth module."
        persist()
        let filter = NSPredicate(format: "SELF BEGINSWITH[cd] %@", "SmartStartBT-")
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: filter) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.pickerVisible = false
                if let error = error as NSError?, error.domain == EABluetoothAccessoryPickerErrorDomain, error.code != 0 {
                    self.connection = "SmartStart not connected"
                    self.detail = error.code == 2 ? "Connection canceled." : "SmartStart was not found. Wake the module and try again."
                    self.persist()
                } else {
                    self.reconnect()
                }
            }
        }
    }
    func disconnect() {
        paused = true
        cancelScheduledRelease()
        UserDefaults.standard.set(true, forKey: "sessionPaused")
        closeSession()
        connection = "Viper disconnected"
        detail = "Viper session closed. Bluetooth remains paired."
        persist()
    }
    func suspendForWidget() {
        guard !previewControls, !paused else { return }
        closeSession()
    }
    func cancelScheduledRelease() {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
    }
    func releaseAfterIdle(minimumDelay: Int = 0) {
        guard !previewControls, !paused else { return }
        cancelScheduledRelease()
        let seconds = max(minimumDelay, UserDefaults.standard.integer(forKey: "sessionHoldSeconds"))
        guard seconds > 0 else { closeSession(); return }
        idleReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard !Task.isCancelled, UIApplication.shared.applicationState != .active else { return }
            self?.closeSession()
        }
    }
    func reconnect() {
        guard !previewControls, !paused else { return }
        let devices = EAAccessoryManager.shared().connectedAccessories
        guard let device = devices.first(where: { $0.protocolStrings.contains(Self.accessoryProtocol) }) else {
            closeSession()
            connection = "SmartStart not connected"
            detail = "Tap Connect to find your SmartStart module."
            persist(); return
        }
        if let old = accessory, old.connectionID == device.connectionID, session != nil { return }
        closeSession(); accessory = device
        guard let next = EASession(accessory: device, forProtocol: Self.accessoryProtocol),
              let input = next.inputStream, let output = next.outputStream else {
            connection = "Unable to open SmartStart session"; persist(); return
        }
        session = next
        input.delegate = self; output.delegate = self
        input.schedule(in: .main, forMode: .default); output.schedule(in: .main, forMode: .default)
        connection = "Connecting to \(device.name)…"
        detail = "Opening the Viper session."
        input.open(); output.open(); persist()
    }
    private func closeSession() {
        for stream in [session?.inputStream, session?.outputStream].compactMap({ $0 }) {
            stream.delegate = nil; stream.remove(from: .main, forMode: .default); stream.close()
        }
        session = nil; accessory = nil; ready = false; inputOpen = false; outputOpen = false
        pending = Data(); pendingCommand = nil; responseFramer = ResponseFramer(); responseGeneration += 1
        finishWrite(false)
    }
    private func finishWrite(_ success: Bool) {
        let completion = writeCompletion
        writeCompletion = nil
        completion?(success)
    }
    func cancelPendingWrite() {
        guard !pending.isEmpty else { return }
        pending = Data(); pendingCommand = nil
        detail = "Send unconfirmed. Check the vehicle."
        finishWrite(false)
        persist()
    }
    @discardableResult func send(_ command: Command, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard ready, pending.isEmpty, let output = session?.outputStream else { return false }
        lastResponseHex = ""
        responseGeneration += 1
        responseFramer = ResponseFramer()
        pending = Data(command.rawValue.utf8); pendingCommand = command.title
        writeCompletion = completion
        detail = "Sending \(command.title)…"; persist()
        if output.hasSpaceAvailable { flush(output) }
        return true
    }
    private func flush(_ output: OutputStream) {
        guard !pending.isEmpty else { return }
        let written = pending.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return output.write(base, maxLength: raw.count)
        }
        if written < 0 {
            detail = "Could not write command. Check the vehicle before retrying."
            pending = Data(); pendingCommand = nil
            finishWrite(false)
        } else if written > 0 {
            pending.removeFirst(written)
            if pending.isEmpty {
                detail = "\(pendingCommand ?? "Command") sent. Vehicle result is not yet verified."
                pendingCommand = nil
                finishWrite(true)
            }
        }
        persist()
    }
    nonisolated func stream(_ stream: Stream, handle event: Stream.Event) {
        Task { @MainActor in self.handle(stream, event: event) }
    }
    private func handle(_ stream: Stream, event: Stream.Event) {
        guard stream === session?.inputStream || stream === session?.outputStream else { return }
        switch event {
        case .openCompleted:
            if stream === session?.inputStream { inputOpen = true }
            if stream === session?.outputStream { outputOpen = true }
            if inputOpen && outputOpen { ready = true; connection = "Connected to \(accessory?.name ?? "SmartStart")"; if detail == "Opening the Viper session." { detail = "Ready for a command." } }
        case .hasSpaceAvailable:
            if let output = stream as? OutputStream { outputOpen = true; if inputOpen { ready = true; connection = "Connected to \(accessory?.name ?? "SmartStart")"; if detail == "Opening the Viper session." { detail = "Ready for a command." } }; flush(output) }
        case .hasBytesAvailable:
            guard let input = stream as? InputStream else { break }
            var bytes = [UInt8](repeating: 0, count: 128)
            let count = input.read(&bytes, maxLength: bytes.count)
            if count > 0 {
                let chunk = Data(bytes.prefix(count))
                lastResponseHex = chunk.map { String(format: "%02x", $0) }.joined()
                detail = "Receiving a response…"
                persist()
                for line in responseFramer.append(chunk) {
                    detail = AccessoryReply.message(for: line, incomplete: false)
                    persist()
                }
                responseGeneration += 1
                let generation = responseGeneration
                if detail == "Receiving a response…" {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard let self, self.responseGeneration == generation, self.detail == "Receiving a response…" else { return }
                        if let text = self.responseFramer.partialText {
                            self.detail = AccessoryReply.message(for: text, incomplete: true)
                        } else {
                            self.detail = "Accessory replied; result unclear. Check vehicle."
                        }
                        self.persist()
                    }
                }
            } else if count < 0 { detail = "Could not read module response." }
        case .errorOccurred, .endEncountered:
            closeSession()
            connection = "SmartStart connection ended"
            detail = "Check the vehicle before retrying a command."
        default: break
        }
        persist()
    }
    enum Command: String {
        case lock, unlock, trunk, aux1, aux2, start, panic
        var requiresConfirmation: Bool {
            switch self {
            case .trunk, .start, .panic: return true
            default: return false
            }
        }
        var title: String {
            switch self {
            case .aux1: return "Aux 1"
            case .aux2: return "Aux 2"
            case .start: return "Remote Start"
            default: return rawValue.capitalized
            }
        }
    }
}

private enum ViperTheme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.031)
    static let panel = Color(red: 0.072, green: 0.089, blue: 0.081)
    static let line = Color.white.opacity(0.09)
    static let lime = Color(red: 0.63, green: 0.94, blue: 0.24)
    static let muted = Color(red: 0.62, green: 0.68, blue: 0.64)
    static let red = Color(red: 1.0, green: 0.30, blue: 0.31)
    static let redPanel = Color(red: 0.22, green: 0.055, blue: 0.06)
    static let blue = Color(red: 0.35, green: 0.72, blue: 1.0)
    static func iconColor(_ command: ViperConnection.Command) -> Color {
        switch command {
        case .unlock, .panic: return red
        case .trunk: return blue
        case .start: return Color(red: 1.0, green: 0.68, blue: 0.25)
        case .aux1, .aux2: return Color(red: 0.72, green: 0.76, blue: 0.79)
        default: return lime
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var car: ViperConnection
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingConfirmation: ViperConnection.Command?
    @State private var showBluetoothDetails = false
    @State private var timeoutExpanded = false
    @AppStorage("sessionHoldSeconds") private var sessionHoldSeconds = 0
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    connectionCard
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: columns, spacing: 12) {
                            control("Lock", icon: "lock.fill", command: .lock)
                            control("Unlock", icon: "lock.open.fill", command: .unlock)
                            control("Remote Start", icon: "power", command: .start)
                            control("Trunk", icon: "car.rear.fill", command: .trunk)
                            control("Aux 1", icon: "1.square", command: .aux1)
                            control("Aux 2", icon: "2.square", command: .aux2)
                        }
                        control("Panic", icon: "speaker.wave.3.fill", command: .panic, warning: true)
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { withAnimation { timeoutExpanded.toggle() } } label: {
                        Label(timeoutExpanded ? "Close session hold menu" : "Open session hold menu", systemImage: "lock.fill")
                    }
                    if timeoutExpanded {
                        ForEach(timeoutOptions, id: \.seconds) { option in
                            Button { sessionHoldSeconds = option.seconds; withAnimation { timeoutExpanded = false } } label: {
                                Text(option.label).font(.system(size: 13, weight: .bold))
                            }.accessibilityLabel("\(option.label) session hold")
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(ViperTheme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { phase in
                if phase == .active { car.cancelScheduledRelease(); car.reconnect() }
                else if phase == .background { car.releaseAfterIdle() }
            }
        }
        .tint(ViperTheme.lime)
        .sheet(isPresented: $showBluetoothDetails) {
            NavigationStack {
                List {
                    Section("Connection") {
                        LabeledContent("Viper session", value: car.connection)
                        LabeledContent("Session hold", value: sessionHoldSeconds > 0 ? "\(sessionHoldSeconds / 60) minutes" : "Release immediately")
                        Text(car.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let device = car.accessoryDetails {
                        Section("Accessory") {
                            LabeledContent("Name", value: device.name)
                            LabeledContent("Manufacturer", value: device.manufacturer)
                            LabeledContent("Model", value: device.modelNumber)
                            LabeledContent("Serial number", value: device.serialNumber)
                            LabeledContent("Firmware", value: device.firmwareRevision)
                            LabeledContent("Hardware", value: device.hardwareRevision)
                            LabeledContent("Connection ID", value: String(device.connectionID))
                            LabeledContent("Connected", value: device.isConnected ? "Yes" : "No")
                            ForEach(device.protocolStrings, id: \.self) { value in LabeledContent("Protocol", value: value) }
                        }
                    } else { Text("Accessory details are unavailable until connected.").foregroundStyle(.secondary) }
                }
                .navigationTitle("Bluetooth")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showBluetoothDetails = false } } }
            }
        }
    }
    private var header: some View {
        HStack(spacing: 13) {
            Image("BrandMark").resizable().scaledToFill().frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(ViperTheme.line))
            VStack(alignment: .leading, spacing: 3) {
                Text("VIPER").font(.system(size: 24, weight: .black)).tracking(2.2).foregroundStyle(.white)
                Text("BLUETOOTH REMOTE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(ViperTheme.muted)
            }
            Spacer(minLength: 0)
            Button { showBluetoothDetails = true } label: {
                BluetoothMark().stroke(Color.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .butt, lineJoin: .miter))
                    .frame(width: 14, height: 22).frame(width: 32, height: 32)
                    .background(Color(red: 0.0, green: 0.47, blue: 0.96), in: RoundedRectangle(cornerRadius: 9))
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("Bluetooth details")


        }
        .accessibilityElement(children: .contain)
    }
    private let timeoutOptions: [(label: String, seconds: Int)] = [
        ("5m", 300), ("30m", 1800), ("1h", 3600), ("3h", 10800), ("6h", 21600), ("12h", 43200)
    ]
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(ViperTheme.lime.opacity(car.ready ? 0.14 : 0.06)).frame(width: 42, height: 42)
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(car.ready ? ViperTheme.lime : ViperTheme.muted)
                }
                HStack(spacing: 6) {
                    Circle().fill(car.ready ? ViperTheme.lime : ViperTheme.muted).frame(width: 6, height: 6)
                    Text(car.connection.hasPrefix("Connected to ") ? String(car.connection.dropFirst("Connected to ".count)) : car.connection)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { if car.ready { car.disconnect() } else { car.connect() } } label: {
                    Text(car.ready ? "Disconnect" : "Connect")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(car.ready ? Color.white : ViperTheme.background)
                .background(car.ready ? Color.white.opacity(0.08) : ViperTheme.lime, in: RoundedRectangle(cornerRadius: 10))
                .disabled(car.pickerVisible)
            }
            if car.detail != "Ready for a command." {
                Text(car.detail).font(.footnote).foregroundStyle(ViperTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.10), ViperTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ViperTheme.line))
    }
    private func control(_ title: String, icon: String, command: ViperConnection.Command, warning: Bool = false) -> some View {
        Group {
            if pendingConfirmation == command {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send \(title)?").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    HStack(spacing: 10) {
                        Button("Cancel") { pendingConfirmation = nil }
                            .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                        Button("Confirm") { pendingConfirmation = nil; car.send(command) }
                            .buttonStyle(.plain).font(.system(size: 13, weight: .bold))
                            .foregroundStyle(warning ? Color.white : ViperTheme.background).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(warning ? ViperTheme.red : ViperTheme.lime, in: RoundedRectangle(cornerRadius: 9))
                            .disabled(!car.ready)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
                .background(warning ? ViperTheme.redPanel : ViperTheme.panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(warning ? ViperTheme.red.opacity(0.55) : ViperTheme.lime.opacity(0.5)))
            } else {
                Button {
                    if command.requiresConfirmation { pendingConfirmation = command }
                    else { pendingConfirmation = nil; car.send(command) }
                } label: {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(warning ? ViperTheme.red : (car.ready ? ViperTheme.iconColor(command) : ViperTheme.muted))
                        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(warning ? ViperTheme.red : (car.ready ? Color.white : ViperTheme.muted))
                    }
                    .padding(12).frame(maxWidth: .infinity, minHeight: 102, alignment: .center)
                    .background(warning ? ViperTheme.redPanel : ViperTheme.panel.opacity(car.ready ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).fill(warning ? Color.clear : ViperTheme.iconColor(command).opacity(car.ready ? 0.045 : 0.01)))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(warning ? ViperTheme.red.opacity(0.4) : ViperTheme.line))
                    .contentShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(ViperPressStyle()).disabled(!car.ready)
                .accessibilityLabel(title).accessibilityHint(command.requiresConfirmation ? "Requires confirmation" : "Sends immediately")
            }
        }
    }
}
private struct BluetoothMark: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width, y = rect.height
        var path = Path()
        path.move(to: CGPoint(x: x * 0.18, y: y * 0.25))
        path.addLine(to: CGPoint(x: x * 0.8, y: y * 0.75))
        path.addLine(to: CGPoint(x: x * 0.5, y: y * 0.98))
        path.addLine(to: CGPoint(x: x * 0.5, y: y * 0.02))
        path.addLine(to: CGPoint(x: x * 0.8, y: y * 0.25))
        path.addLine(to: CGPoint(x: x * 0.18, y: y * 0.75))
        return path
    }
}
private struct ViperPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1).opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
@MainActor final class PhoneModel: ObservableObject {
    let car: ViperConnection
    let watch: PhoneWatchBridge
    init() {
        let connection = ViperConnection()
        car = connection
        watch = PhoneWatchBridge(car: connection)
    }
}
@MainActor final class ViperAppDelegate: NSObject, UIApplicationDelegate {
    let model = PhoneModel()
}
@main struct ViperApp: App {
    @UIApplicationDelegateAdaptor(ViperAppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { ContentView().environmentObject(appDelegate.model.car) } }
}
