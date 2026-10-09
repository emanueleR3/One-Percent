import SwiftUI
import OnePercentCore

/// Streak, completion rates and the last twelve weeks at a glance.
struct StatsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = store.tracking

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        tile(L("Streak"), value: "\(summary.currentStreak)", caption: L("best %d", summary.bestStreak), tint: Theme.orange)
                        tile(L("7 days"), value: percent(summary.rate7), caption: summary.rate7 == nil ? L("no goals") : L("goals done"), tint: Theme.mint)
                        tile(L("30 days"), value: percent(summary.rate30), caption: summary.rate30 == nil ? L("no goals") : L("goals done"), tint: Theme.mint)
                        tile(L("Per day"), value: String(format: "%.1f", summary.averagePerDay), caption: L("goals done"), tint: Theme.primaryText)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Last 12 weeks").uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.tertiaryText)
                        Heatmap(columns: summary.heatmap)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("1% score").uppercased())
                                .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.tertiaryText)
                            Text(String(format: "%.2f×", summary.score))
                                .font(.system(size: 38, weight: .semibold, design: .rounded)).foregroundStyle(Theme.primaryText)
                        }
                        Spacer()
                        Text(Lp("%d perfect day", "%d perfect days", summary.perfectDays))
                            .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(L("Stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() }.foregroundStyle(Theme.mint) }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
    }

    private func percent(_ rate: Double?) -> String {
        rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }

    private func tile(_ title: String, value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.tertiaryText)
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
            Text(caption).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

private struct Heatmap: View {
    let columns: [[DayStats?]]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(columns.indices, id: \.self) { column in
                VStack(spacing: 4) {
                    ForEach(columns[column].indices, id: \.self) { row in
                        cell(columns[column][row])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cell(_ day: DayStats?) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color(for: day))
            .aspectRatio(1, contentMode: .fit)
    }

    private func color(for day: DayStats?) -> Color {
        guard let day else { return Color.clear }
        if day.isPerfect { return Theme.mint }
        if day.ratio > 0 { return Theme.mint.opacity(0.25 + 0.5 * day.ratio) }
        return Theme.surface
    }
}
