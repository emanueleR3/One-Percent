import SwiftUI

/// Compact day navigation and picker per ONE_PERCENT_SPEC.md (Section 6.2, 12)
struct DayPickerView: View {
    @ObservedObject var store: TaskStore
    var onPopoverChange: ((Bool) -> Void)? = nil
    @State private var isShowingCalendarPopover = false

    var body: some View {
        HStack(spacing: 4) {
            // Previous Day Button
            Button {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectPreviousDay()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .frame(width: 18, height: 22)
            }
            .buttonStyle(.plain)
            .help("Previous day")
            .accessibilityLabel("Go to previous day")

            // Day Title Button with Popover
            Button {
                isShowingCalendarPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(store.dateService.formatDayTitle(for: store.selectedDate))
                        .font(IslandTypography.statusLabel)
                        .foregroundStyle(store.dateService.isToday(store.selectedDate) ? IslandPalette.primaryText : IslandPalette.inProgressAccent)

                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(IslandPalette.secondaryText)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .fill(IslandPalette.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .stroke(IslandPalette.border.opacity(0.6), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("Choose date")
            .accessibilityLabel("Selected date: \(store.dateService.formatDayTitle(for: store.selectedDate))")
            .popover(isPresented: $isShowingCalendarPopover, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Button("Today") {
                            store.selectToday()
                            isShowingCalendarPopover = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(IslandPalette.elevatedSurface)
                        .font(IslandTypography.caption)
                        .controlSize(.small)

                        Button("Tomorrow") {
                            store.selectTomorrow()
                            isShowingCalendarPopover = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(IslandPalette.elevatedSurface)
                        .font(IslandTypography.caption)
                        .controlSize(.small)
                    }
                    .padding(.top, 10)

                    DatePicker(
                        "Date",
                        selection: Binding(
                            get: { store.selectedDate },
                            set: { newDate in
                                store.selectDate(newDate)
                                isShowingCalendarPopover = false
                            }
                        ),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(width: 260)
                .background(IslandPalette.background)
            }

            // Next Day Button
            Button {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectNextDay()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .frame(width: 18, height: 22)
            }
            .buttonStyle(.plain)
            .help("Next day")
            .accessibilityLabel("Go to next day")

            // Quick "Today" Jump Button when viewing another day
            if !store.dateService.isToday(store.selectedDate) {
                Button {
                    withAnimation(IslandAnimations.statusTransition) {
                        store.selectToday()
                    }
                } label: {
                    Text("Today")
                        .font(IslandTypography.caption)
                        .foregroundStyle(IslandPalette.completedAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(IslandPalette.completedAccent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help("Jump back to today")
                .accessibilityLabel("Return to today")
            }
        }
        .onChange(of: isShowingCalendarPopover) { _, open in
            onPopoverChange?(open)
        }
    }
}
