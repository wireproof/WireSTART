import SwiftUI
import ExternalAccessory
import UIKit
import WidgetKit

@MainActor final class WireSTARTConnection: NSObject, ObservableObject, StreamDelegate {
    private static let accessoryProtocol = "com.directed.smartstartbt"
    @Published private(set) var connection = "Looking for SmartStart…"
    @Published private(set) var detail = ""
    @Published private(set) var ready = false { didSet { if ready != oldValue { publishConnectionState() } } }
    @Published private(set) var paused = UserDefaults.standard.bool(forKey: "sessionPaused")
    @Published private(set) var pickerVisible = false
    enum VehicleState { case unknown, locked, unlocked, valet }
    @Published private(set) var vehicleState: VehicleState = .unknown
    @Published private(set) var signalFlashActive = false
    @Published private(set) var signalFlashOn = false
    @Published private(set) var signalFlashColor: Color = .blue
    private var signalFlashID = UUID()
    private var previewControls = false
    var onAccessoryError: ((String) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
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
        UserDefaults(suiteName: "group.com.wireproof.wirestart")?.set(false, forKey: "valetDetected")
        let storedHold = UserDefaults.standard.integer(forKey: "sessionHoldSeconds")
        let hold = max(900, storedHold)
        UserDefaults.standard.set(hold, forKey: "sessionHoldSeconds")
        UserDefaults(suiteName: "group.com.wireproof.wirestart")?.set(hold, forKey: "sessionHoldSeconds")
        publishConnectionState()
        EAAccessoryManager.shared().registerForLocalNotifications()
        for name in [NSNotification.Name.EAAccessoryDidConnect, .EAAccessoryDidDisconnect] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconnect() }
            })
        }
        if paused {
            connection = "SmartStart: Disconnected"
            detail = ""
            persist()
        } else {
            reconnect()
        }
    }
    private func publishConnectionState() {
        let shared = UserDefaults(suiteName: "group.com.wireproof.wirestart")
        shared?.set(ready, forKey: "appSessionReady")
        shared?.set(true, forKey: "appReported")
        WidgetCenter.shared.reloadAllTimelines()
        onConnectionChange?(ready)
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
        connection = "SmartStart: Connecting"
        detail = ""
        persist()
        let filter = NSPredicate(format: "SELF BEGINSWITH[cd] %@", "SmartStartBT-")
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: filter) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.pickerVisible = false
                if let error = error as NSError?, error.domain == EABluetoothAccessoryPickerErrorDomain, error.code != 0 {
                    self.connection = "SmartStart: Disconnected"
                    self.detail = error.code == 2 ? "" : "SmartStart was not found. Wake the module and try again."
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
        UserDefaults(suiteName: "group.com.wireproof.wirestart")?.removeObject(forKey: "widgetResponseAt")
        closeSession()
        connection = "SmartStart: Disconnected"
        detail = ""
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
        let seconds = max(900, minimumDelay, UserDefaults.standard.integer(forKey: "sessionHoldSeconds"))
        let started = Date().timeIntervalSince1970
        idleReleaseTask = Task { @MainActor [weak self] in
            var deadline = started + Double(seconds)
            while !Task.isCancelled {
                let remaining = max(0, deadline - Date().timeIntervalSince1970)
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                guard !Task.isCancelled, UIApplication.shared.applicationState != .active else { return }
                let widgetActivity = UserDefaults(suiteName: "group.com.wireproof.wirestart")?.double(forKey: "widgetActivityAt") ?? 0
                let latestDeadline = max(started, widgetActivity) + Double(seconds)
                if latestDeadline > Date().timeIntervalSince1970 { deadline = latestDeadline; continue }
                self?.closeSession()
                return
            }
        }
    }
    func reconnect() {
        guard !previewControls, !paused else { return }
        let devices = EAAccessoryManager.shared().connectedAccessories
        guard let device = devices.first(where: { $0.protocolStrings.contains(Self.accessoryProtocol) }) else {
            closeSession()
            connection = "SmartStart: Disconnected"
            detail = ""
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
        connection = "SmartStart: Connecting"
        detail = "Opening the WireSTART session."
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
    private func flashSignal(_ color: Color) {
        let id = UUID()
        signalFlashID = id; signalFlashColor = color; signalFlashActive = true
        Task { @MainActor in
            for phase in 0..<6 {
                guard self.signalFlashID == id else { return }
                self.signalFlashOn = phase % 2 == 0
                try? await Task.sleep(nanoseconds: 166_666_667)
            }
            guard self.signalFlashID == id else { return }
            self.signalFlashActive = false; self.signalFlashOn = false
        }
    }
    func cancelPendingWrite() {
        guard !pending.isEmpty else { return }
        pending = Data(); pendingCommand = nil
        detail = "Send unconfirmed. Check the vehicle."
        flashSignal(.red)
        finishWrite(false)
        persist()
    }
    @discardableResult func send(_ command: Command, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard ready, pending.isEmpty, let output = session?.outputStream else { flashSignal(.red); return false }
        flashSignal(.blue)
        lastResponseHex = ""
        responseGeneration += 1
        responseFramer = ResponseFramer()
        pending = Data(command.rawValue.utf8); pendingCommand = command.title
        writeCompletion = completion
        detail = ""; persist()
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
            flashSignal(.red)
            pending = Data(); pendingCommand = nil
            finishWrite(false)
        } else if written > 0 {
            pending.removeFirst(written)
            if pending.isEmpty {
                detail = ""
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
            if inputOpen && outputOpen { ready = true; connection = "Connected to \(accessory?.name ?? "SmartStart")"; if detail == "Opening the WireSTART session." { detail = "Ready for a command." } }
        case .hasSpaceAvailable:
            if let output = stream as? OutputStream { outputOpen = true; if inputOpen { ready = true; connection = "Connected to \(accessory?.name ?? "SmartStart")"; if detail == "Opening the WireSTART session." { detail = "Ready for a command." } }; flush(output) }
        case .hasBytesAvailable:
            guard let input = stream as? InputStream else { break }
            var bytes = [UInt8](repeating: 0, count: 128)
            let count = input.read(&bytes, maxLength: bytes.count)
            if count > 0 {
                let chunk = Data(bytes.prefix(count))
                lastResponseHex = chunk.map { String(format: "%02x", $0) }.joined()
                let lines = responseFramer.append(chunk)
                for line in lines { applyAccessoryReply(line, complete: true) }
                responseGeneration += 1
                let generation = responseGeneration
                if responseFramer.partialText != nil {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard let self, self.responseGeneration == generation,
                              let text = self.responseFramer.takePartialText() else { return }
                        self.applyAccessoryReply(text, complete: false)
                        self.persist()
                    }
                }
                persist()
            } else if count < 0 { detail = "Could not read module response." }
        case .errorOccurred, .endEncountered:
            closeSession()
            connection = "SmartStart connection ended"
            detail = "Check the vehicle before retrying a command."
        default: break
        }
        persist()
    }
    private func applyAccessoryReply(_ reply: String, complete: Bool) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch text {
        case "ERR", "E", "RR":
            vehicleState = .valet
            UserDefaults(suiteName: "group.com.wireproof.wirestart")?.set(true, forKey: "valetDetected")
            WidgetCenter.shared.reloadAllTimelines()
            detail = ""
            onAccessoryError?("ERR")
        case "LOCK OK":
            if vehicleState != .valet { vehicleState = .locked }
            detail = ""
        case "UNLOCK OK":
            if vehicleState != .valet { vehicleState = .unlocked }
            detail = ""
        case "START OK", "STOP OK", "TRUNK OK", "PANIC OK":
            detail = ""
        default:
            detail = complete ? "Accessory response unrecognized." : "Accessory response incomplete."
        }
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

private enum WireSTARTTheme {
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static let background = adaptive(UIColor(red: 0.95, green: 0.96, blue: 0.95, alpha: 1), UIColor(red: 0.025, green: 0.035, blue: 0.031, alpha: 1))
    static let panel = adaptive(.white, UIColor(red: 0.072, green: 0.089, blue: 0.081, alpha: 1))
    static let connectionPanel = adaptive(UIColor(red: 0.91, green: 0.95, blue: 0.91, alpha: 1), UIColor(red: 0.09, green: 0.13, blue: 0.10, alpha: 1))
    static let line = adaptive(UIColor.black.withAlphaComponent(0.12), UIColor.white.withAlphaComponent(0.09))
    static let text = Color.primary
    static let controlSurface = adaptive(UIColor.black.withAlphaComponent(0.08), UIColor.white.withAlphaComponent(0.10))
    static let lime = adaptive(UIColor(red: 0.13, green: 0.45, blue: 0.10, alpha: 1), UIColor(red: 0.63, green: 0.94, blue: 0.24, alpha: 1))
    static let buttonLime = Color(red: 0.63, green: 0.94, blue: 0.24)
    static let signalShadow = adaptive(UIColor.black.withAlphaComponent(0.65), .clear)
    static let muted = adaptive(UIColor(red: 0.37, green: 0.42, blue: 0.39, alpha: 1), UIColor(red: 0.62, green: 0.68, blue: 0.64, alpha: 1))
    static let red = adaptive(UIColor(red: 0.72, green: 0.10, blue: 0.12, alpha: 1), UIColor(red: 1.0, green: 0.30, blue: 0.31, alpha: 1))
    static let redPanel = adaptive(UIColor(red: 1.0, green: 0.90, blue: 0.90, alpha: 1), UIColor(red: 0.22, green: 0.055, blue: 0.06, alpha: 1))
    static let blue = adaptive(UIColor(red: 0.05, green: 0.34, blue: 0.65, alpha: 1), UIColor(red: 0.35, green: 0.72, blue: 1.0, alpha: 1))
    static func iconColor(_ command: WireSTARTConnection.Command) -> Color {
        switch command {
        case .unlock, .panic: return red
        case .trunk: return blue
        case .start: return adaptive(UIColor(red: 0.65, green: 0.31, blue: 0.02, alpha: 1), UIColor(red: 1.0, green: 0.68, blue: 0.25, alpha: 1))
        case .aux1, .aux2: return muted
        default: return lime
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var car: WireSTARTConnection
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingConfirmation: WireSTARTConnection.Command?
    @State private var showBluetoothDetails = false
    @State private var vehicleNames = UserDefaults.standard.dictionary(forKey: "vehicleNamesByAccessory") as? [String: String] ?? [:]
    @State private var showIconPicker = false
    @State private var selectedIcon = UIApplication.shared.alternateIconName
    @State private var iconChangeError: String?
    @State private var timeoutExpanded = false
    @State private var hasVerticalToolbar = false
    @State private var hingeOpen = false
    @State private var landscapeLayout = false
    private var useVerticalToolbar: Bool { hasVerticalToolbar || (hingeOpen && landscapeLayout) }
    @AppStorage("sessionHoldSeconds") private var sessionHoldSeconds = 900
    private var selectedIconColor: Color {
        switch selectedIcon {
        case "IconRed", "IconRedEyes": return Color(red: 1.0, green: 0.30, blue: 0.31)
        case "IconBlue", "IconBlueEyes": return Color(red: 0.25, green: 0.65, blue: 1.0)
        case "IconYellow": return Color(red: 1.0, green: 0.86, blue: 0.15)
        case "IconPurple": return Color(red: 0.72, green: 0.30, blue: 1.0)
        case "IconPink": return Color(red: 1.0, green: 0.25, blue: 0.65)
        default: return WireSTARTTheme.buttonLime
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
              let landscape = geometry.size.width > geometry.size.height
              let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: landscape ? 3 : 2)
              let tileHeight = landscape ? max(70, min(145, (geometry.size.height - 245) / 3)) : max(102, min(135, (geometry.size.height - 225) / 4))
              ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    connectionCard(showSessionInfo: geometry.size.width >= 500 && geometry.size.height >= 500)
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: columns, spacing: 12) {
                            control("Lock", icon: "lock.fill", command: .lock, height: tileHeight)
                            control("Unlock", icon: "lock.open.fill", command: .unlock, height: tileHeight)
                            control("Remote Start", icon: "power", command: .start, height: tileHeight)
                            control("Trunk", icon: "car.rear.fill", command: .trunk, height: tileHeight)
                            control("Aux 1", icon: "1.square", command: .aux1, height: tileHeight)
                            control("Aux 2", icon: "2.square", command: .aux2, height: tileHeight)
                        }
                        control("Panic", icon: "speaker.wave.3.fill", command: .panic, warning: true, height: tileHeight)
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, landscape ? 0 : 12)
                .padding(.bottom, 16)
              }
              .onAppear { landscapeLayout = landscape }
              .onChange(of: landscape) { landscapeLayout = $0 }
              .background {
                  if #available(iOS 27.1, *) {
                      WireSTARTVerticalBarObserver(isActive: $hasVerticalToolbar)
                      WireSTARTHingeObserver(isOpen: $hingeOpen)
                  }
              }
            }
            .onChange(of: useVerticalToolbar) { _ in timeoutExpanded = false }
            .onChange(of: sessionHoldSeconds) { value in
                UserDefaults(suiteName: "group.com.wireproof.wirestart")?.set(max(900, value), forKey: "sessionHoldSeconds")
            }
            .toolbar {
                if #available(iOS 27.1, *), useVerticalToolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { withAnimation { timeoutExpanded.toggle() } } label: {
                            Label("Session hold", systemImage: "clock").labelStyle(.iconOnly).foregroundStyle(WireSTARTTheme.text)
                        }.tint(WireSTARTTheme.text).accessibilityLabel(timeoutExpanded ? "Close session hold menu" : "Open session hold menu")
                    }.axisBehavior(.verticalPreferred)
                    if timeoutExpanded {
                        ForEach(timeoutOptions, id: \.seconds) { option in
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button { sessionHoldSeconds = option.seconds; withAnimation { timeoutExpanded = false } } label: {
                                    Text(option.label).font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(sessionHoldSeconds == option.seconds ? Color.black : WireSTARTTheme.text)
                                        .frame(width: 40, height: 40)
                                        .background(sessionHoldSeconds == option.seconds ? selectedIconColor : Color.clear, in: Circle())
                                }.accessibilityLabel("\(option.label) session hold")
                            }.axisBehavior(.verticalPreferred)
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if !useVerticalToolbar {
                    horizontalTimeout
                        .padding(.leading, 20)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(WireSTARTTheme.background.ignoresSafeArea())

            .onChange(of: scenePhase) { phase in
                if phase == .active { car.cancelScheduledRelease(); car.reconnect() }
                else if phase == .background { car.releaseAfterIdle() }
            }
        }
        .tint(WireSTARTTheme.lime)
        .sheet(isPresented: $showIconPicker) {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                        ForEach(iconChoices, id: \.preview) { choice in
                            Button {
                                guard UIApplication.shared.supportsAlternateIcons else { iconChangeError = "Changing the app icon is unavailable on this device."; return }
                                UIApplication.shared.setAlternateIconName(choice.name) { error in
                                    DispatchQueue.main.async {
                                        if let error { iconChangeError = error.localizedDescription }
                                        else { selectedIcon = choice.name }
                                    }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(choice.preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18))
                                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selectedIcon == choice.name ? selectedIconColor : WireSTARTTheme.line, lineWidth: selectedIcon == choice.name ? 3 : 1))
                                    Text(choice.label).font(.caption.weight(.semibold)).foregroundStyle(WireSTARTTheme.text)
                                }
                            }.buttonStyle(.plain).accessibilityLabel("\(choice.label) icon")
                        }
                    }.padding(20)
                }
                .background(WireSTARTTheme.background.ignoresSafeArea())
                .navigationTitle("Choose Icon")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showIconPicker = false } } }
                .alert("Unable to change icon", isPresented: Binding(get: { iconChangeError != nil }, set: { if !$0 { iconChangeError = nil } })) { Button("OK") { iconChangeError = nil } } message: { Text(iconChangeError ?? "") }
            }
        }
        .sheet(isPresented: $showBluetoothDetails) {
            NavigationStack {
                List {
                    Section {
                        Text("Compatible with Viper VSM50BT").frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                    }
                    Section("Connection") {
                        LabeledContent("VSM50BT:", value: car.ready ? "Connected" : "Disconnected")
                        LabeledContent("Session hold", value: "\(max(900, sessionHoldSeconds) / 60) minutes")
                        if !car.detail.isEmpty {
                            Text(car.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let device = car.accessoryDetails, !VehicleNames.key(for: device.name).isEmpty {
                        Section {
                            TextField("Vehicle name", text: vehicleNameBinding(for: device.name), prompt: Text(device.name))
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .lineLimit(1)
                        } header: { Text("Vehicle name") } footer: {
                            Text("Up to \(VehicleNames.limit) characters. Leave blank to use the SmartStart name.")
                        }
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
                    }
                    Text("WireSTART \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
                .navigationTitle("Bluetooth")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showBluetoothDetails = false } } }
            }
        }
    }
    private var header: some View {
        HStack(spacing: 5) {
            Button { showIconPicker = true } label: {
                Image(iconChoices.first(where: { $0.name == selectedIcon })?.preview ?? "PreviewGreenEyes")
                    .resizable().scaledToFill().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(WireSTARTTheme.line))
            }.buttonStyle(.plain).accessibilityLabel("Choose app icon")
            VStack(alignment: .leading, spacing: 3) {
                Text("WIRESTART").font(.system(size: 24, weight: .black)).tracking(1.0).foregroundStyle(WireSTARTTheme.text).lineLimit(1).fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                Text("REMOTE START").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(WireSTARTTheme.muted)
            }
            Spacer(minLength: 0)
            if car.vehicleState != .unknown {
                Image(systemName: vehicleStateIcon)
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(vehicleStateColor, in: RoundedRectangle(cornerRadius: 7))
                    .frame(width: 36, height: 44)
                    .accessibilityLabel(vehicleStateLabel)
            }
            Button { showBluetoothDetails = true } label: {
                BluetoothMark().stroke(Color.white, style: StrokeStyle(lineWidth: 2.1, lineCap: .butt, lineJoin: .miter))
                    .frame(width: 14, height: 22).frame(width: 32, height: 32)
                    .background(car.ready ? Color(red: 0.05, green: 0.40, blue: 0.85) : Color(red: 0.76, green: 0.16, blue: 0.19), in: RoundedRectangle(cornerRadius: 7))
                    .frame(width: 36, height: 44)
            }.accessibilityLabel("Bluetooth details")


        }
        .accessibilityElement(children: .contain)
    }
    private func vehicleNameBinding(for accessoryName: String) -> Binding<String> {
        let key = VehicleNames.key(for: accessoryName)
        return Binding(
            get: { vehicleNames[key] ?? "" },
            set: { value in
                let name = VehicleNames.limited(value)
                if name.isEmpty { vehicleNames.removeValue(forKey: key) }
                else { vehicleNames[key] = name }
                UserDefaults.standard.set(vehicleNames, forKey: "vehicleNamesByAccessory")
            }
        )
    }
    private var vehicleStateIcon: String {
        switch car.vehicleState { case .unknown: return "questionmark"; case .locked: return "lock.fill"; case .unlocked: return "lock.open.fill"; case .valet: return "exclamationmark.triangle.fill" }
    }
    private var vehicleStateColor: Color {
        switch car.vehicleState { case .unknown: return .gray; case .locked: return Color(red: 0.20, green: 0.58, blue: 0.12); case .unlocked: return Color(red: 0.76, green: 0.16, blue: 0.19); case .valet: return Color(red: 0.86, green: 0.49, blue: 0.06) }
    }
    private var vehicleStateLabel: String {
        switch car.vehicleState { case .unknown: return "Vehicle state unknown"; case .locked: return "Lock acknowledged"; case .unlocked: return "Unlock acknowledged"; case .valet: return "Valet mode detected" }
    }
    private let iconChoices: [(label: String, name: String?, preview: String)] = [
        ("Green", "IconGreenEyes", "PreviewGreen"), ("Red", "IconRed", "PreviewRed"), ("Blue", "IconBlue", "PreviewBlue"),
        ("Yellow", "IconYellow", "PreviewYellow"), ("Purple", "IconPurple", "PreviewPurple"), ("Pink", "IconPink", "PreviewPink"),
        ("Red Eyes", "IconRedEyes", "PreviewRedEyes"), ("Green Eyes", nil, "PreviewGreenEyes"), ("Blue Eyes", "IconBlueEyes", "PreviewBlueEyes")
    ]
    private let timeoutOptions: [(label: String, seconds: Int)] = [
        ("15m", 900), ("30m", 1800), ("1h", 3600), ("3h", 10800), ("6h", 21600), ("12h", 43200)
    ]
    private var horizontalTimeout: some View {
        HStack(spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { timeoutExpanded.toggle() } } label: {
                Image(systemName: "clock").font(.system(size: 18, weight: .semibold)).frame(width: 42, height: 42)
            }.accessibilityLabel(timeoutExpanded ? "Close session hold menu" : "Open session hold menu")
            if timeoutExpanded {
                ForEach(timeoutOptions, id: \.seconds) { option in
                    Button { sessionHoldSeconds = option.seconds; withAnimation(.easeInOut(duration: 0.2)) { timeoutExpanded = false } } label: {
                        Text(option.label).font(.system(size: 12, weight: .bold))
                            .foregroundStyle(sessionHoldSeconds == option.seconds ? Color.black : WireSTARTTheme.text)
                            .frame(width: 39, height: 39)
                            .background(sessionHoldSeconds == option.seconds ? selectedIconColor : Color.clear, in: Circle())
                    }.accessibilityLabel("\(option.label) session hold")
                }
            }
        }
        .foregroundStyle(WireSTARTTheme.text)
        .padding(3)
        .background(WireSTARTTheme.controlSurface, in: Capsule())
        .fixedSize()
    }
    private func connectionCard(showSessionInfo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(WireSTARTTheme.lime.opacity(car.ready ? 0.14 : 0.06)).frame(width: 42, height: 42)
                    TimelineView(.periodic(from: .now, by: 0.65)) { context in
                        let connecting = car.pickerVisible || car.connection == "SmartStart: Connecting"
                        let blink = Int(context.date.timeIntervalSinceReferenceDate / 0.65) % 2 == 0
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(car.vehicleState == .valet ? Color.yellow : (car.signalFlashActive ? (car.signalFlashOn ? car.signalFlashColor : WireSTARTTheme.muted) : (car.ready || (connecting && blink) ? WireSTARTTheme.buttonLime : WireSTARTTheme.muted)))
                            .shadow(color: (car.vehicleState == .valet || (!car.signalFlashActive && (car.ready || (connecting && blink)))) ? WireSTARTTheme.signalShadow : .clear, radius: 0.8, x: 0, y: 0.5)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if car.ready {
                        (Text("SmartStart: ").foregroundColor(WireSTARTTheme.text) + Text("Connected").foregroundColor(WireSTARTTheme.lime))
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        if car.connection.hasPrefix("Connected to ") {
                            Text(VehicleNames.displayName(for: String(car.connection.dropFirst("Connected to ".count)), names: vehicleNames)).font(.system(size: 13)).foregroundStyle(WireSTARTTheme.muted).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    } else if car.connection == "SmartStart: Disconnected" {
                        (Text("SmartStart: ").foregroundColor(WireSTARTTheme.text) + Text("Disconnected").foregroundColor(WireSTARTTheme.red))
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Text(car.connection).font(.system(size: 15, weight: .semibold)).foregroundStyle(WireSTARTTheme.text).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if showSessionInfo, let device = car.accessoryDetails {
                        let details = [device.manufacturer, device.modelNumber, device.firmwareRevision.isEmpty ? "" : "Firmware \(device.firmwareRevision)"].filter { !$0.isEmpty }
                        if !details.isEmpty { Text(details.joined(separator: " · ")).font(.footnote).foregroundStyle(WireSTARTTheme.muted) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { if car.ready { car.disconnect() } else { car.connect() } } label: {
                    Text(car.ready ? "Disconnect" : "Connect")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(car.ready ? WireSTARTTheme.text : Color.black)
                .background(car.ready ? WireSTARTTheme.controlSurface : WireSTARTTheme.buttonLime, in: RoundedRectangle(cornerRadius: 10))
                .disabled(car.pickerVisible)
            }
            if !car.detail.isEmpty && car.detail != "Ready for a command." {
                Text(car.detail).font(.footnote).foregroundStyle(car.detail == "Vehicle Locked" ? WireSTARTTheme.lime : car.detail == "Vehicle Unlocked" ? WireSTARTTheme.red : WireSTARTTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [WireSTARTTheme.connectionPanel, WireSTARTTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WireSTARTTheme.line))
    }
    private func control(_ title: String, icon: String, command: WireSTARTConnection.Command, warning: Bool = false, height: CGFloat = 102) -> some View {
        Group {
            if pendingConfirmation == command {
                VStack(spacing: 7) {
                    Text("Confirm?").font(.system(size: 16, weight: .semibold)).foregroundStyle(WireSTARTTheme.text)
                    HStack(spacing: 10) {
                        Button { pendingConfirmation = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(WireSTARTTheme.text).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(WireSTARTTheme.controlSurface, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityLabel("Cancel \(title)")
                        Button { pendingConfirmation = nil; car.send(command) } label: {
                            Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(warning ? WireSTARTTheme.red : WireSTARTTheme.lime)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(WireSTARTTheme.controlSurface, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).disabled(!car.ready).accessibilityLabel("Confirm \(title)")
                    }
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: height, alignment: .center)
                .background(warning ? WireSTARTTheme.redPanel : WireSTARTTheme.panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(warning ? WireSTARTTheme.red.opacity(0.55) : WireSTARTTheme.lime.opacity(0.5)))
            } else {
                Button {
                    if command.requiresConfirmation { pendingConfirmation = command }
                    else { pendingConfirmation = nil; car.send(command) }
                } label: {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(warning ? WireSTARTTheme.red : (car.ready ? WireSTARTTheme.iconColor(command) : WireSTARTTheme.muted))
                        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(warning ? WireSTARTTheme.red : (car.ready ? WireSTARTTheme.text : WireSTARTTheme.muted))
                    }
                    .padding(12).frame(maxWidth: .infinity, minHeight: height, alignment: .center)
                    .background(warning ? WireSTARTTheme.redPanel : WireSTARTTheme.panel.opacity(car.ready ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).fill(warning ? Color.clear : WireSTARTTheme.iconColor(command).opacity(car.ready ? 0.045 : 0.01)))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(warning ? WireSTARTTheme.red.opacity(0.4) : WireSTARTTheme.line))
                    .contentShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(WireSTARTPressStyle()).disabled(!car.ready)
                .accessibilityLabel(title).accessibilityHint(command.requiresConfirmation ? "Requires confirmation" : "Sends immediately")
            }
        }
    }
}
@available(iOS 27.1, *)
private struct WireSTARTVerticalBarObserver: View {
    @Environment(\.toolbarVerticalEdge) private var edge
    @Binding var isActive: Bool
    var body: some View {
        Color.clear.allowsHitTesting(false)
            .onAppear { isActive = edge != nil }
            .onChange(of: edge) { isActive = $0 != nil }
    }
}
@available(iOS 27.1, *)
private struct WireSTARTHingeObserver: UIViewRepresentable {
    @Binding var isOpen: Bool
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        let binding = $isOpen
        view.addInteraction(UIHingeInteraction { _, update in
            guard let hinge = update.hinge, hinge.status != .unknown else { return }
            let open = hinge.status != .closed
            DispatchQueue.main.async { if binding.wrappedValue != open { binding.wrappedValue = open } }
        })
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { }
}
private struct BluetoothMark: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width, y = rect.height
        var path = Path()
        path.move(to: CGPoint(x: x * 0.5, y: y * 0.04))
        path.addLine(to: CGPoint(x: x * 0.5, y: y * 0.96))
        path.addLine(to: CGPoint(x: x * 0.85, y: y * 0.74))
        path.addLine(to: CGPoint(x: x * 0.15, y: y * 0.26))
        path.move(to: CGPoint(x: x * 0.15, y: y * 0.74))
        path.addLine(to: CGPoint(x: x * 0.85, y: y * 0.26))
        path.addLine(to: CGPoint(x: x * 0.5, y: y * 0.04))
        return path
    }
}
private struct WireSTARTPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.98 : 1).opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
@MainActor final class PhoneModel: ObservableObject {
    static let shared = PhoneModel()
    let car: WireSTARTConnection
    let watch: PhoneWatchBridge
    init() {
        let connection = WireSTARTConnection()
        car = connection
        watch = PhoneWatchBridge(car: connection)
    }
}
@MainActor final class WireSTARTAppDelegate: NSObject, UIApplicationDelegate {
    let model = PhoneModel.shared
}
@main struct WireSTARTApp: App {
    @UIApplicationDelegateAdaptor(WireSTARTAppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { ContentView().environmentObject(appDelegate.model.car) } }
}
