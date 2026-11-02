import SwiftUI
import WidgetKit
import AppIntents

private struct CommandEntry: TimelineEntry { let date: Date; let status: String }
private struct CommandProvider: TimelineProvider {
    private func entry(at date: Date) -> CommandEntry {
        let record = UserDefaults(suiteName: "group.com.wireproof.wirestart")?.dictionary(forKey: "watchComplicationStatus")
        guard let ready = record?["ready"] as? Bool else { return CommandEntry(date: date, status: "WireSTART") }
        guard ready else { return CommandEntry(date: date, status: "Disconnected") }
        let state = record?["state"] as? String
        let label = ["locked": "Locked", "unlocked": "Unlocked", "valet": "Valet"][state ?? ""] ?? "WireSTART"
        return CommandEntry(date: date, status: label)
    }
    func placeholder(in context: Context) -> CommandEntry { CommandEntry(date: .now, status: "WireSTART") }
    func getSnapshot(in context: Context, completion: @escaping (CommandEntry) -> Void) { completion(context.isPreview ? placeholder(in: context) : entry(at: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CommandEntry>) -> Void) {
        completion(Timeline(entries: [entry(at: .now)], policy: .never))
    }
}
private struct CommandComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let symbol: String
    let command: String
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(title, systemImage: symbol)
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .accessoryCorner:
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                    .widgetLabel { Text(title) }
            default:
                ZStack { AccessoryWidgetBackground(); Image(systemName: symbol).font(.system(size: 20, weight: .semibold)) }
            }
        }
        .widgetURL(URL(string: "wirestart-watch://command/\(command)"))
        .accessibilityLabel(title)
        .containerBackground(for: .widget) { Color.clear }
    }
}
private struct LockComplication: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "watch-lock", provider: CommandProvider()) { _ in CommandComplicationView(title: "Lock", symbol: "lock.fill", command: "lock") }.configurationDisplayName("Lock").description("Lock with WireSTART.").supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline]) }
}
private struct UnlockComplication: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "watch-unlock", provider: CommandProvider()) { _ in CommandComplicationView(title: "Unlock", symbol: "lock.open.fill", command: "unlock") }.configurationDisplayName("Unlock").description("Unlock with WireSTART.").supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline]) }
}
private struct StartComplication: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "watch-start", provider: CommandProvider()) { _ in CommandComplicationView(title: "Start", symbol: "power", command: "start") }.configurationDisplayName("Start").description("Confirm Start in WireSTART.").supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline]) }
}
private struct TrunkComplication: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "watch-trunk", provider: CommandProvider()) { _ in CommandComplicationView(title: "Trunk", symbol: "car.rear.fill", command: "trunk") }.configurationDisplayName("Trunk").description("Confirm Trunk in WireSTART.").supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline]) }
}
private struct PanicComplication: Widget {
    var body: some WidgetConfiguration { StaticConfiguration(kind: "watch-panic", provider: CommandProvider()) { _ in CommandComplicationView(title: "Panic", symbol: "speaker.wave.3.fill", command: "panic") }.configurationDisplayName("Panic").description("Confirm Panic in WireSTART.").supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline]) }
}
@main struct WireSTARTWatchComplications: WidgetBundle {
    var body: some Widget {
        LockComplication(); UnlockComplication(); StartComplication(); TrunkComplication(); PanicComplication()
        if #available(watchOS 11.0, *) { MainControlsComplication(); TrunkControlsComplication(); UtilityControlsComplication() }
    }
}


@available(watchOS 11.0, *)
private struct ControlsRow: View {
    enum Layout { case start, trunk, utility }
    let layout: Layout
    let status: String
    var body: some View {
        AccessoryWidgetGroup {
            Text(" ")
        } content: {
            command(layout == .utility ? .start : .lock, layout == .utility ? "power" : "lock.fill", layout == .utility ? .orange : .green, layout == .utility ? "Start" : "Lock")
            command(layout == .utility ? .trunk : .unlock, layout == .utility ? "car.rear.fill" : "lock.open.fill", layout == .utility ? .blue : .red, layout == .utility ? "Trunk" : "Unlock")
            command(layout == .start ? .start : (layout == .trunk ? .trunk : .panic), layout == .start ? "power" : (layout == .trunk ? "car.rear.fill" : "speaker.wave.3.fill"), layout == .start ? .orange : (layout == .trunk ? .blue : .red), layout == .start ? "Start" : (layout == .trunk ? "Trunk" : "Panic"))
        }.accessoryWidgetGroupStyle(.roundedSquare)
            .overlay(alignment: .top) { Text(status).frame(maxWidth: .infinity, alignment: .center).allowsHitTesting(false) }
            .containerBackground(for: .widget) { Color.clear }
    }
    private func command(_ action: ComplicationAction, _ icon: String, _ color: Color, _ label: String) -> some View {
        Button(intent: WatchComplicationIntent(action)) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityLabel(label)
    }
}
@available(watchOS 11.0, *)
private struct MainControlsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch-main-controls", provider: CommandProvider()) { ControlsRow(layout: .start, status: $0.status) }
            .configurationDisplayName("Lock, Unlock, Start")
            .description("Three WireSTART controls.")
            .supportedFamilies([.accessoryRectangular])
    }
}
@available(watchOS 11.0, *)
private struct TrunkControlsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch-trunk-controls", provider: CommandProvider()) { ControlsRow(layout: .trunk, status: $0.status) }
            .configurationDisplayName("Lock, Unlock, Trunk")
            .description("Lock, unlock, and trunk controls.")
            .supportedFamilies([.accessoryRectangular])
    }
}
@available(watchOS 11.0, *)
private struct UtilityControlsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch-utility-controls", provider: CommandProvider()) { ControlsRow(layout: .utility, status: $0.status) }
            .configurationDisplayName("Start, Trunk, Panic")
            .description("Start, Trunk, and Panic controls.")
            .supportedFamilies([.accessoryRectangular])
    }
}
