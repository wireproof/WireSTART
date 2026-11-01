import WidgetKit
import SwiftUI

private let green = Color(red: 0.63, green: 0.94, blue: 0.24)
private let widgetBackground = Color(red: 0.025, green: 0.035, blue: 0.031)

struct ViperEntry: TimelineEntry { let date: Date }
struct ViperProvider: TimelineProvider {
    func placeholder(in context: Context) -> ViperEntry { ViperEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ViperEntry) -> Void) { completion(ViperEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ViperEntry>) -> Void) {
        completion(Timeline(entries: [ViperEntry(date: .now)], policy: .never))
    }
}

struct ViperWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack { AccessoryWidgetBackground(); Image(systemName: "car.fill").font(.system(size: 21, weight: .semibold)) }
            case .accessoryRectangular:
                HStack(spacing: 9) {
                    Image(systemName: "car.fill").font(.title2)
                    VStack(alignment: .leading) { Text("VIPER").font(.headline); Text("Open remote").font(.caption) }
                }
            case .systemMedium:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        brand
                        Spacer(minLength: 0)
                        Text("Your vehicle,\nwithin reach.").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                        Text("OPEN REMOTE  ↗").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(green)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "car.fill")
                        .font(.system(size: 37, weight: .medium)).foregroundStyle(green)
                        .frame(width: 88, height: 88)
                        .background(green.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                }.padding(16)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    brand
                    Spacer(minLength: 0)
                    Image(systemName: "car.fill").font(.system(size: 29, weight: .medium)).foregroundStyle(green)
                    Text("Open remote  ↗").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(16)
            }
        }
        .widgetURL(URL(string: "viperremote://open")!)
        .containerBackground(for: .widget) { widgetBackground }
    }
    private var brand: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.shield.fill").foregroundStyle(green)
            Text("VIPER").tracking(1.5).foregroundStyle(.white)
        }.font(.system(size: 11, weight: .black))
    }

}

@main struct ViperWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ViperRemote", provider: ViperProvider()) { _ in ViperWidgetView() }
            .configurationDisplayName("Viper Remote")
            .description("Open your Bluetooth remote from the Home Screen or Lock Screen.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
            .contentMarginsDisabled()
    }
}
