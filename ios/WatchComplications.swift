import SwiftUI
import WidgetKit
import AppIntents

private struct CommandEntry: TimelineEntry { let date: Date }
private struct CommandProvider: TimelineProvider {
    func placeholder(in context: Context) -> CommandEntry { CommandEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (CommandEntry) -> Void) { completion(CommandEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CommandEntry>) -> Void) {
        completion(Timeline(entries: [CommandEntry(date: .now)], policy: .never))
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
    var body: some WidgetConfiguration { StaticConfiguration(kind: "watch-start", provider: CommandProvider()) { _ in CommandComplicationView(title: "Remote Start", symbol: "power", command: "start") }.configurationDisplayName("Remote Start").description("Confirm Remote Start in WireSTART.").supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline]) }
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
    var body: some View {
        AccessoryWidgetGroup("WireSTART") {
            switch layout {
            case .start:
                command(.lock, "lock.fill", .green, "Lock")
                command(.unlock, "lock.open.fill", .red, "Unlock")
                command(.start, "power", .orange, "Remote Start")
            case .trunk:
                command(.lock, "lock.fill", .green, "Lock")
                command(.unlock, "lock.open.fill", .red, "Unlock")
                command(.trunk, "car.rear.fill", .blue, "Trunk")
            case .utility:
                command(.start, "power", .orange, "Remote Start")
                command(.trunk, "car.rear.fill", .blue, "Trunk")
                command(.panic, "speaker.wave.3.fill", .red, "Panic")
            }
        }.accessoryWidgetGroupStyle(.roundedSquare)
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
        StaticConfiguration(kind: "watch-main-controls", provider: CommandProvider()) { _ in ControlsRow(layout: .start) }
            .configurationDisplayName("Lock, Unlock, Start")
            .description("Three WireSTART controls.")
            .supportedFamilies([.accessoryRectangular])
    }
}
@available(watchOS 11.0, *)
private struct TrunkControlsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch-trunk-controls", provider: CommandProvider()) { _ in ControlsRow(layout: .trunk) }
            .configurationDisplayName("Lock, Unlock, Trunk")
            .description("Lock, unlock, and trunk controls.")
            .supportedFamilies([.accessoryRectangular])
    }
}
@available(watchOS 11.0, *)
private struct UtilityControlsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch-utility-controls", provider: CommandProvider()) { _ in ControlsRow(layout: .utility) }
            .configurationDisplayName("Start, Trunk, Panic")
            .description("Remote Start, Trunk, and Panic controls.")
            .supportedFamilies([.accessoryRectangular])
    }
}
