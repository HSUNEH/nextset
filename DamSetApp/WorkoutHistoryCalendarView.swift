import SwiftUI
import DamSetCore

/// Calendar-first workout history. Completed workouts are grouped by their
/// local end date so the markers and the detail list stay consistent when the
/// device calendar or time zone changes.
struct WorkoutHistoryCalendarView: View {
    let summaries: [WorkoutSummary]
    let onUpdate: (WorkoutSummary) -> Bool
    let onDelete: (WorkoutSummary) -> Bool

    @State private var range: HistoryCalendarRange
    @State private var visibleDate: Date
    @State private var selectedDate: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        summaries: [WorkoutSummary],
        initialDate: Date? = nil,
        onUpdate: @escaping (WorkoutSummary) -> Bool = { _ in false },
        onDelete: @escaping (WorkoutSummary) -> Bool = { _ in false }
    ) {
        self.summaries = summaries
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        let initialSelection = initialDate
            ?? summaries.map(\.workoutEndTime).max()
            ?? Date()
        _range = State(initialValue: .month)
        _visibleDate = State(initialValue: initialSelection)
        _selectedDate = State(initialValue: initialSelection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                rangePicker
                periodNavigation
                calendarPanel
                selectedDateSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(GymScreenBackground())
        .navigationTitle("Workout Calendar")
        .inlineNavigationTitle()
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
        .onChange(of: range) { _, _ in
            visibleDate = selectedDate
        }
    }

    private var rangePicker: some View {
        Picker("Calendar range", selection: $range) {
            ForEach(HistoryCalendarRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityHint("Switch between monthly and weekly workout history")
    }

    @ViewBuilder
    private var periodNavigation: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                periodTitle
                todayButton
                HStack(spacing: 16) {
                    previousPeriodButton
                    nextPeriodButton
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 12) {
                previousPeriodButton
                VStack(spacing: 2) {
                    periodTitle
                    todayButton
                }
                .frame(maxWidth: .infinity)
                nextPeriodButton
            }
        }
    }

    private var periodTitle: some View {
        Text(periodTitleText)
            .font(.headline.weight(.bold))
            .fontWidth(.condensed)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityAddTraits(.isHeader)
    }

    private var todayButton: some View {
        Button("Today") {
            let today = calendar.startOfDay(for: Date())
            selectedDate = today
            visibleDate = today
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(DamSetDesign.accent)
        .frame(minWidth: 64, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityHint("Returns the calendar to today")
    }

    private var previousPeriodButton: some View {
        periodButton(
            systemName: "chevron.left",
            accessibilityLabel: "Previous \(range.accessibilityName)",
            offset: -1
        )
    }

    private var nextPeriodButton: some View {
        periodButton(
            systemName: "chevron.right",
            accessibilityLabel: "Next \(range.accessibilityName)",
            offset: 1
        )
    }

    private func periodButton(
        systemName: String,
        accessibilityLabel: String,
        offset: Int
    ) -> some View {
        Button {
            movePeriod(by: offset)
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DamSetDesign.steel)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(GymCompactStepperButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var calendarPanel: some View {
        VStack(spacing: 10) {
            weekdayHeader
            LazyVGrid(columns: dayColumns, spacing: 8) {
                ForEach(Array(displayedDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(date)
                    } else {
                        Color.clear
                            .frame(minHeight: 48)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .gymPanel(accent: DamSetDesign.accent.opacity(0.36), cut: 16, padding: 10)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: dayColumns, spacing: 8) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DamSetDesign.steel.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let workoutCount = summaries(on: date).count

        return Button {
            selectedDate = calendar.startOfDay(for: date)
            visibleDate = date
        } label: {
            VStack(spacing: 4) {
                Text(date, format: .dateTime.day())
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .minimumScaleFactor(0.75)

                Circle()
                    .fill(workoutCount > 0 ? (isSelected ? Color.white : DamSetDesign.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                Circle()
                    .fill(isSelected ? DamSetDesign.accent : Color.clear)
                    .padding(2)
            }
            .overlay {
                if isToday && !isSelected {
                    Circle()
                        .stroke(DamSetDesign.steel.opacity(0.82), lineWidth: 1)
                        .padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDate(date))
        .accessibilityValue(dayAccessibilityValue(workoutCount: workoutCount, isToday: isToday))
        .accessibilityHint("Shows workouts completed on this date")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedDateDisplayText)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityLabel(accessibilityDate(selectedDate))
                    .accessibilityAddTraits(.isHeader)
                Text(selectedDateSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)

            if selectedSummaries.isEmpty {
                emptyState
            } else {
                ForEach(selectedSummaries) { summary in
                    NavigationLink {
                        WorkoutSummaryDetailView(
                            summary: summary,
                            allSummaries: summaries,
                            onUpdate: updateSummary,
                            onDelete: onDelete
                        )
                    } label: {
                        WorkoutCalendarSummaryRow(
                            summary: summary,
                            useVerticalLayout: dynamicTypeSize.isAccessibilitySize
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summaryAccessibilityLabel(summary))
                    .accessibilityHint("Opens workout details")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                summaries.isEmpty ? "No workout history yet" : "No workouts this day",
                systemImage: summaries.isEmpty ? "calendar.badge.plus" : "calendar"
            )
        } description: {
            Text(
                summaries.isEmpty
                    ? "Completed workouts will appear on the calendar."
                    : "Choose a date marked with a red dot."
            )
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .cardSurface(accent: DamSetDesign.steelMuted.opacity(0.65))
    }

    private var selectedSummaries: [WorkoutSummary] {
        summaries(on: selectedDate)
            .sorted { $0.workoutEndTime > $1.workoutEndTime }
    }

    private var selectedDateSubtitle: String {
        let count = selectedSummaries.count
        switch count {
        case 0:
            return "No workouts"
        case 1:
            return "1 workout"
        default:
            return "\(count) workouts"
        }
    }

    private var selectedDateDisplayText: String {
        selectedDate.formatted(
            Date.FormatStyle()
                .year()
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
    }

    private var dayColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 32), spacing: 0), count: 7)
    }

    private var displayedDays: [Date?] {
        switch range {
        case .month:
            return monthDays(containing: visibleDate)
        case .week:
            return weekDays(containing: visibleDate).map(Optional.some)
        }
    }

    private var orderedWeekdaySymbols: [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let startIndex = max(0, min(6, localizedCalendar.firstWeekday - 1))
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private var periodTitleText: String {
        let interval = periodInterval(containing: visibleDate, range: range)
        switch range {
        case .month:
            let style = Date.FormatStyle()
                .year()
                .month(.wide)
                .locale(locale)
            return interval.start.formatted(style)
        case .week:
            let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end)
                ?? interval.end
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(locale)
            return "\(interval.start.formatted(style)) – \(endDate.formatted(style))"
        }
    }

    private func monthDays(containing date: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: monthInterval.start) else {
            return [calendar.startOfDay(for: date)]
        }

        let weekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        var days = Array<Date?>(repeating: nil, count: leadingEmptyDays)

        for offset in 0..<dayRange.count {
            if let day = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) {
                days.append(day)
            }
        }

        while !days.isEmpty && !days.count.isMultiple(of: 7) {
            days.append(nil)
        }
        return days
    }

    private func weekDays(containing date: Date) -> [Date] {
        let interval = periodInterval(containing: date, range: .week)
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    private func periodInterval(containing date: Date, range: HistoryCalendarRange) -> DateInterval {
        let component: Calendar.Component = range == .month ? .month : .weekOfYear
        if let interval = calendar.dateInterval(of: component, for: date) {
            return interval
        }

        let start = calendar.startOfDay(for: date)
        let fallbackDays = range == .month ? 1 : 7
        let end = calendar.date(byAdding: .day, value: fallbackDays, to: start)
            ?? start.addingTimeInterval(TimeInterval(fallbackDays * 86_400))
        return DateInterval(start: start, end: end)
    }

    private func movePeriod(by offset: Int) {
        let component: Calendar.Component = range == .month ? .month : .weekOfYear
        guard let destination = calendar.date(byAdding: component, value: offset, to: visibleDate) else {
            return
        }

        visibleDate = destination
        let destinationInterval = periodInterval(containing: destination, range: range)
        selectedDate = preferredSelection(in: destinationInterval)
    }

    private func preferredSelection(in interval: DateInterval) -> Date {
        if let latestWorkout = summaries
            .map(\.workoutEndTime)
            .filter(interval.contains)
            .max() {
            return calendar.startOfDay(for: latestWorkout)
        }

        let today = Date()
        if interval.contains(today) {
            return calendar.startOfDay(for: today)
        }
        return calendar.startOfDay(for: interval.start)
    }

    private func summaries(on date: Date) -> [WorkoutSummary] {
        summaries.filter { calendar.isDate($0.workoutEndTime, inSameDayAs: date) }
    }

    private func updateSummary(_ summary: WorkoutSummary) -> Bool {
        guard onUpdate(summary) else { return false }
        selectedDate = calendar.startOfDay(for: summary.workoutEndTime)
        visibleDate = summary.workoutEndTime
        return true
    }

    private func accessibilityDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .complete, time: .omitted)
                .locale(locale)
        )
    }

    private func dayAccessibilityValue(workoutCount: Int, isToday: Bool) -> String {
        let workoutText: String
        switch workoutCount {
        case 0:
            workoutText = "No workouts"
        case 1:
            workoutText = "1 workout"
        default:
            workoutText = "\(workoutCount) workouts"
        }
        return isToday ? "Today, \(workoutText)" : workoutText
    }

    private func summaryAccessibilityLabel(_ summary: WorkoutSummary) -> String {
        let time = summary.workoutEndTime.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(locale)
        )
        return "\(summary.routineName), \(time), \(summary.totalSets) sets, \(summary.compactTrainingLoadText)"
    }
}

private enum HistoryCalendarRange: String, CaseIterable, Identifiable {
    case month
    case week

    var id: Self { self }

    var title: String {
        switch self {
        case .month: "Month"
        case .week: "Week"
        }
    }

    var accessibilityName: String {
        switch self {
        case .month: "month"
        case .week: "week"
        }
    }
}

private struct WorkoutCalendarSummaryRow: View {
    let summary: WorkoutSummary
    let useVerticalLayout: Bool

    var body: some View {
        Group {
            if useVerticalLayout {
                VStack(alignment: .leading, spacing: 10) {
                    identity
                    metrics
                }
            } else {
                HStack(spacing: 14) {
                    identity
                    Spacer(minLength: 10)
                    metrics
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(accent: DamSetDesign.accent.opacity(0.48))
    }

    private var identity: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DamSetDesign.accent)
                .frame(width: 44, height: 44)
                .background(DamSetDesign.controlFill, in: Circle())
                .overlay {
                    Circle()
                        .stroke(DamSetDesign.steelMuted, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.routineName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary.workoutEndTime.formatted(date: .omitted, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var metrics: some View {
        VStack(alignment: useVerticalLayout ? .leading : .trailing, spacing: 3) {
            Text("\(summary.totalSets) sets")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(summary.compactTrainingLoadText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
