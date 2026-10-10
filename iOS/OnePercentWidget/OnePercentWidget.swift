import WidgetKit
import SwiftUI

@main
struct OnePercentWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FocusLiveActivity()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnePercentToday", provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
        }
        .configurationDisplayName("One Percent")
        .description("Today's progress and your next goals.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: WidgetSnapshot.sample.withDay(AppGroup.dayKey(for: Date())))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let snapshot = context.isPreview
            ? WidgetSnapshot.sample.withDay(AppGroup.dayKey(for: Date()))
            : AppGroup.read()
        completion(TodayEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let snapshot = AppGroup.read()
        // One entry now and one just after midnight (when yesterday's numbers stop being true), and
        // ask for a refresh every half hour in between.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(3600)
        let entries = [TodayEntry(date: now, snapshot: snapshot), TodayEntry(date: midnight, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}

private extension WidgetSnapshot {
    func withDay(_ day: String) -> WidgetSnapshot {
        var copy = self
        copy.day = day
        return copy
    }
}

/// Picks the layout for the family WidgetKit asks for.
struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        TodayWidgetView(entry: entry, family: family)
    }
}
